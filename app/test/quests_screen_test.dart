import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/quest_log.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/quests_screen.dart';

/// Журнал заданий.
///
/// Проверяется не вёрстка, а обещание: игрок в любой момент видит, что делать
/// сейчас, сколько осталось и что за это дадут. Задание, о котором надо
/// догадываться, целью не является.
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

  void build({PlayerProfile? profile}) {
    dir = Directory.systemTemp.createTempSync('rift_quests_test');
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: profile ?? PlayerProfile(),
      clock: () => DateTime.utc(2026, 8, 1),
      seed: 1,
    );
  }

  tearDown(() {
    controller.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Временный каталог мог не создаться — падать из-за уборки нельзя.
    }
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: QuestsScreen(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('на старте видно первую цель, а не все сорок четыре',
      (tester) async {
    build();
    await pump(tester);

    final first = ContentPack.current.quest('first_return')!;
    expect(find.text(first.name), findsOneWidget);

    // Цель из середины цепи не показывается: игрок должен видеть следующий
    // шаг, а не простыню.
    final later = ContentPack.current.quest('fire_mastery')!;
    expect(find.text(later.name), findsNothing);
    expect(find.textContaining('открывается дальше по цепочкам'),
        findsOneWidget);
  });

  testWidgets('у задания названа награда — умение', (tester) async {
    build();
    await pump(tester);

    final first = ContentPack.current.quest('first_return')!;
    final reward = ContentPack.current.ability(first.rewardAbility)!;

    expect(find.textContaining('Награда: ${reward.name}'), findsOneWidget);
  });

  testWidgets('накопительная цель показывает, сколько осталось',
      (tester) async {
    final profile = PlayerProfile(maxDepthEver: 9);
    profile.quests.check(const QuestFacts(runsCompleted: 1));
    build(profile: profile);
    await pump(tester);

    // «Глубже» — цель до 15-го этажа, рекорд 9.
    expect(find.text('Глубже'), findsOneWidget);
    expect(find.text('9 из 15'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  testWidgets('цель про один спуск полоски не имеет', (tester) async {
    // «3 из 10» о ней соврало бы: она либо выполнена спуском, либо нет.
    final profile = PlayerProfile(maxDepthEver: 20);
    profile.quests.check(const QuestFacts(runsCompleted: 1, maxDepthEver: 20));
    build(profile: profile);
    await pump(tester);

    expect(find.text('Поджигатель'), findsOneWidget,
        reason: 'цепь Пепла открывается после «Глубже»');
    expect(find.textContaining('из 0.4'), findsNothing);
  });

  testWidgets('выполненное уезжает вниз и названо открытым', (tester) async {
    final profile = PlayerProfile();
    profile.quests.check(const QuestFacts(runsCompleted: 1));
    build(profile: profile);
    await pump(tester);

    final first = ContentPack.current.quest('first_return')!;
    final reward = ContentPack.current.ability(first.rewardAbility)!;

    // Список строит только видимое: выполненное лежит ПОД текущими целями, и
    // без прокрутки его не существует. Это и есть проверяемое свойство —
    // история не занимает место цели.
    await tester.scrollUntilVisible(find.text('ВЫПОЛНЕНО'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('ВЫПОЛНЕНО'), findsOneWidget);
    expect(find.textContaining('Открыто: ${reward.name}'), findsOneWidget);
  });

  testWidgets('счётчик наверху считает по всему контенту', (tester) async {
    build();
    await pump(tester);

    final total = ContentPack.current.quests.length;
    expect(find.textContaining('Выполнено 0 из $total'), findsOneWidget);
  });
}
