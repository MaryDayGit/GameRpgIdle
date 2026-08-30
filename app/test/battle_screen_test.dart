import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/descent_replay.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/battle_screen.dart';

/// Боевая сцена показывает ПОВТОР уже посчитанного рана. Если повтор
/// разойдётся с записанным результатом, игрок увидит бой, которого не было.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late GameController controller;
  late Contract contract;
  late DateTime clock;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_battle_test');
    clock = DateTime.utc(2026, 8, 1, 12);

    final profile = PlayerProfile(gold: 50000);
    final merc = Mercenary(
      id: 'm',
      name: 'Тала',
      rank: MercRank.veteran,
      trait: MercTrait.swift,
    );
    profile.roster.reserve.add(merc);

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => clock,
      // Фиксированный сид: без него каждый прогон считал другой ран, и тест
      // на переход между этажами падал раз в пять запусков — сообщая не о
      // поломке, а о том, что в этот раз выпал другой бой.
      seed: 20260801,
    );
    contract = controller.deploy(merc)!;

    // Спуск доводится до конца: при отправке посчитан только отрезок до
    // первой развилки, а повтор боя проверяется на целом ране. Приказ решает
    // за отсутствующего игрока — это и есть спуск, который увидит тот, кто
    // открыл экран боя после гибели.
    controller.profile.refreshContracts(clock.add(const Duration(days: 1)));
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // не важно
    }
  });

  test('повтор догоняет заданный момент и совпадает с результатом', () {
    final replay = DescentReplay(
      contract: contract,
    );

    // Середина спуска: глубина уже не нулевая, но и не финальная.
    final half = contract.result!.totalSeconds / 2;
    replay.seekTo(half);

    expect(replay.snapshot.finished, isFalse);
    expect(replay.snapshot.depth, greaterThan(1));
    expect(replay.snapshot.depth, lessThanOrEqualTo(contract.result!.maxDepth));
    // Либо бой, либо переход между этажами: и то и другое — состояние,
    // а вот пустая волна посреди боя означала бы, что повтор развалился.
    expect(replay.enemies.isNotEmpty || replay.snapshot.resting, isTrue);
    expect(replay.hero.hpFraction, inInclusiveRange(0.0, 1.0));

    // Догоняем до конца — исход обязан совпасть с записанным.
    replay.seekTo(contract.result!.totalSeconds + 60);
    expect(replay.snapshot.finished, isTrue);
    expect(replay.driver.result.maxDepth, contract.result!.maxDepth);
    expect(replay.driver.result.ending, contract.result!.ending);
    expect(replay.driver.result.killedBy, contract.result!.killedBy);
  });

  /// Наёмник для отдельного профиля: контракт из `setUp` уже доведён до
  /// конца, а здесь нужен живой.
  Mercenary walker(String id) => Mercenary(
        id: id,
        name: 'Корвин',
        rank: MercRank.veteran,
        trait: MercTrait.swift,
      );

  test('повтор стоит на развилке там же, где стоит наёмник', () {
    // Повтор, проходящий развилку сам, уходит дальше наёмника: на Заставе
    // «ждёт решения перед этажом 6», а на экране боя — десятый этаж. Один
    // спуск, показанный двумя разными местами, — это и есть обман.
    final p = PlayerProfile(gold: 50000)..roster.reserve.add(walker('w'));
    final contract = p.deploy(p.roster.reserve.first, seed: 4242, now: clock);
    final segment = contract.result!;
    expect(segment.ending, RunEnding.atFork,
        reason: 'отрезок до первой развилки — это и есть весь спуск пока что');

    final replay = DescentReplay(contract: contract);
    replay.seekTo(segment.totalSeconds + 600);
    final waiting = replay.snapshot.depth;

    expect(replay.driver.result.ending, RunEnding.atFork,
        reason: 'повтор обязан встать на той же развилке');
    expect(replay.driver.result.maxDepth, segment.maxDepth);
    // Наёмник стоит ПЕРЕД этажом развилки: пройденных этажей на один меньше.
    expect(waiting, segment.maxDepth + 1);

    // Игрок выбирает путь, не уходя с экрана боя. Повтор, построенный до
    // выбора, с этой секунды показывает уже не тот спуск.
    p.refreshContracts(contract.segmentEndsAtUtc!);
    expect(contract.atFork, isTrue);
    expect(p.chooseFork(contract, Fork.boldIndex, contract.segmentEndsAtUtc!),
        isTrue);

    replay.seekTo(contract.result!.totalSeconds + 600);
    expect(replay.snapshot.depth, greaterThan(waiting),
        reason: 'после решения наёмник идёт дальше — и повтор тоже');
  });

  testWidgets('на развилке экран задаёт вопрос, а не выглядит зависшим',
      (tester) async {
    // Повтор честно замирает вместе с наёмником. Без этой ветки экран
    // показывал бы полоску перехода на ста процентах, остановившиеся часы и
    // ни слова о том, почему всё встало.
    final p = PlayerProfile(gold: 50000)..roster.reserve.add(walker('q'));
    final contract = p.deploy(p.roster.reserve.first, seed: 4242, now: clock);
    p.refreshContracts(contract.segmentEndsAtUtc!);
    expect(contract.atFork, isTrue);

    clock = contract.segmentEndsAtUtc!;
    final own = GameController(
      content: content,
      store: SaveStore(dir),
      profile: p,
      clock: () => clock,
      seed: 20260801,
    );
    addTearDown(own.dispose);

    // Экран боя длинный, и на телефонном окне развилка ушла бы за нижний
    // край: проверять надо содержание, а не длину списка.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: BattleScreen(controller: own, contract: contract),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Развилка'), findsWidgets,
        reason: 'состояние обязано быть названо');
    expect(find.textContaining('Открыт, только пока вы в игре'), findsOneWidget,
        reason: 'третий путь предлагается тому, кто смотрит бой');

    final fork = contract.pendingFork!;
    for (final option in fork.allOptions) {
      expect(find.text(option.name), findsOneWidget,
          reason: 'путь «${option.name}» не предложен');
    }

    // И вопрос действительно решается отсюда: нажатие двигает спуск дальше.
    final standing = contract.result!.maxDepth;
    await tester.tap(find.text(fork.bold.name));
    await tester.pump();

    expect(contract.atFork, isFalse);
    expect(contract.forkChoices, [Fork.boldIndex]);
    expect(contract.result!.maxDepth, greaterThan(standing));

    await tester.pumpWidget(const SizedBox());
  });

  test('повтор разлома идёт под разломом дня', () {
    // Модификатор разлома действует на каждом этаже. Повтор без него — это
    // другой спуск: другие волны, другие враги, другая гибель.
    final p = PlayerProfile(gold: 50000)..roster.reserve.add(walker('r'));
    final contract =
        p.deploy(p.roster.reserve.first, seed: 909, now: clock, rift: true);
    p.refreshContracts(clock.add(const Duration(days: 1)));

    final replay = DescentReplay(contract: contract);
    replay.seekTo(contract.result!.totalSeconds + 600);

    expect(replay.driver.result.maxDepth, contract.result!.maxDepth);
    expect(replay.driver.result.killedBy, contract.result!.killedBy);
    // Время спуска — самая чувствительная подпись рана: волны в разломе
    // вдвое длиннее, и «тот же этаж за другое время» значит другой бой.
    expect(replay.driver.result.totalSeconds,
        closeTo(contract.result!.totalSeconds, 0.001));
    expect(replay.driver.result.gold, closeTo(contract.result!.gold, 0.001));
  });

  test('перемотка назад пересобирает повтор, а не ломает его', () {
    final replay = DescentReplay(
      contract: contract,
    );

    replay.seekTo(contract.result!.totalSeconds / 2);
    final forward = replay.snapshot.depth;

    replay.seekTo(10);
    expect(replay.snapshot.depth, lessThanOrEqualTo(forward));

    replay.seekTo(contract.result!.totalSeconds / 2);
    expect(replay.snapshot.depth, forward,
        reason: 'тот же момент обязан давать то же состояние');
  });

  testWidgets('экран боя показывает этаж и волну', (tester) async {
    // Три секунды от старта — заведомо первая волна первого этажа. Треть
    // рана могла попасть на переход между этажами, где волны нет вовсе.
    clock = contract.startedAtUtc.add(const Duration(seconds: 3));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: BattleScreen(controller: controller, contract: contract),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Этаж'), findsOneWidget);
    expect(find.textContaining('Волна'), findsWidgets);
    expect(find.text('HP наёмника'), findsOneWidget);
    expect(find.textContaining('Вы наблюдаете'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('переход между этажами объяснён, а не выглядит зависанием',
      (tester) async {
    // Отдых занимает пять секунд времени рана. Раньше эти пять секунд экран
    // просто стоял, а потом прыгал вперёд: часы шли, тики — нет.
    final probe = DescentReplay(contract: contract);
    var seconds = 0.0;
    while (!probe.snapshot.resting && seconds < 600.0) {
      probe.seekTo(seconds += 0.1);
    }
    expect(probe.snapshot.resting, isTrue,
        reason: 'переход обязан занимать время рана');

    // Полсекунды ВНУТРЬ перехода, а не на его первый миг: экран перематывает
    // по времени с точностью до миллисекунды, а проба шагает долями секунды и
    // останавливается чуть за границей. Стоять ровно на границе — значит
    // проверять округление, а не то, что переход назван. Отдых длится пять
    // секунд, полсекунды заведомо внутри.
    clock = contract.startedAtUtc
        .add(Duration(milliseconds: ((seconds + 0.5) * 1000).round()));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: BattleScreen(controller: controller, contract: contract),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Переход'), findsWidgets,
        reason: 'пауза обязана быть названа');

    await tester.pumpWidget(const SizedBox());
  });

  test('здоровье и прогресс волны меняются по ходу боя', () {
    // То, ради чего вообще существует экран наблюдения: если перематывать по
    // времени завершённых этажей, повтор всегда встаёт на границу этажа —
    // герой только что отдохнул, волна ещё не начата, и на экране вечные
    // 100 % HP при нулевом прогрессе.
    final replay = DescentReplay(
      contract: contract,
    );

    final total = contract.result!.totalSeconds;
    final hp = <double>{};
    final progress = <double>{};

    for (var i = 1; i <= 40; i++) {
      replay.seekTo(total * i / 41);
      if (replay.snapshot.finished) break;
      hp.add((replay.hero.hpFraction * 100).round() / 100);
      progress.add((replay.snapshot.waveProgress * 100).round() / 100);
    }

    expect(hp.length, greaterThan(3),
        reason: 'здоровье обязано меняться, а не стоять на месте');
    expect(progress.where((p) => p > 0.0 && p < 1.0).length, greaterThan(3),
        reason: 'волну надо заставать в середине, а не только в начале');
  });
}
