import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/echo_tree_screen.dart';

/// Древо — единственное место, где тратится Эхо, и единственный выбор,
/// переживающий смерть наёмника. Проверяется, что выбор действительно есть:
/// узел покупается по одному и закрывает следующий, а не «вкладывается всё».
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

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_tree_test');
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile(echo: 1000),
      clock: () => DateTime.utc(2026, 7, 1),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // временный каталог мог остаться занятым
    }
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: EchoTreeScreen(controller: controller),
    ));
    await tester.pump();
  }

  testWidgets('ветки видны, узлы названы своими именами', (tester) async {
    await pump(tester);

    expect(find.text('Живучесть I'), findsOneWidget);
    expect(find.text('+8 % к максимуму HP'), findsOneWidget);

    // Список строит только видимое, поэтому до дальних веток надо доехать.
    for (final branch in controller.profile.tree.branches) {
      await tester.scrollUntilVisible(find.text(branch.name), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(branch.name), findsOneWidget, reason: branch.name);
    }
  });

  testWidgets('узел покупается и открывает следующий', (tester) async {
    await pump(tester);

    final tree = controller.profile.tree;
    final echoBefore = controller.profile.echo;

    // Второй узел ветки закрыт первым: кнопка есть, но не нажимается.
    expect(tree.isAvailable('blood_hp_2'), isFalse);

    // Первая кнопка цены — это первый узел первой ветки.
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();

    expect(tree.has('blood_hp_1'), isTrue);
    expect(controller.profile.echo, lessThan(echoBefore));
    expect(tree.isAvailable('blood_hp_2'), isTrue);
  });

  testWidgets('без Эха ничего не покупается', (tester) async {
    controller.dispose();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile(),
      clock: () => DateTime.utc(2026, 7, 1),
    );
    await pump(tester);

    expect(controller.canBuyEchoNode, isFalse);
    final buttons = tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton));
    expect(buttons.every((b) => b.onPressed == null), isTrue,
        reason: 'цена видна, но нажать нельзя — так виден потолок');
  });
}
