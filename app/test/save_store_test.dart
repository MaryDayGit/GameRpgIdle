import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift_app/data/save_store.dart';

/// Запись сейва — единственное место, где убитый системой процесс стоит
/// игроку аккаунта. Проверяется не «файл появился», а что после обрыва
/// на любом шаге остаётся, чем играть.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    ContentPack.parse(raw).apply();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_save_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  SaveData makeData({double gold = 1234.0}) => SaveData(
        lastSeenUtc: DateTime.utc(2026, 5, 1),
        profile: PlayerProfile(gold: gold, echo: 7),
      );

  test('пустое хранилище отдаёт null, а не падает', () async {
    final store = SaveStore(dir);
    expect(store.exists, isFalse);
    expect(await store.load(), isNull);
  });

  test('записанное читается обратно', () async {
    final store = SaveStore(dir);
    await store.save(makeData());

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.profile.gold, 1234.0);
    expect(loaded.profile.echo, 7);
    expect(loaded.lastSeenUtc, DateTime.utc(2026, 5, 1));
  });

  test('временный файл не остаётся после успешной записи', () async {
    final store = SaveStore(dir);
    await store.save(makeData());

    final leftovers = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });

  test('битый основной файл — играем с резервной копии', () async {
    final store = SaveStore(dir);
    await store.save(makeData(gold: 100.0));
    await store.save(makeData(gold: 200.0)); // теперь есть и .bak

    // Обрыв записи: основной файл превратился в мусор.
    File('${dir.path}/rift.save.json').writeAsStringSync('{битый');

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.profile.gold, 100.0,
        reason: 'потерян один автосейв, а не весь прогресс');
  });

  test('если не читается ни файл, ни копия — это отказ, а не пустой профиль',
      () async {
    final store = SaveStore(dir);
    await store.save(makeData());
    File('${dir.path}/rift.save.json').writeAsStringSync('мусор');

    expect(store.load(), throwsA(isA<SaveException>()),
        reason: 'молча начать новую игру поверх старой — худшее из возможного');
  });

  test('перезапись не теряет данные между шагами', () async {
    final store = SaveStore(dir);
    for (var i = 1; i <= 5; i++) {
      await store.save(makeData(gold: i * 10.0));
      final loaded = await store.load();
      expect(loaded!.profile.gold, i * 10.0);
    }
  });

  test('расписание сохраняет по сворачиванию приложения', () async {
    final store = SaveStore(dir);
    var snapshots = 0;

    final scheduler = SaveScheduler(
      store: store,
      snapshot: () {
        snapshots++;
        return makeData(gold: 999.0);
      },
    )..start();
    addTearDown(scheduler.dispose);

    scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(snapshots, greaterThan(0));
    final loaded = await store.load();
    expect(loaded!.profile.gold, 999.0);
  });

  // Номер записи — то, на чём стоит выбор между сейвом на телефоне и сейвом
  // в облаке (`rift/core/save/save_sync.dart`). Ошибка здесь не выглядит
  // ошибкой: игра работает, а прогресс теряется у того, кто играет с двух
  // устройств.
  group('номер записи', () {
    test('растёт на единицу с каждой записью', () async {
      final store = SaveStore(dir);
      expect(store.revision, 0, reason: 'сейва ещё не было');

      final first = await store.save(makeData());
      final second = await store.save(makeData());
      expect(first.revision, 1);
      expect(second.revision, 2);
      expect(store.revision, 2);
    });

    test('переживает перезапуск игры', () async {
      await SaveStore(dir).save(makeData());
      await SaveStore(dir).save(makeData());

      final fresh = SaveStore(dir);
      final loaded = await fresh.load();
      expect(loaded!.revision, 2);
      expect(fresh.revision, 2);
      expect((await fresh.save(makeData())).revision, 3,
          reason: 'счётчик, начавшийся заново, объявил бы старый сейв новым');
    });

    test('устройство и аккаунт проставляет хранилище, а не вызывающий',
        () async {
      final store = SaveStore(dir, deviceId: 'phone_a')..accountId = 'uid_1';
      final saved = await store.save(makeData());
      expect(saved.deviceId, 'phone_a');
      expect(saved.accountId, 'uid_1');
      expect((await store.peek())!.deviceId, 'phone_a');
    });
  });

  group('отметка синхронизации', () {
    test('живёт в своём файле и переживает перезапуск', () async {
      final store = SaveStore(dir);
      await store.save(makeData());
      await store.save(makeData());
      await store.markMirrored(2);

      final fresh = SaveStore(dir);
      final loaded = await fresh.load();
      expect(loaded!.mirroredRevision, 2);
      expect(fresh.mirroredRevision, 2);
    });

    test('не откатывается назад', () async {
      final store = SaveStore(dir);
      await store.save(makeData());
      await store.markMirrored(5);
      await store.markMirrored(3);
      expect(store.mirroredRevision, 5);
    });

    test('потерянная отметка не теряет данные', () async {
      // Файл отметки испорчен. Это приводит к вопросу игроку, а не к тихой
      // перезаписи, — ровно то поведение, ради которого ноль и выбран
      // значением по умолчанию.
      final store = SaveStore(dir);
      await store.save(makeData(gold: 55.0));
      await store.markMirrored(1);
      File('${dir.path}/rift.save.json.sync').writeAsStringSync('не json');

      final fresh = SaveStore(dir);
      final loaded = await fresh.load();
      expect(loaded!.profile.gold, 55.0);
      expect(loaded.mirroredRevision, 0);
    });
  });

  group('облачный сейв на месте локального', () {
    test('берётся с облачной ревизией и сразу отмечается синхронизированным',
        () async {
      final store = SaveStore(dir);
      await store.save(makeData(gold: 10.0));

      final cloud = SaveData(
        lastSeenUtc: DateTime.utc(2026, 6, 1),
        profile: PlayerProfile(gold: 5000.0),
        revision: 42,
      );
      final adopted = await store.adopt(cloud);

      expect(adopted.revision, 42,
          reason: 'взятый сейв — тот же сейв, а не новая запись поверх него');
      expect(store.mirroredRevision, 42,
          reason: 'мы только что взяли его оттуда — расходиться не с чем');
      expect((await store.load())!.profile.gold, 5000.0);
    });
  });

  group('сезоны', () {
    test('сейв прошлого сезона уезжает в архив, а не удаляется', () async {
      final store = SaveStore(dir);
      await store.save(makeData(gold: 777.0));

      final name = await store.archiveSeason('season_0');
      expect(name, 'rift.season_0.save.json');
      expect(File('${dir.path}/$name').existsSync(), isTrue,
          reason: 'обнуление сезона не должно уничтожать доказанное в нём');
      expect(File('${dir.path}/rift.save.json').existsSync(), isFalse);

      // Хранилище начинает сезон с чистого счётчика.
      expect(store.revision, 0);
      expect(await store.load(), isNull);
    });

    test('архив открывается как обычный сейв', () async {
      final store = SaveStore(dir);
      await store.save(makeData(gold: 777.0));
      final name = await store.archiveSeason(Season.zero.id);

      final archive = SaveStore(dir, fileName: name!);
      expect((await archive.load())!.profile.gold, 777.0);
    });
  });

  group('поломки перестали быть тихими', () {
    test('подъём с резервной копии сообщается', () async {
      final trouble = <String>[];
      final store = SaveStore(dir,
          onTrouble: (kind, stage) => trouble.add('$kind/$stage'));

      await store.save(makeData(gold: 100.0));
      await store.save(makeData(gold: 200.0));
      File('${dir.path}/rift.save.json').writeAsStringSync('{битый');

      await store.load();
      expect(trouble, contains('recovered/primary'));
    });

    test('нечитаемый сейв убирается в сторону, а не затирается', () async {
      final trouble = <String>[];
      final store = SaveStore(dir,
          onTrouble: (kind, stage) => trouble.add('$kind/$stage'));
      await store.save(makeData(gold: 100.0));
      File('${dir.path}/rift.save.json').writeAsStringSync('мусор');

      await expectLater(store.load(), throwsA(isA<SaveException>()));
      expect(trouble, contains('recovered/both'));

      final quarantined = await store.quarantine();
      expect(quarantined, 'rift.save.json.broken');
      expect(File('${dir.path}/$quarantined').readAsStringSync(), 'мусор',
          reason: 'сейв не открылся сегодняшней версией игры — завтрашняя '
              'может и открыть');
      expect(await store.load(), isNull);
    });
  });

  test('уход в фон помечается как уход, а таймер — нет', () async {
    // Различие не косметическое: по нему зеркало решает, выгружать сейв в
    // облако сейчас или подождать (`cloud_sync.dart`). Уход в фон — последний
    // момент, когда сейв ещё можно выгрузить.
    final leavings = <bool>[];
    final scheduler = SaveScheduler(
      store: SaveStore(dir),
      snapshot: makeData,
      onSaved: (_, {required leaving}) => leavings.add(leaving),
    );
    addTearDown(scheduler.dispose);

    await scheduler.saveNow();
    scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(leavings, [false, true]);
  });
}
