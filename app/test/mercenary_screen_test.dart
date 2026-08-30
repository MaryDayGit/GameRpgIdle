import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/gear_grid.dart';
import 'package:rift_app/ui/mercenary_screen.dart';

/// Пятый рычаг игры: игрок сам собирает билд. Проверяется не вёрстка, а то,
/// что нажатие действительно меняет снаряжение и способности наёмника.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late GameController controller;
  late Mercenary merc;

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
    dir = Directory.systemTemp.createTempSync('rift_merc_test');
    final profile = PlayerProfile(gold: 10000);

    merc = Mercenary(
      id: 'm1',
      name: 'Корвин',
      rank: MercRank.veteran,
      trait: MercTrait.hardy,
      gear: Equipment(),
      abilities: const [],
    );
    profile.roster.reserve.add(merc);

    // Наполняем сундук: по несколько предметов на каждый тип.
    final rng = Rng(7);
    for (final kind in GearKind.values) {
      for (var i = 0; i < 3; i++) {
        profile.stash.add(ItemFactory.roll(ilvl: 30, rng: rng, kind: kind));
      }
    }

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => DateTime.utc(2026, 7, 1),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // временный каталог мог остаться занятым — не повод валить тест
    }
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MercenaryScreen(controller: controller, mercenary: merc),
    ));
    await tester.pump();
  }

  /// Прокручивает экран до нужного места. В `ListView` то, что за экраном,
  /// вообще не построено, и `find.text` его не увидит.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.byType(Scrollable).first);
    // scrollUntilVisible останавливается, едва край виджета вошёл в экран,
    // а `tap` целится в центр — и промахивается мимо видимой области молча.
    await tester.ensureVisible(target);
    await tester.pump();
  }

  testWidgets('надевание предмета из сундука меняет билд', (tester) async {
    await pump(tester);

    expect(find.text('Снаряжение'), findsOneWidget);
    expect(find.byType(GearGrid), findsOneWidget,
        reason: 'снаряжение должно читаться взглядом, а не построчно');
    expect(merc.gear.filledSlots, 0);

    final stashBefore = controller.profile.stash.length;

    // Открываем слот оружия через сетку — это основной путь на экране;
    // подробный список лежит ниже и на первом экране не виден.
    // pumpAndSettle здесь безопасен: экран билда часов не заводит.
    await tester.tap(find.descendant(
      of: find.byType(GearGrid),
      matching: find.byType(InkWell),
    ).first);
    await tester.pumpAndSettle();

    // Заголовки предметов есть только в открытом листе — на экране надето
    // ничего нет.
    final option = find.textContaining('ур. ·');
    expect(option, findsWidgets, reason: 'лист с вариантами должен открыться');
    await tester.tap(option.first);
    await tester.pumpAndSettle();

    expect(merc.gear.filledSlots, 1, reason: 'предмет должен надеться');
    expect(controller.profile.stash.length, stashBefore - 1,
        reason: 'и исчезнуть из сундука');
  });

  testWidgets('способность встаёт в слот и не занимает два', (tester) async {
    await pump(tester);
    // Список строит только видимое: без прокрутки четвёртый слот ещё не
    // существует, и счёт слотов зависел бы от высоты экрана.
    await scrollTo(tester, find.text('Умения'));

    expect(find.text('Пустой слот'), findsNWidgets(Tuning.abilitySlots));

    await tester.tap(find.text('Пустой слот').first);
    await tester.pumpAndSettle();

    final first = ContentPack.current.abilities.first;
    expect(find.text(first.name), findsOneWidget,
        reason: 'лист способностей должен открыться');
    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();

    expect(merc.abilities, [first.id]);

    // Та же способность во второй слот не встаёт.
    expect(controller.setAbility(merc, 1, first.id), isFalse);
    expect(merc.abilities, [first.id]);
  });

  testWidgets('способности отбираются по тегу', (tester) async {
    // Способностей пятьдесят пять. Плоский список из полусотни карточек — это
    // не выбор билда, а прокрутка: игрок берёт то, что первым попалось.
    await pump(tester);
    await scrollTo(tester, find.text('Умения'));

    await tester.tap(find.text('Пустой слот').first);
    await tester.pumpAndSettle();

    // Отбор по стихии: после нажатия остаются только умения с этим тегом.
    expect(find.text('Все'), findsOneWidget);
    await tester.tap(find.text('Молния').first);
    await tester.pumpAndSettle();

    final lightning = ContentPack.current.abilities
        .where((a) => a.isStarter && a.tags.contains(Tag.lightning))
        .toList();
    expect(lightning, isNotEmpty, reason: 'молния обязана быть с первого рана');
    expect(find.text(lightning.first.name), findsWidgets);

    // А умение без этого тега — пропало.
    final cleave = ContentPack.current.ability('cleave')!;
    expect(find.text(cleave.name), findsNothing);
  });

  testWidgets('теги способности видны в слоте', (tester) async {
    // Тег — это ответ на вопрос «что мне теперь искать в сундуке». Спрятанный
    // в подпись через запятую, он таким ответом не выглядит.
    await pump(tester);
    await scrollTo(tester, find.text('Умения'));

    controller.setAbility(merc, 0, 'spark_bolt');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Разряд'));

    expect(find.text('Молния'), findsWidgets);
    expect(find.text('Чары'), findsWidgets);
  });

  testWidgets('карточка способности разбирает урон по шагам', (tester) async {
    // Строка «×2.9 урона» отвечает на вопрос только тому, кто уже знает
    // устройство игры. Игрок должен увидеть, ОТ ЧЕГО это растёт и почему
    // найденный «+% к урону Огнём» на эту способность не действует.
    await pump(tester);
    controller.setAbility(merc, 0, 'spark_bolt');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Разряд'));

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('ОТ ЧЕГО РАСТЁТ'), findsOneWidget);
    expect(find.text('Сила чар'), findsWidgets,
        reason: 'ось обязана быть названа, а не подразумеваться');
    expect(find.text('ТЕГИ'), findsOneWidget);
    expect(find.text('ТИП УРОНА'), findsOneWidget);
    expect(find.text('ЦЕНА'), findsOneWidget);
  });

  testWidgets('карточка Атаки называет другую ось', (tester) async {
    await pump(tester);
    controller.setAbility(merc, 0, 'cleave');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Рассекающий удар'));

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Урон оружия'), findsWidgets);
    expect(find.text('Сила чар'), findsNothing);
  });

  testWidgets('пустой список множителей объясняет, откуда они берутся',
      (tester) async {
    // У свежего наёмника теговых множителей нет, и молчащее место здесь хуже
    // всего: игрок видел «+% к урону Огнём» на вещи и должен понять, куда это
    // число вообще девается.
    await pump(tester);
    controller.setAbility(merc, 0, 'spark_bolt');
    await tester.pumpAndSettle();

    await scrollTo(tester, find.textContaining('Множителей по тегам'));
    expect(find.textContaining('дерева пассивок'), findsWidgets);
  });

  testWidgets('приказ на развилку выбирается и запирается вместе с лоадаутом',
      (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Приказ на развилку'));

    expect(find.text('Приказ на развилку'), findsOneWidget,
        reason: 'рычаг, которого не видно, игрок не выберет');
    expect(merc.forkPolicy, ForkPolicy.loot);

    await tester.tap(find.text(ForkPolicy.safety.ru));
    await tester.pump();
    expect(merc.forkPolicy, ForkPolicy.safety);

    // И то же самое, что с остальной сборкой: в бездне менять нельзя —
    // спуск уже посчитан, и приказ задним числом переписал бы случившийся ран.
    controller.deploy(merc);
    await tester.pump();
    await tester.tap(find.text(ForkPolicy.echo.ru));
    await tester.pump();
    expect(merc.forkPolicy, ForkPolicy.safety);
  });

  testWidgets('отправка уносит приказ в контракт', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text(ForkPolicy.echo.ru));
    await tester.tap(find.text(ForkPolicy.echo.ru));
    await tester.pump();

    expect(merc.forkPolicy, ForkPolicy.echo, reason: 'нажатие не сработало');
    final contract = controller.deploy(merc);
    expect(contract, isNotNull);
    expect(contract!.forkPolicy, ForkPolicy.echo,
        reason: 'иначе повтор покажет бой, которого не было');
  });

  testWidgets('у наёмника в бездне сборка заперта', (tester) async {
    controller.deploy(merc);
    await pump(tester);

    expect(controller.canEdit(merc), isFalse);
    // «Лоадаут» — слово не из русского языка игрока: на экране
    // говорится «сборка».
    expect(find.textContaining('сборка заперта'), findsOneWidget);

    // Даже прямой вызов действия ничего не меняет.
    final before = merc.gear.filledSlots;
    final item = controller.profile.stash
        .firstWhere((i) => i.kind == GearKind.weapon);
    expect(controller.equip(merc, 0, item), isFalse);
    expect(merc.gear.filledSlots, before);
  });

  testWidgets('сетка снаряжения открывает тот же выбор, что и список',
      (tester) async {
    await pump(tester);

    final grid = find.byType(GearGrid);
    expect(grid, findsOneWidget);

    // Ячейка оружия — первая в раскладке сетки.
    final cells = find.descendant(of: grid, matching: find.byType(InkWell));
    expect(cells, findsNWidgets(9), reason: 'девять слотов');

    await tester.tap(cells.first);
    await tester.pumpAndSettle();

    expect(find.text('Оружие'), findsWidgets, reason: 'открылся выбор оружия');
  });
}
