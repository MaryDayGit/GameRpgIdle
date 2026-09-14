import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/coach_mark.dart';
import 'package:rift_app/ui/onboarding.dart';
import 'package:rift_app/ui/mercenary_screen.dart';
import 'package:rift_app/ui/outpost_screen.dart';
import 'package:rift_app/ui/theme.dart';

/// Сценарий первого запуска: то, что видит человек, впервые открывший игру.
///
/// Проверяется не «сценарий совпадает со списком шагов» — это проверяло бы
/// само себя, — а три свойства, ради которых он написан:
///
///  * он ведёт. На каждом шаге на экране ровно одно место, куда можно нажать,
///    и подсказка называет его словами;
///  * он не врёт. Шаг-задание закрывается тем, что игрок сделал дело, а не
///    кнопкой «Дальше»;
///  * он не мешает. Пропущенное обучение не возвращается, а разделы, которых
///    ещё не было, открываются все разом.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
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
    dir = Directory.systemTemp.createTempSync('rift_onboarding_test');
    clock = DateTime.utc(2026, 6, 1, 12);
  });

  tearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит дескриптор сейва — мусор во временной папке не повод
      // валить тест.
    }
  });

  GameController controllerFor(
    PlayerProfile profile, {
    AppSettings? settings,
  }) =>
      GameController(
        content: content,
        store: SaveStore(dir),
        profile: profile,
        clock: () => clock,
        seed: 20260907,
        initialSettings: settings,
      );

  /// Профиль игрока, который уже закрыл один спуск: есть рекорд, золото,
  /// Эхо, вещь в сундуке — и никого в резерве.
  PlayerProfile afterFirstRun() {
    final profile = PlayerProfile(gold: 400, echo: 30, maxDepthEver: 24);
    profile.quests.runsCompleted = 1;
    profile.stash.add(ItemFactory.roll(
        rng: Rng(3), ilvl: 20, kind: GearKind.weapon, lootQuality: 0));
    profile.refreshTavern(Rng(11));
    return profile;
  }

  /// Прокачивает кадры до того, как слой обучения найдёт подсвеченное место.
  ///
  /// `pumpAndSettle` здесь нельзя: контроллер держит секундный таймер, и
  /// «пока всё успокоится» не наступит никогда.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> openOutpost(
    WidgetTester tester,
    GameController c, {
    double textScale = 1.0,
    Size size = const Size(412, 915),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: riftTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: OutpostScreen(controller: c),
      ),
    ));
    await settle(tester);
  }

  /// Закрывает вступительное окно — с него начинается любой первый запуск.
  Future<void> readIntro(WidgetTester tester) async {
    expect(find.text('Понятно'), findsOneWidget,
        reason: 'первый запуск начинается со вступления');
    await tester.tap(find.text('Понятно'));
    await settle(tester);
  }

  testWidgets('первый запуск доводит игрока до отправки и не даёт её пропустить',
      (tester) async {
    final c = controllerFor(PlayerProfile.newGame(seed: 1));
    addTearDown(c.dispose);

    await openOutpost(tester, c);
    await readIntro(tester);

    // Шаг первый: наёмник, который уже есть. Объясняющий — у него кнопка.
    expect(find.text('Это ваш наёмник'), findsOneWidget);
    expect(find.text('ШАГ 1 ИЗ ${Onboarding.total}'), findsOneWidget,
        reason: 'игрок должен видеть, что обучение кончится, и когда');

    await tester.tap(find.text('Дальше'));
    await settle(tester);

    // Шаг второй: задание. Кнопки «Дальше» у него нет нарочно — обучение,
    // которое проходится нажатием «Дальше», учит только нажимать «Дальше».
    expect(find.text('Отправьте наёмника вниз'), findsOneWidget);
    expect(find.text('Нажмите «Отправить»'), findsOneWidget);
    expect(find.text('Дальше'), findsNothing);

    // Окно в затемнении живое: по подсвеченной кнопке можно нажать.
    await tester.tap(find.text('Отправить').first);
    await settle(tester);

    expect(c.profile.hasActiveDescent, isTrue);
    expect(c.tutorialSeen, contains('deploy'),
        reason: 'задание закрывается делом, а не кнопкой');
    expect(find.text('Отправьте наёмника вниз'), findsNothing);

    // И сразу следующий шаг — про то, что игру теперь можно закрыть.
    expect(find.text('Дальше — без вас'), findsOneWidget);
  });

  testWidgets('обучение доводит игрока через весь первый спуск', (tester) async {
    // Самый важный тест файла: сценарий проходится целиком, теми же
    // нажатиями, что и на телефоне. Порядок шагов тут не описан списком — он
    // проверяется тем, что каждый следующий шаг вообще появляется после
    // предыдущего действия.
    final c = controllerFor(PlayerProfile.newGame(seed: 7));
    addTearDown(c.dispose);

    await openOutpost(tester, c);
    await readIntro(tester);

    // --- Наёмник и отправка ---------------------------------------------------
    expect(find.text('Это ваш наёмник'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await settle(tester);

    expect(find.text('Отправьте наёмника вниз'), findsOneWidget);
    await tester.tap(find.text('Отправить').first);
    await settle(tester);

    final contract = c.activeContract!;
    expect(find.text('Дальше — без вас'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await settle(tester);

    // --- Развилка -------------------------------------------------------------
    clock = contract.segmentEndsAtUtc!.add(const Duration(seconds: 1));
    c.tick();
    await settle(tester);

    expect(contract.atFork, isTrue);
    expect(find.text('Расселина разошлась надвое'), findsOneWidget);

    // Пути на развилке — внутри подсвеченной карточки, и нажать по ним
    // можно, не закрывая подсказку.
    await tester.tap(find.text(contract.pendingFork!.options.first.name));
    await settle(tester);

    expect(contract.forkChoices, isNotEmpty);
    expect(find.text('Расселина разошлась надвое'), findsNothing);

    // --- Гибель и добыча ------------------------------------------------------
    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    c.tick();
    await settle(tester);

    expect(find.text('Гибель — это не проигрыш'), findsOneWidget);
    await tester.tap(find.text('Открыть журнал'));
    await settle(tester);

    // Журнал: шаг переехал вместе с игроком на другой экран.
    expect(find.text('Чем всё кончилось'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await settle(tester);

    await tester.tap(find.textContaining('Забрать'));
    await settle(tester);

    // Разбор добычи — следующий экран и следующий шаг.
    if (c.profile.hasPendingLoot) {
      expect(find.text('Что из этого оставить'), findsOneWidget);
      await tester.tap(find.text('Дальше'));
      await settle(tester);

      await tester.tap(find.textContaining('Разобрать остальное'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
    }

    // Окно «задание выполнено» встаёт поверх: первый спуск закрывает сразу
    // несколько заданий. Закрываем и идём дальше.
    if (find.text('Хорошо').evaluate().isNotEmpty) {
      await tester.tap(find.text('Хорошо'));
      await settle(tester);
    }

    expect(c.profile.quests.runsCompleted, 1,
        reason: 'первый спуск закрыт целиком');

    // --- Второй круг ----------------------------------------------------------
    // Дальше идут объяснения разделов, которые только что открылись. Их
    // порядок не важен, важно что каждое закрывается «Дальше» и что цепочка
    // доходит до найма следующего наёмника.
    for (var i = 0; i < 8 && find.text('Дальше').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Дальше'));
      await settle(tester);
    }

    expect(find.text('Наймите следующего'), findsOneWidget,
        reason: 'после первого спуска резерв пуст, и это следующий шаг');

    // --- Наём, сборка, второй спуск -------------------------------------------
    c.profile.gold += 5000;
    expect(c.hire(c.profile.tavernCandidates.first), isTrue);
    await settle(tester);

    expect(find.text('Наймите следующего'), findsNothing);
    expect(find.text('Теперь есть чем снарядить'), findsOneWidget);

    // «Откройте Сборку» — единственный шаг, который закрывается нажатием:
    // открытый экран не меняет в профиле ни одного числа.
    await tester.tap(find.text('Сборка'));
    await settle(tester);

    expect(c.tutorialSeen, contains('build'));
    expect(find.text('Оденьте наёмника'), findsOneWidget,
        reason: 'шаг переехал на экран сборки вместе с игроком');

    // Сборка объясняется тремя шагами — вещи, умения, приказ, — и пока они
    // идут, экран не отпускает: затемнение глушит и кнопку «назад». Это и
    // есть разница между обучением и подписью на полях.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Дальше'));
      await settle(tester);
    }

    await tester.pageBack();
    await settle(tester);

    // Возвращаемся на Заставу: остались постройки и второй спуск.
    for (var i = 0; i < 4 && find.text('Дальше').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Дальше'));
      await settle(tester);
    }

    expect(find.text('Отправьте второго'), findsOneWidget);
    await tester.tap(find.text('Отправить').first);
    await settle(tester);

    expect(c.profile.hasActiveDescent, isTrue);
    expect(c.tutorialSeen, contains('deployAgain'));
  });

  testWidgets('на экране сборки обучение показывает слоты по очереди',
      (tester) async {
    // Вторая половина сценария живёт на другом экране, и спрашивает она про
    // ОТКРЫТОГО наёмника, а не про первого в резерве.
    final profile = afterFirstRun();
    final merc = MercFactory.roll(Rng(21), idPrefix: 'build');
    profile.roster.reserve.add(merc);

    final c = controllerFor(profile,
        settings: AppSettings(tutorialSeen: {
          Onboarding.introId,
          'roster',
          'deploy',
          'descent',
          'fork',
          'collect',
          'journal',
          'loot',
          'stash',
          'echo',
          'quests',
          'hire',
        }));
    addTearDown(c.dispose);

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: riftTheme(),
      home: MercenaryScreen(controller: c, mercenary: merc),
    ));
    await settle(tester);

    // Три объяснения по порядку — снаряжение, умения, приказ. Ровно то, из
    // чего состоит сборка, и ровно в том порядке, в каком они на экране.
    expect(find.text('Оденьте наёмника'), findsOneWidget);

    // Подсвеченное место живое: слот можно нажать, не закрывая подсказку.
    final item = c.profile.stash.first;
    expect(c.equip(merc, Equipment.slotKinds.indexOf(item.kind), item), isTrue);
    await settle(tester);
    expect(find.text('Оденьте наёмника'), findsOneWidget,
        reason: 'объяснение не исчезает от того, что игрок начал делать');

    await tester.tap(find.text('Дальше'));
    await settle(tester);
    expect(find.text('И выберите умения'), findsOneWidget);

    await tester.tap(find.text('Дальше'));
    await settle(tester);
    expect(find.text('Если вас не будет рядом'), findsOneWidget,
        reason: 'последнее, что решается до отправки, — что делать без вас');

    await tester.tap(find.text('Дальше'));
    await settle(tester);
    expect(find.text('Если вас не будет рядом'), findsNothing,
        reason: 'сборка объяснена целиком — экран отпускает игрока');
  });

  testWidgets('затемнение глушит всё, кроме подсвеченного места',
      (tester) async {
    final c = controllerFor(PlayerProfile.newGame(seed: 2));
    addTearDown(c.dispose);

    await openOutpost(tester, c);
    await readIntro(tester);

    // На первом шаге подсвечена строка наёмника. Справка в шапке экрана —
    // мимо неё, и открыться не должна.
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await settle(tester);

    expect(find.text('Это ваш наёмник'), findsOneWidget,
        reason: 'шаг обучения на месте — справка не открылась поверх него');
    expect(find.text('Как это работает'), findsNothing);
  });

  testWidgets('разделы открываются по мере того, как в них появляется смысл',
      (tester) async {
    final c = controllerFor(PlayerProfile.newGame(seed: 3));
    addTearDown(c.dispose);

    await openOutpost(tester, c);
    await readIntro(tester);

    // Сразу после установки: ни сундука, ни древ, ни построек. Восемь
    // разделов, в которых нечего делать, — это восемь вопросов без ответа.
    expect(find.text('Кузница'), findsNothing);
    expect(find.text('Задания'), findsNothing);
    expect(find.text('Древо Эха'), findsNothing);
    expect(find.text('Пассивки'), findsNothing);
    expect(find.text('ЗАСТАВА'), findsNothing);
    expect(find.text('ТАВЕРНА'), findsNothing);

    // Но то, чем игрок распоряжается прямо сейчас, на месте.
    expect(find.text('Отправить'), findsWidgets);
  });

  testWidgets('после первого спуска разделы на месте', (tester) async {
    final c = controllerFor(afterFirstRun(),
        settings: AppSettings(tutorialSeen: {Onboarding.introId}));
    addTearDown(c.dispose);

    await openOutpost(tester, c);

    // `findsWidgets`, а не `findsOneWidget`: разделы не просто появляются —
    // про каждый из них обучение ещё и говорит, и слово встречается дважды.
    expect(find.text('Задания'), findsWidgets);
    expect(find.text('Древо Эха'), findsWidgets);
    expect(find.text('Кузница'), findsWidgets);
    expect(find.textContaining('Сундук'), findsWidgets);
  });

  testWidgets('пропуск закрывает обучение насовсем и открывает всё сразу',
      (tester) async {
    final c = controllerFor(PlayerProfile.newGame(seed: 4));
    addTearDown(c.dispose);

    await openOutpost(tester, c);
    await readIntro(tester);

    await tester.tap(find.text('Дальше сам'));
    await settle(tester);

    expect(c.settings.tutorialDone, isTrue);
    expect(find.text('Это ваш наёмник'), findsNothing);

    // Пропустивший обучение получает игру целиком, а не обрезанную: раздел,
    // спрятанный навсегда, — это поломка, а не бережность.
    expect(find.text('Кузница'), findsOneWidget);
    expect(find.text('Задания'), findsOneWidget);

    // И обычная подсказка о следующем шаге возвращается на своё место. Это
    // другой текст, из `tutorial.dart`: сценарий кончился, строка осталась.
    expect(find.text('Отправьте его вниз'), findsOneWidget);
  });

  testWidgets('обучение можно пройти заново', (tester) async {
    final c = controllerFor(PlayerProfile.newGame(seed: 5),
        settings: AppSettings(
          tutorialDone: true,
          tutorialSeen: {Onboarding.introId, 'roster'},
        ));
    addTearDown(c.dispose);

    await openOutpost(tester, c);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);

    // Лист настроек прокручивается, и обучение стоит в нём последним: список
    // ленивый, так что до прокрутки этой строки в дереве просто нет. С каждой
    // новой настройкой она уезжает ещё ниже.
    await tester.dragUntilVisible(
      find.text('Обучение'),
      find.byType(ListView).last,
      const Offset(0, -60),
    );
    await settle(tester);

    expect(find.text('Обучение'), findsOneWidget);
    await tester.tap(find.text('Пройти заново'));
    await settle(tester);

    expect(c.settings.tutorialDone, isFalse);
    expect(c.tutorialSeen, isEmpty,
        reason: 'заново — значит с самого начала, а не с того же места');
  });

  testWidgets('обучение не догоняет того, кто его обогнал', (tester) async {
    // Игрок, закрывший четыре спуска, разобрался сам. Ни один из ранних шагов
    // не должен всплыть — ни «это ваш наёмник», ни «откройте журнал».
    final profile = afterFirstRun();
    profile.quests.runsCompleted = 4;
    profile.roster.reserve.add(MercFactory.roll(Rng(9), idPrefix: 'late'));

    final c = controllerFor(profile,
        settings: AppSettings(tutorialSeen: {Onboarding.introId}));
    addTearDown(c.dispose);

    await openOutpost(tester, c);

    expect(find.text('Это ваш наёмник'), findsNothing);
    expect(find.text('Отправьте наёмника вниз'), findsNothing);

    // Опоздавшие шаги погашены молча — и второй раз их уже не считают.
    expect(c.tutorialSeen, contains('roster'));
    expect(c.tutorialSeen, contains('deploy'));

    // Остаётся последний: обучение прощается, а не обрывается на полуслове.
    expect(find.text('Дальше вы сами'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await settle(tester);

    expect(c.settings.tutorialDone, isTrue);
  });

  testWidgets('подсказка, которой не на что указать, не запирает экран',
      (tester) async {
    // Задание нарочно не даёт кнопки «Дальше». Но если места, на которое оно
    // показывает, на экране не оказалось — а экран под затемнением не
    // работает, — без кнопки игрок остался бы запертым.
    var closed = false;

    await tester.pumpWidget(MaterialApp(
      theme: riftTheme(),
      home: TutorialLayer(
        mark: CoachMark(
          id: 'потерянный',
          title: 'Заголовок',
          text: 'Объяснение',
          anchor: 'метки-с-таким-именем-нет',
          hint: 'Нажмите на то, чего нет',
          onLost: () => closed = true,
        ),
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Нажмите на то, чего нет'), findsNothing,
        reason: 'звать нажать на отсутствующее место — это издевательство');

    await tester.tap(find.text('Понятно'));
    expect(closed, isTrue);
  });

  testWidgets('кнопка шага остаётся на экране, даже когда места почти нет',
      (tester) async {
    // Найдено на телефоне: подсвеченная карточка спуска заняла верх экрана,
    // объяснение встало под ней и продолжилось за нижний край — вместе с
    // «Дальше». Нажать было нечего, шаг не закрывался, обучение запиралось.
    const size = Size(320, 560);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      theme: riftTheme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(1.5),
        ),
        child: TutorialLayer(
          mark: CoachMark(
            id: 'длинный',
            title: 'Заголовок в целую строку',
            text: 'Очень длинное объяснение, которое при крупном системном '
                'шрифте занимает половину экрана и не помещается под '
                'подсвеченным местом целиком. Оно обязано прокручиваться, а '
                'не выталкивать кнопку за край экрана вместе с собой.',
            anchor: 'высокая-метка',
            step: 3,
            total: 21,
            onNext: () {},
            onSkip: () {},
          ),
          child: Scaffold(
            body: Column(
              children: [
                // Занимает верхнюю треть: карточке останется полоса снизу.
                TutorialAnchor(
                  id: 'высокая-метка',
                  child: SizedBox(key: key, height: 220, width: 320),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    final button = find.text('Дальше');
    expect(button, findsOneWidget);

    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(size.height),
        reason: 'кнопка, которой шаг закрывается, не уезжает за край');
    expect(rect.top, greaterThanOrEqualTo(0.0));

    // И она работает: до неё можно дотянуться пальцем, а не только глазами.
    await tester.tap(button);
  });

  testWidgets('карточка обучения помещается на узком экране с крупным шрифтом',
      (tester) async {
    // 320×640 при ×1.3 — то же условие, что и у остальной вёрстки
    // (`layout_test.dart`). Карточка обучения перекрывает экран целиком, и
    // обрезанная кнопка на ней означает запертого игрока.
    final c = controllerFor(PlayerProfile.newGame(seed: 6));
    addTearDown(c.dispose);

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('overflowed')) {
        overflows.add(details.exception.toString());
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    await openOutpost(tester, c,
        textScale: 1.3, size: const Size(320, 640));
    await readIntro(tester);

    expect(find.text('Это ваш наёмник'), findsOneWidget);
    expect(find.text('Дальше'), findsOneWidget,
        reason: 'кнопка обязана остаться на экране, а не уехать за край');

    await tester.tap(find.text('Дальше'));
    await settle(tester);

    expect(find.text('Нажмите «Отправить»'), findsOneWidget);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}
