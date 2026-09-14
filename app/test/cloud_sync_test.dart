import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_sync.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift_app/data/account.dart';
import 'package:rift_app/data/cloud_save.dart';
import 'package:rift_app/data/cloud_sync.dart';
import 'package:rift_app/data/save_store.dart';

/// Облачное зеркало: два устройства, одно облако.
///
/// Правило выбора проверяется в ядре (`test/save_sync_test.dart` пакета
/// `rift`) — здесь проверяется, что вокруг него правильно ходят по диску и
/// по сети. Разница существенная: правило может быть верным, а сейв всё
/// равно потеряется, если офлайн принять за пустое облако или выгрузить
/// сейв, не подняв отметку синхронизации.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    ContentPack.parse(raw).apply();
  });

  late Directory root;
  late FakeCloudSaveStore cloud;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_cloud_test');
    cloud = FakeCloudSaveStore();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Отдельное «устройство»: свой каталог, своё имя, общий аккаунт и общее
  /// облако. Два вызова с разными именами — это два телефона одного игрока,
  /// с тем же именем — перезапуск того же телефона.
  Future<({SaveStore store, CloudMirror mirror})> device(String name,
      {DateTime Function()? clock}) async {
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    final account = FakeAccountService(uid: 'uid_1');
    await account.signInSilently();

    final store = SaveStore(dir, deviceId: name)
      ..accountId = account.current.uid;
    return (
      store: store,
      mirror: CloudMirror(
        store: store,
        cloud: cloud,
        account: account,
        clock: clock ?? DateTime.now,
      ),
    );
  }

  SaveData data({double gold = 100, int depth = 0, int runs = 0}) {
    final profile = PlayerProfile(gold: gold, maxDepthEver: depth);
    profile.quests.runsCompleted = runs;
    return SaveData(
      lastSeenUtc: DateTime.utc(2026, 9, 1),
      profile: profile,
      seasonId: Season.current.id,
    );
  }

  group('перенос на другое устройство', () {
    test('пустое устройство поднимает сейв из облака само', () async {
      // Ради этого сценария всё и делается: игрок переустановил игру или
      // взял новый телефон. Вопросов ему не задаётся ни одного.
      final phone = await device('phone');
      final saved = await phone.store.save(data(gold: 4000, depth: 47, runs: 12));
      await phone.mirror.push(saved, force: true);

      final tablet = await device('tablet');
      final sync = await tablet.mirror.resolveOnBoot();

      expect(sync.decision.action, SyncAction.takeRemote);
      expect(sync.decision.reason, 'no_local');
      expect(sync.needsPlayer, isFalse);

      final adopted = await tablet.mirror.adopt(sync.remote!);
      expect(adopted.profile.gold, 4000);
      expect(adopted.profile.maxDepthEver, 47);
    });

    test('свежая установка поверх пустого сейва тоже уступает облаку',
        () async {
      final phone = await device('phone');
      await phone.mirror
          .push(await phone.store.save(data(gold: 4000, depth: 47, runs: 12)),
              force: true);

      // Игрок успел открыть игру на планшете: заведён пустой профиль со
      // свежей отметкой времени. По часам он новее облачного.
      final tablet = await device('tablet');
      await tablet.store.save(data(gold: 0));

      final sync = await tablet.mirror.resolveOnBoot();
      expect(sync.decision.action, SyncAction.takeRemote);
      expect(sync.decision.reason, 'fresh_install');
    });

    test('принятый сейв не считается расхождением на следующем запуске',
        () async {
      final phone = await device('phone');
      await phone.mirror
          .push(await phone.store.save(data(gold: 4000, depth: 47, runs: 12)),
              force: true);

      final tablet = await device('tablet');
      await tablet.mirror.adopt((await tablet.mirror.resolveOnBoot()).remote!);

      final again = await tablet.mirror.resolveOnBoot();
      expect(again.decision.action, SyncAction.keepLocal,
          reason: 'мы только что взяли этот сейв оттуда');
      expect(again.needsPlayer, isFalse);
    });
  });

  group('обычный запуск', () {
    test('своё облако не спрашивает игрока', () async {
      final phone = await device('phone');
      await phone.mirror
          .push(await phone.store.save(data(depth: 40, runs: 5)), force: true);

      final restarted = await device('phone');
      await restarted.store.save(data(gold: 500, depth: 42, runs: 6));

      final sync = await restarted.mirror.resolveOnBoot();
      expect(sync.decision.action, SyncAction.keepLocal);
      expect(sync.decision.reason, 'local_ahead');
    });

    test('пустое облако не спрашивает игрока', () async {
      final phone = await device('phone');
      await phone.store.save(data(depth: 40, runs: 5));

      final sync = await phone.mirror.resolveOnBoot();
      expect(sync.decision.action, SyncAction.keepLocal);
      expect(sync.decision.reason, 'no_remote');
    });
  });

  test('два устройства, разошедшиеся из общей точки, спрашивают игрока',
      () async {
    final phone = await device('phone');
    await phone.mirror
        .push(await phone.store.save(data(depth: 30, runs: 4)), force: true);

    // Планшет забрал сейв и доиграл до 45.
    final tablet = await device('tablet');
    await tablet.mirror.adopt((await tablet.mirror.resolveOnBoot()).remote!);
    await tablet.mirror.push(await tablet.store.save(data(depth: 45, runs: 9)),
        force: true);

    // А телефон тем временем доиграл до 38, ничего не выгружая.
    await phone.store.save(data(depth: 38, runs: 7));

    final sync = await phone.mirror.resolveOnBoot();
    expect(sync.decision.action, SyncAction.ask);
    expect(sync.needsPlayer, isTrue);
    expect(sync.decision.local!.progress.maxDepth, 38);
    expect(sync.decision.remote!.progress.maxDepth, 45);
    expect(sync.remote, isNotNull,
        reason: 'облачный сейв нужен целиком: между вопросом и ответом '
            'игрока сеть успевает пропасть');
  });

  group('отказ сети', () {
    test('офлайн — это не пустое облако', () async {
      // Самая дорогая ошибка всего слоя. Приняв отказ сети за отсутствие
      // документа, зеркало выгрузило бы локальный сейв поверх облачного у
      // каждого, у кого пропал интернет.
      final phone = await device('phone');
      await phone.mirror
          .push(await phone.store.save(data(depth: 47, runs: 12)), force: true);

      final tablet = await device('tablet');
      await tablet.store.save(data(gold: 0));
      cloud.offline = true;

      final sync = await tablet.mirror.resolveOnBoot();
      expect(sync.decision.action, SyncAction.keepLocal);
      expect(sync.errorStage, 'read');
      expect(cloud.docs.values.single.head.progress.maxDepth, 47,
          reason: 'облачный сейв не тронут');
    });

    test('неудачная выгрузка не поднимает отметку синхронизации', () async {
      final phone = await device('phone');
      cloud.offline = true;

      final saved = await phone.store.save(data(depth: 10, runs: 1));
      await phone.mirror.push(saved, force: true);

      expect(phone.store.mirroredRevision, 0,
          reason: 'объявить сейв синхронизированным, когда он никуда не '
              'уехал, — значит потом молча затереть облачный');

      cloud.offline = false;
      await phone.mirror.push(saved, force: true);
      expect(phone.store.mirroredRevision, saved.revision);
    });
  });

  group('частота выгрузки', () {
    test('подряд идущие сохранения не жгут квоту Firestore', () async {
      // 20 000 записей в сутки даются на весь проект, а не на игрока
      // (`cloud_sync.dart`). Сейв пишется раз в минуту — выгружать его с
      // той же частотой значит отключить синхронизацию всем сразу.
      var now = DateTime.utc(2026, 9, 1, 12);
      final phone = await device('phone', clock: () => now);

      await phone.mirror.push(await phone.store.save(data(gold: 1)));
      await phone.mirror.push(await phone.store.save(data(gold: 2)));
      await phone.mirror.push(await phone.store.save(data(gold: 3)));
      expect(cloud.pushes, 1);

      now = now.add(const Duration(minutes: 6));
      await phone.mirror.push(await phone.store.save(data(gold: 4)));
      expect(cloud.pushes, 2);
    });

    test('уход в фон и конец спуска промежуток не ждут', () async {
      var now = DateTime.utc(2026, 9, 1, 12);
      final phone = await device('phone', clock: () => now);

      await phone.mirror.push(await phone.store.save(data(gold: 1)));
      await phone.mirror
          .push(await phone.store.save(data(gold: 2)), force: true);
      expect(cloud.pushes, 2);
    });

    test('одна и та же ревизия не выгружается дважды', () async {
      final phone = await device('phone');
      final saved = await phone.store.save(data(gold: 1));

      await phone.mirror.push(saved, force: true);
      await phone.mirror.push(saved, force: true);
      expect(cloud.pushes, 1);
    });

    test('без аккаунта не выгружается ничего', () async {
      final dir = Directory('${root.path}/no_account')..createSync();
      final store = SaveStore(dir);
      final mirror = CloudMirror(
        store: store,
        cloud: cloud,
        account: const NoAccountService(),
      );

      expect(mirror.enabled, isFalse);
      await mirror.push(await store.save(data(gold: 1)), force: true);
      expect(cloud.pushes, 0);
      expect((await mirror.resolveOnBoot()).errorStage, 'auth');
    });
  });
}
