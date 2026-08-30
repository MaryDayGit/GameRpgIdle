import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/stash_screen.dart';

/// Сундук глазами игрока: что у меня есть → что это за вещь → что я могу
/// с ней сделать.
///
/// Первое замечание с телефона было «нет кнопки рюкзак»: вещи существовали,
/// но посмотреть их было негде. Тест держит именно это — что список вещей
/// открывается, что нажатие на вещь показывает её АФФИКСЫ, и что оттуда есть
/// куда идти дальше.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
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

  /// Несколько вещей в сундуке — как после спуска.
  List<Item> fill(PlayerProfile profile, {int count = 6}) {
    final items = <Item>[];
    for (var i = 0; i < count; i++) {
      final item = ItemFactory.roll(rng: Rng(100 + i), ilvl: 20 + i);
      profile.stash.add(item);
      items.add(item);
    }
    return items;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_stash_test');
    final profile = PlayerProfile.newGame(seed: 4)..gold = 1000;
    fill(profile);

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => DateTime.utc(2026, 7, 1),
      initialSettings: AppSettings(tutorialDone: true),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // мусор во временной папке — не повод валить тест
    }
  });

  /// Открывает карточку вещи.
  ///
  /// Ищем по подписи строки, а не по названию слота: название слота стоит и
  /// на фишке фильтра сверху, и нажатие уходило туда.
  Future<void> openItem(WidgetTester tester, Item item) async {
    await tester.tap(find.textContaining('${item.ilvl} ур.').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: StashScreen(controller: controller),
    ));
    await tester.pump();
  }

  testWidgets('сундук показывает вещи и их количество', (tester) async {
    await pump(tester);

    expect(find.textContaining('Сундук · 6 из'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('нажатие на вещь показывает её аффиксы', (tester) async {
    // Ровно то, что просили: «нажимаешь на вещь и там её аффиксы».
    final item = controller.profile.stash
        .firstWhere((i) => i.affixes.isNotEmpty);

    await pump(tester);
    await openItem(tester, item);

    expect(find.textContaining('качество'), findsWidgets,
        reason: 'карточка обязана показать аффиксы, а не только название');
    expect(find.textContaining('Переплавить'), findsOneWidget);
  });

  testWidgets('вещь надевается прямо из сундука', (tester) async {
    final merc = controller.profile.roster.reserve.first;
    final item = controller.profile.stash
        .firstWhere((i) => merc.gear.slotsFor(i.kind).isNotEmpty);

    await pump(tester);
    await openItem(tester, item);

    await tester.tap(find.text('Надеть'));
    await tester.pump();

    expect(merc.gear.slots.whereType<Item>(), isNotEmpty);
    expect(controller.profile.stash, isNot(contains(item)));
  });

  testWidgets('распыление освобождает место и даёт золото', (tester) async {
    // Без этого игрок не может почистить сундук сам: он чистился только
    // переполнением, то есть за игрока решала игра.
    final item = controller.profile.stash.first;
    final goldBefore = controller.profile.gold;

    await pump(tester);
    await openItem(tester, item);

    await tester.tap(find.textContaining('Переплавить'));
    await tester.pump();

    expect(controller.profile.stash, hasLength(5));
    expect(controller.profile.gold, greaterThan(goldBefore));
  });

  testWidgets('пока наёмник в бездне, надеть не предлагают', (tester) async {
    // Лоадаут заперт с момента отправки и до гибели. Кнопка, которая ничего
    // не сделает, хуже её отсутствия: она читается как поломка.
    final merc = controller.profile.roster.reserve.first;
    controller.deploy(merc);

    await pump(tester);
    await openItem(tester, controller.profile.stash.first);

    expect(find.text('Надеть'), findsNothing);
    expect(find.textContaining('заперто до его гибели'), findsOneWidget);
  });

  testWidgets('пустой сундук говорит, откуда берутся вещи', (tester) async {
    controller.profile.stash.clear();
    await pump(tester);

    expect(find.textContaining('Вещи приносят наёмники'), findsOneWidget);
  });
}
