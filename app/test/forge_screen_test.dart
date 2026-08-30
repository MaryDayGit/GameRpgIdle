import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/forge_screen.dart';

/// Крафт проверяется через экран: правила уже покрыты тестами ядра, здесь
/// важно, что игрок может до них дотянуться и что операция меняет состояние,
/// а не только текст на кнопке.
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

  Item makeItem({
    GearKind kind = GearKind.amulet,
    int ilvl = 30,
    Rarity rarity = Rarity.rare,
    String affixId = 'max_hp_flat',
    StatKey stat = StatKey.maxHp,
  }) =>
      Item(
        kind: kind,
        ilvl: ilvl,
        rarity: rarity,
        affixes: [
          AffixRoll(
            affixId: affixId,
            stat: stat,
            percentile: 0.95,
            value: 300.0,
          ),
        ],
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_forge_test');
    final profile = PlayerProfile(gold: 1e9, maxDepthEver: 100);
    profile.stash.add(makeItem());

    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile,
      clock: () => DateTime.utc(2026, 10, 1),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // не важно
    }
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: ForgeScreen(controller: controller),
    ));
    await tester.pump();
  }

  testWidgets('разбор превращает предмет в осколок', (tester) async {
    await pump(tester);

    expect(find.textContaining('Осколки · 0 из'), findsOneWidget);

    await tester.tap(find.textContaining('Амулет'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('В осколок'));
    await tester.pumpAndSettle();

    // Операция сперва показывает, что получится, и только потом делает.
    // Плата за извлечение: 95 - 10.
    expect(find.textContaining('осколок качества 85'), findsOneWidget);
    expect(find.textContaining('Остальные свойства'), findsOneWidget);

    await tester.tap(find.text('Разобрать'));
    await tester.pumpAndSettle();

    expect(controller.profile.stash, isEmpty);
    expect(controller.profile.shards, hasLength(1));
    expect(controller.profile.shards.single.quality, 85);
  });

  testWidgets('от операции можно отказаться, и она ничего не сделает',
      (tester) async {
    // Предпросмотр без отказа — это не предпросмотр, а лишний экран.
    await pump(tester);
    final before = controller.profile.gold;

    await tester.tap(find.textContaining('Амулет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перебросить'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(controller.profile.gold, before);
    expect(controller.profile.stash.single.affixes.single.rerolls, 0);
  });

  testWidgets('перекат тратит золото и меняет ролл', (tester) async {
    await pump(tester);

    final before = controller.profile.gold;
    await tester.tap(find.textContaining('Амулет'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Перебросить'));
    await tester.pumpAndSettle();

    // Перекат — лотерея, и границы показываются до оплаты.
    expect(find.textContaining('не хуже:'), findsOneWidget);
    expect(find.textContaining('не лучше:'), findsOneWidget);

    await tester.tap(find.textContaining('Перебросить ·'));
    await tester.pumpAndSettle();

    expect(controller.profile.gold, lessThan(before));
    expect(controller.profile.stash.single.affixes.single.rerolls, 1);
  });

  testWidgets('осколок впечатывается в свободный слот другого предмета',
      (tester) async {
    // Второй предмет — с местом под аффикс и ДРУГИМ аффиксом: одинаковые
    // не впечатываются, они сложились бы в один.
    controller.profile.stash.add(makeItem(
      ilvl: 80,
      rarity: Rarity.relic,
      affixId: 'armor_flat',
      stat: StatKey.armor,
    ));
    await pump(tester);

    // Разбираем первый.
    await tester.tap(find.textContaining('30 ур.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В осколок'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Разобрать'));
    await tester.pumpAndSettle();

    expect(controller.profile.shards, hasLength(1));

    // Впечатываем в оставшийся. Ищем осколок по его качеству: подсказка
    // о разборе ещё висит на экране и содержит то же слово.
    await tester.tap(find.text('85'));
    await tester.pumpAndSettle();
    expect(find.text('свободный слот'), findsOneWidget);

    await tester.tap(find.textContaining('80 ур.').last);
    await tester.pumpAndSettle();

    // Ради этого осколок и носят через раны: тот же перцентиль на более
    // глубокой базе даёт больше, и предпросмотр обязан это показать.
    expect(find.textContaining('пересчитается под уровень'), findsOneWidget);
    await tester.tap(find.text('Впечатать'));
    await tester.pumpAndSettle();

    expect(controller.profile.shards, isEmpty);
    final crafted = controller.profile.stash.single;
    expect(crafted.affixes, hasLength(2));

    // Тот же перцентиль на более глубокой базе даёт больше — ради этого
    // крафт и существует.
    expect(crafted.affixes.last.value, greaterThan(300.0));
  });

  testWidgets('углубление доступно только реликту', (tester) async {
    controller.profile.stash
      ..clear()
      ..add(Item(
        kind: GearKind.ring,
        ilvl: 30,
        rarity: Rarity.relic,
        affixes: const [
          AffixRoll(
            affixId: 'max_hp_flat',
            stat: StatKey.maxHp,
            percentile: 0.9,
            value: 200.0,
          ),
        ],
        relicId: 'seal_of_thousand_eyes',
      ));
    await pump(tester);

    await tester.tap(find.textContaining('Кольцо'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Углубить до 40'), findsOneWidget);
    await tester.tap(find.textContaining('Углубить до 40'));
    await tester.pumpAndSettle();

    // Углубление считается наперёд целиком: видно, каким станет предмет.
    expect(find.textContaining('Сейчас'), findsOneWidget);
    expect(find.textContaining('Станет'), findsOneWidget);

    await tester.tap(find.textContaining('Углубить ·'));
    await tester.pumpAndSettle();

    expect(controller.profile.stash.single.ilvl, 40);
    expect(controller.profile.stash.single.deepenings, 1);
  });
}
