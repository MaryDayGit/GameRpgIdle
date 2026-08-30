import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_issue.dart';
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
}
