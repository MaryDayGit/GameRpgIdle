import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/passive_tree_def.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/passive_tree.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/passive_tree_screen.dart';

/// Дерево пассивок глазами игрока.
///
/// Живой прогон дал приговор: «дерево странное и не глубокое, везде минуса,
/// слабо чувствуется». Половина этого — про подачу: три класса узлов надо
/// РАЗЛИЧАТЬ, а узел, меняющий правило, надо уметь узнать до того, как ты
/// потратил на дорогу к нему девять очков.
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
      // Рекорд большой: очки даёт глубина, и без неё брать нечего.
      profile: PlayerProfile(maxDepthEver: 200),
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

  /// Дерево — полотно 1600×1600, и на телефонном окне видна только его часть.
  /// Тесту нужно попасть пальцем в конкретный узел, поэтому окно берётся
  /// заведомо большим: проверяется карточка узла, а не прокрутка.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: PassiveTreeScreen(controller: controller),
    ));
    await tester.pump();
  }

  /// Нажимает на узел по его координатам в полотне.
  Future<void> tapNode(WidgetTester tester, PassiveNodeDef node) async {
    // Размер и масштаб берутся у экрана, а не назначаются здесь: со своей
    // копией чисел тест нажимал бы мимо узлов, как только раскладка сменится.
    const canvasSize = treeCanvasSize;
    const scale = treeScreenScale;

    // Полотно ищется по своему размеру, а не «последним CustomPaint»: как
    // только внизу появляется карточка узла, последним становится она.
    final canvas = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == canvasSize && w.height == canvasSize);
    final topLeft = tester.getTopLeft(canvas);
    await tester.tapAt(topLeft +
        Offset(canvasSize / 2 + node.x * scale,
            canvasSize / 2 + node.y * scale));
    await tester.pump();
  }

  testWidgets('видно, сколько очков осталось', (tester) async {
    await pump(tester);
    expect(find.textContaining('${controller.profile.passivePointsLeft}'),
        findsWidgets);
  });

  testWidgets('узел рядом с корнем берётся и снимается', (tester) async {
    await pump(tester);

    final tree = controller.profile.passives;
    final first = tree.node(tree.neighbours(tree.rootId!).first)!;

    await tapNode(tester, first);
    expect(find.text(first.name), findsOneWidget);

    await tester.tap(find.text('Взять'));
    await tester.pump();
    expect(controller.profile.passives.has(first.id), isTrue);

    await tester.tap(find.text('Снять'));
    await tester.pump();
    expect(controller.profile.passives.has(first.id), isFalse);
  });

  testWidgets('класс узла назван словом, а правило подписано', (tester) async {
    // Три класса — это три разных обещания: дорога, награда и размен. Не
    // сказать, который перед тобой, значит показать три одинаковых кружка
    // разного размера.
    final tree = controller.profile.passives;
    final ruleNode = tree.nodes.firstWhere((n) => n.rule != null);
    final keystone =
        tree.nodes.firstWhere((n) => n.kind == PassiveKind.keystone);

    await pump(tester);

    await tapNode(tester, ruleNode);
    expect(find.text('крупный'), findsOneWidget);
    expect(find.text('правило'), findsOneWidget);
    expect(find.text(ruleNode.text), findsOneWidget);

    await tapNode(tester, keystone);
    expect(find.text('ключевой'), findsOneWidget);
    expect(find.text(keystone.text), findsOneWidget,
        reason: 'у ключевого узла есть плата, и она в тексте');
  });
  test('подписи крупных узлов не наезжают друг на друга', () {
    // Наложение подписей нельзя увидеть, глядя на один узел: на девятом
    // кольце три подписанных узла стоят рядом по построению, и каждая
    // подпись по отдельности лежит правильно. Проверять надо весь набор.
    final tree = PassiveTree();
    final labelled = [
      for (final n in tree.nodes)
        if (n.kind != PassiveKind.stat) n,
    ];
    expect(labelled.length, greaterThan(20),
        reason: 'иначе проверять нечего');

    // Ширина подписи оценивается сверху: настоящий TextPainter требует
    // отрисовки, а нам нужна геометрия. Семь пикселей на знак для
    // одиннадцатого кегля — с запасом.
    Size sizeOf(String name) => Size(name.length * 7.0, 14.0);

    const origin = Offset(treeCanvasSize / 2, treeCanvasSize / 2);
    final rects = <Rect>[];
    for (final n in labelled) {
      final size = sizeOf(n.name);
      final center =
          origin + Offset(n.x * treeScreenScale, n.y * treeScreenScale);
      final radius = n.kind == PassiveKind.keystone ? 16.0 : 13.0;
      rects.add(labelTopLeft(center, radius, size) & size);
    }

    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: 'подпись «${labelled[i].name}» накрывает '
              '«${labelled[j].name}»',
        );
      }
    }
  });

}
