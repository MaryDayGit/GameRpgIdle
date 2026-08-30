import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/outpost_screen.dart';

/// Цикл игры целиком, глазами игрока: нанял — отправил — дождался — забрал —
/// вложил. Если он не проходится в тесте, он не проходится и на телефоне.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late DateTime clock;
  late GameController controller;

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
    dir = Directory.systemTemp.createTempSync('rift_ui_test');
    clock = DateTime.utc(2026, 6, 1, 12);
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile.newGame(seed: 1)..gold = 100000,
      clock: () => clock,
      // Сид контроллера, а не настенные часы: без него сид спуска менялся от
      // запуска к запуску, длина первого отрезка гуляла между одним и двумя
      // этажами, и тест падал примерно в половине параллельных прогонов.
      seed: 20260828,
      // Обучение показывается только на первом запуске, и эти тесты не про
      // него: вступление модальное и перехватывало бы нажатия.
      initialSettings: AppSettings(tutorialDone: true),
    );
  });

  tearDown(() {
    controller.dispose();
    // Windows не даёт удалить каталог, пока в нём есть открытые дескрипторы,
    // а последняя запись сейва может ещё не закрыться. Мусор во временной
    // папке — не повод валить тест.
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // не важно
    }
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: OutpostScreen(controller: controller),
    ));
    await tester.pump();
  }

  testWidgets('полный круг: наём, спуск, ожидание, добыча, постройка',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Бездна пуста'), findsOneWidget);
    expect(controller.profile.roster.candidates, isNotEmpty);

    // Новый аккаунт начинает с выданным наёмником: первое действие в игре
    // не должно упираться в «не хватает 250».
    expect(controller.profile.roster.reserve, hasLength(1));

    // --- Наём ----------------------------------------------------------------
    final candidate = controller.profile.roster.candidates.first;
    controller.hire(candidate);
    await tester.pump();

    expect(controller.profile.roster.reserve, contains(candidate));
    expect(find.text('Отправить'), findsWidgets);

    // --- Отправка ------------------------------------------------------------
    await tester.tap(find.text('Отправить').first);
    await tester.pump();

    final contract = controller.activeContract;
    expect(contract, isNotNull, reason: 'наёмник должен уйти вниз');
    // Строка подсказки тоже говорит про бездну — важно, что карточка спуска
    // на месте, а не что слово встречается ровно один раз.
    expect(find.textContaining('в бездне'), findsWidgets);
    // Показывается ПРОШЕДШЕЕ время, а не оставшееся: ран посчитан целиком
    // при отправке, и обратный отсчёт был бы датой гибели наёмника.
    expect(find.textContaining('в бездне'), findsWidgets);
    expect(find.textContaining('осталось'), findsNothing);

    // Пока он там — забирать нечего.
    expect(find.text('Открыть журнал'), findsNothing);

    // --- Ожидание ------------------------------------------------------------
    // Журнал открывается по ходу времени, а не весь сразу. Проверяется на
    // конце отрезка, а не на его середине: в отрезке до первой развилки
    // бывает и один этаж, и половина одного этажа — это ноль пройденных.
    final segmentEnd = contract!.segmentEndsAtUtc!;
    clock = segmentEnd.subtract(const Duration(milliseconds: 1));
    controller.tick();
    await tester.pump();

    expect(contract.descending, isTrue);
    // Часы стоят за миг ДО конца отрезка (иначе контракт уже встал бы на
    // развилке), а глубина спрашивается РОВНО на конце: за миллисекунду до
    // него последний этаж ещё не дописан, и это не ошибка, а определение.
    expect(contract.depthAt(segmentEnd), contract.result!.maxDepth,
        reason: 'к концу отрезка пройдено всё, что в нём есть');
    expect(contract.depthAt(contract.startedAtUtc), 0,
        reason: 'а в начале — ничего');

    // --- Развилка ------------------------------------------------------------
    // То, ради чего спуск переписан на отрезки: между отправкой и гибелью
    // игра спрашивает игрока. Раньше здесь не происходило ничего.
    clock = segmentEnd.add(const Duration(seconds: 1));
    controller.tick();
    await tester.pump();

    expect(contract.atFork, isTrue);
    // Два упоминания, и оба нужны: заголовок карточки и подсказка наверху.
    // Подсказка про развилку обязана вытеснить все остальные — наёмник СТОИТ,
    // и это единственное, что сейчас требует игрока.
    expect(find.text('Наёмник ждёт решения'), findsOneWidget);
    expect(find.textContaining('${contract.mercenary.name} на развилке'),
        findsOneWidget);

    final fork = contract.pendingFork!;
    expect(find.text(fork.options.first.name), findsOneWidget,
        reason: 'путь обязан быть назван, а не показан кнопкой «А»');
    expect(find.text(fork.options.first.minus), findsOneWidget,
        reason: 'плата за путь — половина решения');

    await tester.tap(find.text(fork.options.first.name));
    await tester.pump();

    expect(contract.descending, isTrue, reason: 'выбрал — пошёл дальше');
    expect(contract.forkChoices, [0]);

    // --- Гибель --------------------------------------------------------------
    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();
    await tester.pump();

    expect(contract.awaitingCollection, isTrue);
    expect(find.text('Открыть журнал'), findsOneWidget);

    // --- Добыча --------------------------------------------------------------
    final goldBefore = controller.profile.gold;
    final echoBefore = controller.profile.echo;

    // pumpAndSettle здесь нельзя: контроллер держит секундный таймер, и
    // «подождать, пока всё успокоится» не наступит никогда.
    await tester.tap(find.text('Открыть журнал'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Журнал рассказывает, чем кончилось, и только потом отдаёт добычу.
    expect(find.textContaining('Этажи'), findsOneWidget);
    expect(find.textContaining('Находки'), findsOneWidget);

    // Лента событий ниже витрины — до неё надо долистать.
    // Экран Заставы остался в дереве под журналом — ListView здесь два,
    // и листать надо именно верхний.
    await tester.dragUntilVisible(
      find.textContaining('Что было по дороге'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    expect(find.textContaining('Что было по дороге'), findsOneWidget);

    final collect = find.textContaining('Забрать всё');
    expect(collect, findsOneWidget);
    await tester.tap(collect);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.profile.contracts, isEmpty);
    expect(controller.profile.gold, greaterThan(goldBefore));
    expect(controller.profile.echo, greaterThan(echoBefore));
    // Снаряжение наёмника возвращается в сундук сразу; находки ждут разбора.
    expect(controller.profile.stash, isNotEmpty);
    expect(controller.profile.maxDepthEver, greaterThan(0));

    // --- Задание -------------------------------------------------------------
    // Первый закрытый контракт закрывает «Первое возвращение». Награда, о
    // которой не сказали, — награда, которой не было: умение появилось бы в
    // списке сборки молча, и заметить его можно было бы только зайдя туда.
    expect(controller.profile.quests.isDone('first_return'), isTrue);

    // --- Разбор добычи -------------------------------------------------------
    // Рюкзак бесконечен, и находки ждут решения игрока. Экран открывается
    // сразу после журнала: копить непонятную кучу «на потом» игрок не станет.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Разбор добычи'), findsOneWidget);
    expect(controller.profile.hasPendingLoot, isTrue);

    await tester.tap(find.textContaining('Разобрать остальное за меня'));
    await tester.pump();
    expect(controller.profile.pendingLoot, isEmpty);
    expect(controller.profile.stash, isNotEmpty,
        reason: 'лучшее обязано доехать до сундука');

    // Экран закрывается кнопкой, а не сам: закрытие «по пустоте» срабатывало
    // дважды и вторым разом снимало окно с наградой за задание.
    await tester.tap(find.text('Готово'));
    await tester.pump();

    // Окно заданий приходит после того, как разбор закроется.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Заголовок в единственном или множественном числе — сколько именно
    // целей закрыл первый ран, зависит от того, как глубоко он ушёл.
    expect(find.textContaining('ыполнено'), findsWidgets);
    expect(find.textContaining('Открыто умение'), findsWidgets);

    await tester.tap(find.text('Хорошо'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Бездна пуста'), findsOneWidget);

    // --- Застава -------------------------------------------------------------
    expect(controller.profile.outpost.levelOf(Building.tavern), 0);
    controller.upgrade(Building.tavern);
    await tester.pump();
    expect(controller.profile.outpost.levelOf(Building.tavern), 1);

    // Снимаем экран: он обязан остановить часы за собой.
    await tester.pumpWidget(const SizedBox());
  });

  test('прогресс переживает перезапуск', () async {
    // Обычный тест, а не widget-тест: здесь важен диск, а тело `testWidgets`
    // крутится в поддельном времени, где настоящий ввод-вывод не завершается.
    // Экран для этой проверки и не нужен — проверяется состояние, не пиксели.
    controller.refreshTavern();
    final candidate = controller.profile.roster.candidates.first;
    controller.hire(candidate);
    controller.deploy(candidate);

    final store = SaveStore(dir);
    await store.save(
        SaveData(lastSeenUtc: clock, profile: controller.profile));

    final saved = await store.load();
    expect(saved, isNotNull);

    final restored = GameController(
      content: content,
      store: store,
      profile: saved!.profile,
      clock: () => clock,
    );
    addTearDown(restored.dispose);

    expect(restored.activeContract, isNotNull,
        reason: 'наёмник обязан остаться в бездне после перезапуска');
    expect(restored.profile.roster.deployed, hasLength(1));
    expect(restored.profile.gold, controller.profile.gold);
    expect(restored.activeContract!.result!.maxDepth,
        controller.activeContract!.result!.maxDepth);
  });

  testWidgets('карточка наёмника показывает характеристики до найма',
      (tester) async {
    await pumpScreen(tester);

    final candidate = controller.profile.roster.candidates.first;
    // Нанимать вслепую нельзя: ранг и черта в списке выглядят как слова.
    // Список строит только видимое: подсказка о следующем шаге сдвигает
    // Таверну вниз, и без прокрутки нажатие уходит мимо экрана.
    await tester.scrollUntilVisible(find.text(candidate.name), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(candidate.name));
    await tester.pump();

    await tester.tap(find.text(candidate.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Сила сборки'), findsOneWidget);
    expect(find.text('Черта'), findsOneWidget);
    expect(find.text(candidate.trait.description), findsOneWidget);
    expect(find.textContaining('Нанять за'), findsOneWidget);

    await tester.tap(find.textContaining('Нанять за'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.profile.roster.reserve, contains(candidate));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('сборка билда открывается кнопкой со словом, а не иконкой',
      (tester) async {
    // Прошлая версия этого теста проверяла tooltip — и тем закрепляла ошибку:
    // на телефоне подсказку не видит никто, её надо удерживать пальцем.
    // Игрок так и не нашёл, где одевать наёмника.
    await pumpScreen(tester);

    expect(find.text('Сборка'), findsWidgets,
        reason: 'вход в сборку билда обязан быть подписан словом');

    await tester.tap(find.text('Сборка').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // За кнопкой обе половины билда, а не только вещи: «умений нет, как
    // менять билд — непонятно» было ровно про это.
    expect(find.text('Умения'), findsOneWidget,
        reason: 'кнопка ведёт на экран сборки');
    expect(find.textContaining('Мана'), findsOneWidget,
        reason: 'бюджет маны — часть сборки, а не сюрприз в бою');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('в списке видно, сколько слотов пусто', (tester) async {
    // Иначе игрок не узнает, что снаряжать вообще надо: пустой наёмник
    // выглядит так же, как собранный.
    await pumpScreen(tester);

    final merc = controller.profile.roster.reserve.first;
    expect(
      find.text('Снаряжение ${merc.gear.filledSlots}/${merc.gear.usableSlots}'
          ' · умения ${merc.abilities.length}/'
          '${controller.profile.abilitySlots}'),
      findsOneWidget,
    );
  });

  testWidgets('наёмника можно отозвать, не дожидаясь гибели', (tester) async {
    // GDD §8: застревание в неудачном ране бесит, и выход должен быть на виду.
    await pumpScreen(tester);

    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc);
    expect(contract, isNotNull);
    await tester.pump();

    await tester.tap(find.text('Отозвать наёмника'));
    await tester.pump();

    expect(find.text('Отозвать наёмника?'), findsOneWidget,
        reason: 'необратимое действие спрашивается прямо');

    await tester.tap(find.text('Отозвать'));
    await tester.pumpAndSettle();

    expect(contract!.awaitingCollection, isTrue);
    expect(contract.result!.ending, RunEnding.recalled);
    expect(contract.result!.killedBy, isNull, reason: 'наёмник жив');
  });

  testWidgets('передумать можно — контракт остаётся идти', (tester) async {
    await pumpScreen(tester);

    final contract = controller.deploy(controller.profile.roster.reserve.first);
    await tester.pump();

    await tester.tap(find.text('Отозвать наёмника'));
    await tester.pump();
    await tester.tap(find.text('Пусть идёт дальше'));
    await tester.pumpAndSettle();

    expect(contract!.descending, isTrue);
  });

  testWidgets('Клейма нет на экране, пока оно не открыто', (tester) async {
    // Пустой рычаг на экране новичка — это вопрос без ответа.
    await pumpScreen(tester);

    expect(controller.profile.brandRankUnlocked, 0);
    expect(find.text('Клеймо Бездны'), findsNothing);
  });

  testWidgets('открытое Клеймо выставляется перед спуском', (tester) async {
    // Рекорд растёт только забором добычи, поэтому профиль собирается заново.
    final deep = PlayerProfile(maxDepthEver: 60, gold: 5000);
    deep.roster.reserve.add(controller.profile.roster.reserve.first);

    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: deep,
      clock: () => DateTime.utc(2026, 7, 1),
      // Обучение показывается только на первом запуске, и эти тесты не про
      // него: вступление модальное и перехватывало бы нажатия.
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);
    expect(find.text('Клеймо Бездны'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    expect(deep.brandRank, 2);

    final contract = controller.deploy(deep.roster.reserve.first);
    expect(contract!.brandRank, 2,
        reason: 'Клеймо обязано уйти в контракт снимком');
  });

  testWidgets('лестница Клейма видна: чем открывается ранг и что он даёт',
      (tester) async {
    // Выше рангов «за рекорд» лестница держится доказательствами, и игрок
    // должен видеть, какая из двух причин держит его сейчас, — иначе ранги
    // просто перестают появляться без объяснения.
    final veteran = PlayerProfile(
      maxDepthEver: 100000,
      gold: 5000,
      bestDepthByBrand: {
        balance.Curves.brandRanksByDepth: balance.Curves.brandProofDepth,
      },
    );
    veteran.roster.reserve.add(controller.profile.roster.reserve.first);

    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: veteran,
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);

    expect(veteran.provenBrandRanks, 1);
    expect(
        find.textContaining(
            'следующий ранг: этаж ${balance.Curves.brandProofDepth} на ранге '
            '${balance.Curves.brandRanksByDepth + 1}'),
        findsOneWidget,
        reason: 'дальше рекорда лестницу держит доказательство');
    expect(find.textContaining('Доказано рангов: 1'), findsOneWidget,
        reason: 'доказанный ранг платит очком дерева пассивок');
  });

  testWidgets('без наёмников и без золота Таверна даёт добровольца',
      (tester) async {
    // Состояние достижимо честной игрой: новая игра начинается с нулём
    // золота, и отозванный на втором этаже наёмник приносит меньше задатка.
    // Заработать без наёмника нельзя — без добровольца игра встаёт.
    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile(),
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);

    expect(find.text('даром'), findsOneWidget);
    // Застава — длинный список, и Таверна на телефоне ниже сгиба: нажатие
    // по невидимому виджету уходит в пустоту.
    await tester.ensureVisible(find.text('даром'));
    await tester.pump();
    await tester.tap(find.text('даром'));
    await tester.pump();

    expect(controller.profile.roster.reserve, hasLength(1));
    expect(controller.profile.gold, 0.0);
    expect(find.text('даром'), findsNothing,
        reason: 'наёмник есть — доброволец больше не нужен');
  });

  testWidgets('на экране состояние, объяснение — в нажатии', (tester) async {
    // Восемь описаний построек стояли на главном экране постоянно: числа
    // в них терялись. Описание переехало в карточку постройки, и на экране
    // осталось то, что меняется, — уровень и цена.
    await pumpScreen(tester);

    for (final building in Building.values) {
      // Список строит только видимое, поэтому строку надо сперва показать:
      // иначе «описания нет» доказывалось бы тем, что нет и самой постройки.
      await tester.scrollUntilVisible(find.text(building.ru), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(building.ru), findsOneWidget);
      expect(find.text(building.description), findsNothing,
          reason: '${building.ru}: описание не должно жить на главном экране');
    }
  });

  testWidgets('карточка постройки говорит, что даст следующий уровень',
      (tester) async {
    // Цена без «станет вот так» — это предложение купить кота в мешке.
    await pumpScreen(tester);

    await tester.scrollUntilVisible(find.text(Building.vault.ru), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(Building.vault.ru));
    await tester.pump();
    await tester.tap(find.text(Building.vault.ru));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(Building.vault.description), findsOneWidget);
    expect(find.textContaining('Сейчас:'), findsOneWidget);
    expect(find.textContaining('Станет:'), findsOneWidget);
  });

  testWidgets('улучшение из карточки постройки работает', (tester) async {
    // Рекорд нужен: уровень открывает глубина, а не кошелёк.
    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile(maxDepthEver: 100, gold: 100000),
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);
    // Скроллящихся списков на экране больше одного (полоса рангов Клейма),
    // поэтому список указан явно.
    await tester.scrollUntilVisible(find.text(Building.altar.ru), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(Building.altar.ru));
    await tester.pump();
    await tester.tap(find.text(Building.altar.ru));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.textContaining('Улучшить'));
    await tester.pump();

    expect(controller.profile.outpost.levelOf(Building.altar), 1);
  });

  testWidgets('верёвка названа: видно, откуда начнётся спуск', (tester) async {
    // Спуск, молча начавшийся с двенадцатого этажа, читается как сбой счёта.
    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile(maxDepthEver: 60, gold: 5000),
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);

    expect(
      find.textContaining('Верёвка спущена до этажа '
          '${controller.profile.startDepth}'),
      findsOneWidget,
    );
  });

  testWidgets('два спуска показываются двумя карточками', (tester) async {
    // Контракт, которого не видно, — это контракт, про который забыли.
    controller.dispose();
    final profile = PlayerProfile(
      outpost: Outpost({Building.tavern: Tuning.secondSlotLevel}),
      maxDepthEver: 200,
      gold: 100000,
    );
    for (var i = 0; i < 2; i++) {
      profile.roster.reserve
          .add(MercFactory.roll(Rng(i + 3), idPrefix: 'ui$i'));
    }

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );

    await pumpScreen(tester);
    expect(controller.profile.deploySlots, 2);

    final first = profile.roster.reserve.first;
    final second = profile.roster.reserve.last;
    controller.deploy(first);
    await tester.pump();
    controller.deploy(second);
    await tester.pump();

    expect(find.textContaining('${first.name} в бездне'), findsOneWidget);
    expect(find.textContaining('${second.name} в бездне'), findsOneWidget);
  });

  testWidgets('пока слот один, второй наёмник ждёт и это сказано',
      (tester) async {
    await pumpScreen(tester);

    expect(controller.profile.deploySlots, 1);
    controller.deploy(controller.profile.roster.reserve.first);
    await tester.pump();

    expect(find.text('Слоты заняты'), findsNothing,
        reason: 'наёмников в резерве нет — некому и показывать');
    expect(controller.profile.canDeploy, isFalse);
  });

  testWidgets('первый запуск объясняет цикл, и только один раз',
      (tester) async {
    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile.newGame(seed: 5),
      clock: () => DateTime.utc(2026, 7, 1),
    );

    await pumpScreen(tester);
    await tester.pump();

    expect(find.text('Расселина'), findsOneWidget);
    expect(find.textContaining('нанимаете тех, кто спускается'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    expect(controller.settings.tutorialDone, isTrue);
    expect(find.text('Понятно'), findsNothing);
  });

  testWidgets('подсказка называет следующий шаг и исчезает, когда он сделан',
      (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    // Наёмник выдан новому аккаунту, сундук пуст — очередь за отправкой.
    expect(find.text('Отправьте его вниз'), findsOneWidget);

    await tester.tap(find.text('Отправить').first);
    await tester.pump();

    expect(find.text('Отправьте его вниз'), findsNothing,
        reason: 'подсказка считается от состояния, а не листается вручную');
    expect(find.text('Наёмник внизу'), findsOneWidget);
  });
}
