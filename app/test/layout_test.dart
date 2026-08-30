import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/quest_log.dart';
import 'package:rift/core/sim/crafting.dart';
import 'package:rift/core/sim/daily_rift.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/ability_detail.dart';
import 'package:rift_app/ui/battle_screen.dart';
import 'package:rift_app/ui/echo_tree_screen.dart';
import 'package:rift_app/ui/forge_screen.dart';
import 'package:rift_app/ui/help_screen.dart';
import 'package:rift_app/ui/journal_screen.dart';
import 'package:rift_app/ui/mercenary_screen.dart';
import 'package:rift_app/ui/mercenary_stats.dart';
import 'package:rift_app/ui/outpost_screen.dart';
import 'package:rift_app/ui/passive_tree_screen.dart';
import 'package:rift_app/ui/quests_screen.dart';
import 'package:rift_app/ui/stash_screen.dart';

/// Вёрстка: текст не вылезает за экран и не превращается в «…».
///
/// Живой прогон дал это отдельным замечанием: «внимательно пересмотри везде
/// вёрстку, чтобы тексты не выходили за рамки и не превращались в …».
/// Пересмотреть глазами можно один раз; следующая же правка текста сломает
/// всё заново — русские слова длиннее английских, и «Восстановление» шире
/// любой колонки, рассчитанной на «Regen».
///
/// Поэтому проверка живёт тестом. Каждый экран разворачивается на **узком**
/// экране (320 логических точек — уже, чем любой современный телефон) и с
/// **увеличенным системным шрифтом** (×1.3 — то, что включает половина людей
/// старше сорока). Переполнение `Row`/`Column` Flutter сообщает исключением,
/// и тест его ловит.
///
/// Что тест НЕ ловит: обрезание в «…» там, где стоит `TextOverflow.ellipsis`.
/// Такое место должно быть осознанным — и оно ровно одно, в ленте боя, где
/// строка заведомо длиннее экрана и обрезать её правильно.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late GameController controller;
  late PlayerProfile profile;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  /// Профиль, у которого всё наполнено: пустой экран не переполняется никогда,
  /// и проверять его бессмысленно.
  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_layout_test');

    profile = PlayerProfile(
      gold: 1e6,
      echo: 5000,
      maxDepthEver: 120,
      outpost: Outpost({for (final b in Building.values) b: 4}),
    );

    for (var i = 0; i < 3; i++) {
      profile.roster.reserve.add(MercFactory.roll(Rng(i + 1), idPrefix: 'l$i'));
    }

    // Вещи всех типов: длина строки свойства зависит и от типа, и от того,
    // сколько свойств выпало. Редкость набирается сама — роллов хватает.
    final rng = Rng(42);
    for (final kind in GearKind.values) {
      for (var i = 0; i < 3; i++) {
        profile.stash.add(ItemFactory.roll(
            rng: rng, ilvl: 90, kind: kind, lootQuality: 2.0));
      }
    }
    for (var i = 0; i < 6; i++) {
      final item = profile.stash[i];
      if (item.affixes.isNotEmpty) {
        profile.shards.add(Crafting.extract(item, 0));
      }
    }

    // Задания: часть закрыта, часть открыта — на экране есть оба раздела.
    profile.quests.check(const QuestFacts(
      runsCompleted: 6,
      maxDepthEver: 60,
      relicsFound: 2,
      bossesKilled: {'ash_lord', 'void_devourer'},
    ));

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => DateTime.utc(2026, 8, 1),
      seed: 7,
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Временный каталог мог не создаться — падать из-за уборки нельзя.
    }
  });

  /// Самый узкий телефон, который стоит поддерживать, и крупный системный
  /// шрифт. Если верстка держится здесь — она держится везде.
  const narrow = Size(320, 640);

  Future<void> show(WidgetTester tester, Widget screen,
      {double textScale = 1.0, Size size = narrow}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: screen,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Переполнение Flutter сообщает исключением. Забрать его надо явно —
  /// иначе тест упадёт где-то дальше и с непонятным следом.
  void expectNoOverflow(WidgetTester tester, String where) {
    final error = tester.takeException();
    if (error == null) return;

    // Подробности Flutter пишет в диагностику ошибки — без них в отчёте
    // остаётся «на 74 точки вправо» и ни слова о том, где именно.
    final details = error is FlutterError
        ? error.diagnostics.map((d) => d.toString()).join(' | ')
        : '$error';
    fail('$where: вёрстка не помещается в экран. $details');
  }

  /// Экраны, которые проверяются целиком. Каждый — с наполненным профилем.
  Map<String, Widget Function()> screens() => {
        'Застава': () => OutpostScreen(controller: controller),
        'Сборка': () => MercenaryScreen(
            controller: controller, mercenary: profile.roster.reserve.first),
        'Задания': () => QuestsScreen(controller: controller),
        'Сундук': () => StashScreen(controller: controller),
        'Кузница': () => ForgeScreen(controller: controller),
        'Древо Эха': () => EchoTreeScreen(controller: controller),
        'Пассивки': () => PassiveTreeScreen(controller: controller),
        'Справка': () => const HelpScreen(),
      };

  group('узкий экран', () {
    for (final entry in screens().entries) {
      testWidgets('${entry.key}: ничего не вылезает', (tester) async {
        await show(tester, entry.value());
        expectNoOverflow(tester, entry.key);
      });
    }
  });

  group('крупный системный шрифт', () {
    // Полтора кегля — не экзотика: это системная настройка, которую включают
    // ради читаемости. Верстка, рассыпающаяся от неё, рассыпается у реальных
    // людей, а не у выдуманных.
    for (final entry in screens().entries) {
      testWidgets('${entry.key}: держит ×1.3', (tester) async {
        await show(tester, entry.value(), textScale: 1.3);
        expectNoOverflow(tester, '${entry.key} ×1.3');
      });
    }
  });

  testWidgets('журнал спуска помещается', (tester) async {
    final contract = controller.deploy(profile.roster.reserve.first)!;
    await show(
      tester,
      JournalScreen(contract: contract, onCollect: () {}),
    );
    expectNoOverflow(tester, 'Журнал');
  });

  testWidgets('журнал спуска держит ×1.3', (tester) async {
    final contract = controller.deploy(profile.roster.reserve.first)!;
    await show(
      tester,
      JournalScreen(contract: contract, onCollect: () {}),
      textScale: 1.3,
    );
    expectNoOverflow(tester, 'Журнал ×1.3');
  });

  testWidgets('карточка умения помещается на узком экране', (tester) async {
    // Разбор умения — самая плотная таблица в игре: подпись, число и
    // пояснение в одной строке. Проверяется на самом длинном умении.
    final merc = profile.roster.reserve.first;
    final stats = profile.heroProfileFor(merc).aggregate();

    for (final id in ['thunder_totem', 'coup_de_grace', 'quickened_mind']) {
      final def = ContentPack.current.ability(id)!;
      await show(
        tester,
        Scaffold(body: AbilityDetailSheet(def: def, stats: stats)),
        textScale: 1.3,
      );
      expectNoOverflow(tester, 'Карточка «${def.name}»');
    }
  });

  testWidgets('лист характеристик помещается и всё называет', (tester) async {
    // Самый плотный экран в игре: два десятка строк «название — значение»
    // с расшифровкой под каждой. Русские названия длинные, и «Восстановление
    // маны» с числом справа — ровно то место, где вёрстка ломается первой.
    final merc = profile.roster.reserve.first;
    await show(
      tester,
      Scaffold(
        body: MercenaryStatsSheet(
          mercenary: merc,
          profile: profile.heroProfileFor(merc),
          depth: 60,
        ),
      ),
      textScale: 1.3,
    );
    expectNoOverflow(tester, 'Характеристики ×1.3');

    // Ради чего лист и делался: перед спуском видно живучесть по стихиям.
    // Список проверяется поимённо, а не счётчиком строк: пропавшее
    // сопротивление холоду счётчик бы не заметил.
    //
    // С прокруткой, потому что список ленивый: без неё проверялась бы только
    // верхняя треть, а вёрстка ломается как раз внизу, где строки длиннее.
    for (final label in [
      'Максимум HP',
      'Броня',
      'Огню',
      'Холоду',
      'Молнии',
      'Пустоте',
      'Урон оружия',
      'Сила чар',
      'Скорость атаки',
      'Запас маны',
      'Вампиризм',
      'Находимое золото',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 120,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget,
          reason: 'в характеристиках нет строки «$label»');
      expectNoOverflow(tester, 'Характеристики у строки «$label»');
    }

    // Дробные величины не округляются до целого. База восстановления HP —
    // 0.5, и `money` показывал «1», то есть вдвое больше правды. Ошибка тем
    // опаснее, что выглядит как round number.
    await tester.scrollUntilVisible(find.text('Восстановление HP'), -120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('0.5 в секунду'), findsOneWidget,
        reason: 'восстановление HP округлилось и стало враньём');

    // Знак поправки называется словом. Черта «Погорелица» ЗАБИРАЕТ скорость
    // атаки, и «база 1.20 и -10 % сверху» читалось как опечатка: «сверху»
    // обещает прибавку, а минус её отнимает в той же строке.
    expect(find.textContaining('сверху -'), findsNothing,
        reason: 'отрицательная поправка не может быть «сверху»');
  });

  testWidgets('карточка развилки помещается и называет третий путь',
      (tester) async {
    // Самая плотная карточка на Заставе: три пути, у каждого имя, плата,
    // награда и разбор платы против сборки. Четыре строки в кнопке, которая
    // в теме рассчитана на одну.
    final merc = profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    profile.refreshContracts(contract.segmentEndsAtUtc!);
    expect(contract.atFork, isTrue, reason: 'проверять нечего без развилки');

    await show(tester, OutpostScreen(controller: controller), textScale: 1.3);

    // Вступление модальное и перекрывает всё: без него тест «не находил»
    // карточку, которая на самом деле была на месте.
    if (find.text('Понятно').evaluate().isNotEmpty) {
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
    }
    expectNoOverflow(tester, 'Развилка ×1.3');

    // Экран 320×640 при шрифте ×1.3 — карточка ниже сгиба, и ленивый список
    // её не строит. Доскроллить обязан тест, а не игрок: он-то доскроллит.
    //
    // Прокрутка руками и от НИЖНЕГО края: и `scrollUntilVisible`, и `drag`
    // тянут за середину списка, а там лежит горизонтальная лента кнопок
    // («Сундук», «Кузница», «Задания») — она перехватывает жест и прокручивает
    // себя вбок вместо страницы вниз.
    final list = find.byType(ListView).first;
    Future<void> scrollTo(Finder target) async {
      for (var i = 0; i < 25 && target.evaluate().isEmpty; i++) {
        final box = tester.getRect(list);
        await tester.dragFrom(
          Offset(box.center.dx, box.bottom - 24),
          const Offset(0, -160),
        );
        await tester.pump();
      }
    }

    final fork = contract.pendingFork!;
    for (final option in fork.allOptions) {
      await scrollTo(find.text(option.name));
      expect(find.text(option.name), findsOneWidget,
          reason: 'путь «${option.name}» не показан');
      expectNoOverflow(tester, 'Развилка у пути «${option.name}»');
    }

    expect(find.text('Открыт, только пока вы в игре'), findsOneWidget,
        reason: 'третий путь обязан быть подписан, иначе это третья '
            'одинаковая кнопка');
  });

  testWidgets('разлом дня помещается и назван до отправки', (tester) async {
    // Разлом отличается от обычного спуска ровно модификатором, и узнавать
    // это из журнала было бы поздно: решение принимается до отправки.
    await show(tester, OutpostScreen(controller: controller), textScale: 1.3);
    if (find.text('Понятно').evaluate().isNotEmpty) {
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
    }

    final list = find.byType(ListView).first;
    for (var i = 0; i < 25 && find.text('Разлом дня').evaluate().isEmpty; i++) {
      final box = tester.getRect(list);
      await tester.dragFrom(
          Offset(box.center.dx, box.bottom - 24), const Offset(0, -160));
      await tester.pump();
    }

    expect(find.text('Разлом дня'), findsOneWidget);
    expect(find.textContaining(DailyRift.on(controller.now).modifier.name),
        findsWidgets,
        reason: 'модификатор дня обязан быть назван до отправки');
    expectNoOverflow(tester, 'Разлом дня ×1.3');
  });

  testWidgets('экран боя помещается', (tester) async {
    final contract = controller.deploy(profile.roster.reserve.first)!;
    await show(
      tester,
      BattleScreen(controller: controller, contract: contract),
      textScale: 1.3,
    );
    expectNoOverflow(tester, 'Бой ×1.3');
  });

  testWidgets('экран боя на развилке помещается и задаёт вопрос',
      (tester) async {
    // Самое плотное состояние боевого экрана: арена, полоски, лента и три
    // пути развилки с разбором платы — всё в одном столбце. Раньше здесь
    // висел прогноз в три строки, теперь карточка вчетверо выше.
    final contract = controller.deploy(profile.roster.reserve.first)!;
    profile.refreshContracts(contract.segmentEndsAtUtc!);
    expect(contract.atFork, isTrue, reason: 'проверять нечего без развилки');

    await show(
      tester,
      BattleScreen(controller: controller, contract: contract),
      textScale: 1.3,
    );
    expectNoOverflow(tester, 'Бой на развилке ×1.3');

    expect(find.textContaining('Развилка'), findsWidgets,
        reason: 'остановку надо назвать: замерший экран читается как '
            'зависший');

    // Низ экрана боя прокручивается — карточка развилки лежит ниже сгиба.
    final list = find.byType(SingleChildScrollView).last;
    final fork = contract.pendingFork!;
    for (final option in fork.allOptions) {
      for (var i = 0; i < 25 && find.text(option.name).evaluate().isEmpty; i++) {
        final box = tester.getRect(list);
        await tester.dragFrom(
            Offset(box.center.dx, box.bottom - 24), const Offset(0, -160));
        await tester.pump();
      }
      expect(find.text(option.name), findsOneWidget,
          reason: 'путь «${option.name}» не показан на экране боя');
      expectNoOverflow(tester, 'Бой на развилке, путь «${option.name}»');
    }
  });

  testWidgets('выбор умения помещается', (tester) async {
    // Лист выбора — это отбор по тегам, длинные названия и подписи в одной
    // строке: место, где перенос нужнее всего.
    final merc = profile.roster.reserve.first;
    await show(tester, MercenaryScreen(controller: controller, mercenary: merc));
    await tester.pump();

    final slot = find.text('Пустой слот');
    if (slot.evaluate().isNotEmpty) {
      await tester.tap(slot.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectNoOverflow(tester, 'Выбор умения');
    }
  });

  testWidgets('первый экран обучения помещается целиком', (tester) async {
    // Четыре абзаца в диалоге на экране 320×640 при крупном шрифте — ровно
    // тот случай, когда содержимое не влезает и молча обрезается.
    controller.settings.tutorialDone = false;
    await show(tester, OutpostScreen(controller: controller), textScale: 1.3);
    await tester.pump(const Duration(milliseconds: 400));

    expectNoOverflow(tester, 'Обучение');
    expect(find.text('Понятно'), findsOneWidget,
        reason: 'кнопка обязана остаться на экране, а не уехать за край');
  });
}
