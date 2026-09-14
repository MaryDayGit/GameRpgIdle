import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/lair_battle_screen.dart';
import 'package:rift_app/ui/lair_screen.dart';
import 'package:rift_app/ui/outpost_screen.dart';
import 'package:rift_app/ui/strings.dart';
import 'package:rift_app/ui/theme.dart';

/// Логова глазами игрока: открылись — вызвал — увидел исход. Тест держит
/// путь, а не числа: сколько стоит круг и на каком он этаже, решает баланс.
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

  GameController make(PlayerProfile profile) => GameController(
        content: content,
        store: SaveStore(dir),
        profile: profile,
        clock: () => DateTime.utc(2026, 9, 14, 12),
        seed: 20260914,
        initialSettings: AppSettings(tutorialDone: true),
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_lair_test');
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит файл сейва открытым — мусор во временной папке не
      // повод валить тест.
    }
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: riftTheme(), home: home));
    await tester.pump();
  }

  testWidgets('до порога на Заставе логов нет', (tester) async {
    controller = make(PlayerProfile.newGame(seed: 1)..gold = 1000);
    await pump(tester, OutpostScreen(controller: controller));

    // По названию, а не по иконке: щит на Заставе рисуют и другие разделы.
    expect(find.text(S.lairsTitle), findsNothing);
  });

  testWidgets('вызов стража: выбор наёмника, бой, исход, взятый круг',
      (tester) async {
    final profile = _veteran();
    controller = make(profile);
    final guardian = Bestiary.guardians.first;
    final merc = profile.roster.reserve.first;

    await pump(tester, LairScreen(controller: controller));

    // Умения видны до вызова: «чем идти» решается по ним.
    expect(find.textContaining(guardian.skills.first.name), findsOneWidget);

    final button = find.byKey(Key('lair-challenge-${guardian.id}'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('lair-merc-${merc.id}')));
    // Экран боя крутится тикером и сценой Flame — `pumpAndSettle` на нём не
    // дождётся тишины никогда. Кадры шагами.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Исход записан ДО показа: экран его повторяет, а не решает.
    expect(profile.lairCircles[guardian.id], 1);
    expect(profile.lastLairChallenge?.fight.won, isTrue);
    expect(find.byType(LairBattleScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('lair-skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('lair-outcome-ok')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lair-outcome-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LairBattleScreen), findsNothing,
        reason: 'после исхода игрок возвращается в логово');
    // Карточка перешла ко второму кругу.
    expect(
      find.textContaining('${balance.Curves.lairDepth(2)}'),
      findsWidgets,
    );
  });
}

/// Игрок у порога логов: рекорд, золото, наёмник в резерве и сундук вещей,
/// с которыми первый круг берётся наверняка.
PlayerProfile _veteran() {
  final p = PlayerProfile(
    maxDepthEver: balance.Curves.lairUnlockDepth,
    gold: 1e40,
  );
  p.roster.reserve.add(MercFactory.roll(
    Rng.stream(5, 0, 0, RngPurpose.tavern),
    tavernLevel: 0,
    idPrefix: 'lairui',
  ));
  final rng = Rng.stream(9, 600, 0, RngPurpose.lootRoll);
  for (final kind in Equipment.slotKinds) {
    p.stash.add(ItemFactory.roll(ilvl: 600, rng: rng, kind: kind));
  }
  return p;
}
