import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift_app/data/account.dart';
import 'package:rift_app/data/cloud_save.dart';
import 'package:rift_app/data/cloud_sync.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/account_tile.dart';
import 'package:rift_app/ui/strings.dart';

/// Аккаунт и расхождение сейвов — глазами игрока.
///
/// Проверяется не «виджет построился», а обещания, нарушение которых стоит
/// прогресса: диалог расхождения нельзя закрыть мимо кнопок, и выбор в нём
/// действительно меняет то, во что играют.
///
/// ## Почему половина проверок — не `testWidgets`
///
/// `testWidgets` крутит ФЕЙКОВЫЕ часы: настоящая запись на диск внутри него
/// не завершается никогда, потому что событийный цикл, который её завершает,
/// не проворачивается. А всё, что здесь проверяется, кончается записью
/// файла.
///
/// Поэтому разделено по месту исполнимости: `testWidgets` отвечает за то,
/// что игрок ВИДИТ и куда нажимает, обычный `test` — за то, что после
/// нажатия происходит с сейвом. Попытка проверить второе первым дала бы
/// не проверку, а трёхминутное зависание.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late FakeCloudSaveStore cloud;
  late FakeAccountService account;
  late SaveStore store;
  late CloudMirror mirror;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rift_account_ui');
    cloud = FakeCloudSaveStore();
    account = FakeAccountService(uid: 'uid_1');
    await account.signInSilently();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  SaveData save({double gold = 100, int depth = 0, int runs = 0}) {
    final profile = PlayerProfile(gold: gold, maxDepthEver: depth);
    profile.quests.runsCompleted = runs;
    return SaveData(
      lastSeenUtc: DateTime.utc(2026, 9, 1),
      profile: profile,
      seasonId: Season.current.id,
    );
  }

  /// Готовит расхождение: в облаке сорок семь этажей с планшета, на
  /// телефоне — своя игра на двенадцать, которая в облако не уезжала.
  ///
  /// Собирается в [setUp], а не в теле теста: здесь настоящая запись на
  /// диск, а внутри `testWidgets` она не завершится.
  Future<GameController> conflicted() async {
    final tabletDir = Directory('${dir.path}/tablet')..createSync();
    final tablet = SaveStore(tabletDir, deviceId: 'tablet')
      ..accountId = 'uid_1';
    await cloud.push(
      uid: 'uid_1',
      data: await tablet.save(save(gold: 9000, depth: 47, runs: 12)),
    );

    store = SaveStore(dir, deviceId: 'phone')..accountId = 'uid_1';
    await store.save(save(gold: 500, depth: 12, runs: 2));

    mirror = CloudMirror(store: store, cloud: cloud, account: account);
    final pending = await mirror.resolveOnBoot();

    return GameController(
      content: content,
      store: store,
      profile: (await store.load())!.profile,
      account: account,
      mirror: mirror,
      initialSettings: AppSettings(tutorialDone: true),
    )..pendingSync = pending;
  }

  Widget host(GameController c) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                AccountTile(controller: c),
                TextButton(
                  onPressed: () => showSyncConflictDialog(context, c),
                  child: const Text('открыть'),
                ),
              ],
            ),
          ),
        ),
      );

  group('строка аккаунта', () {
    testWidgets('анонимному говорят, что он потеряет, а не «войдите»',
        (tester) async {
      final c = GameController(
        content: content,
        store: SaveStore(dir),
        profile: PlayerProfile.newGame(seed: 1),
        account: account,
        initialSettings: AppSettings(tutorialDone: true),
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(host(c));

      expect(find.text(S.accountAnonymousAbout), findsOneWidget);
      expect(find.text(S.accountLink), findsOneWidget);
    });

    testWidgets('привязанный показывает почту и предлагает выйти',
        (tester) async {
      await account.linkGoogle();
      final c = GameController(
        content: content,
        store: SaveStore(dir),
        profile: PlayerProfile.newGame(seed: 1),
        account: account,
        initialSettings: AppSettings(tutorialDone: true),
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(host(c));

      expect(find.textContaining('test@example.com'), findsOneWidget);
      expect(find.text(S.accountSignOut), findsOneWidget);
    });
  });

  group('диалог расхождения', () {
    late GameController c;

    // Фикстура собирается здесь: `setUp` идёт вне фейковых часов, и запись
    // на диск в нём завершается по-настоящему.
    setUp(() async => c = await conflicted());
    tearDown(() => c.dispose());

    testWidgets('показывает оба сейва цифрами, а не датами', (tester) async {
      expect(c.hasPendingSync, isTrue);

      await tester.pumpWidget(host(c));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      // Выбирают по этим числам: даты у idle-игры почти всегда соседние.
      expect(find.text(S.syncSummary(12, 2, 0)), findsOneWidget);
      expect(find.text(S.syncSummary(47, 12, 0)), findsOneWidget);
      expect(find.text(S.syncThisPhone), findsNWidgets(2));
      expect(find.text(S.syncCloud), findsNWidgets(2));
    });

    testWidgets('не закрывается мимо кнопок', (tester) async {
      // Закрытый мимо диалог означал бы «оставить локальный» молча — то есть
      // тихо перезаписать облачный сейв через минуту автосейва.
      await tester.pumpWidget(host(c));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text(S.syncConflictTitle), findsOneWidget);
      expect(c.hasPendingSync, isTrue);
    });

    testWidgets('кнопка закрывает диалог и снимает вопрос', (tester) async {
      await tester.pumpWidget(host(c));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, S.syncThisPhone));
      await tester.pump();

      expect(c.hasPendingSync, isFalse,
          reason: 'вопрос, оставшийся заданным после ответа, задастся снова');
    });
  });

  // Что происходит с сейвом после ответа. Обычный `test`, потому что каждая
  // из этих проверок кончается настоящей записью на диск.
  group('ответ на расхождение', () {
    test('облачный сейв становится тем, во что играют', () async {
      final c = await conflicted();
      addTearDown(c.dispose);
      expect(c.profile.maxDepthEver, 12);

      await c.resolveSync(takeCloud: true);

      expect(c.profile.maxDepthEver, 47);
      expect(c.profile.gold, 9000);
      expect(c.hasPendingSync, isFalse);
      expect((await store.load())!.profile.maxDepthEver, 47,
          reason: 'выбранный сейв обязан пережить перезапуск');
    });

    test('свой сейв немедленно уезжает в облако', () async {
      // Иначе второе устройство продолжает считать хозяином себя, и
      // следующий запуск задаст тот же вопрос ещё раз.
      final c = await conflicted();
      addTearDown(c.dispose);
      final before = cloud.pushes;

      await c.resolveSync(takeCloud: false);
      await mirror.push(await store.save(save(gold: 500, depth: 12, runs: 2)),
          force: true);

      expect(c.profile.maxDepthEver, 12);
      expect(cloud.pushes, greaterThan(before));
      expect(cloud.docs.values.single.head.progress.maxDepth, 12);
    });

    test('взятый облачный сейв больше не считается расхождением', () async {
      final c = await conflicted();
      addTearDown(c.dispose);
      await c.resolveSync(takeCloud: true);

      final again = await mirror.resolveOnBoot();
      expect(again.needsPlayer, isFalse,
          reason: 'ответ, не переживший перезапуск, — не ответ');
    });
  });
}
