import 'package:rift/core/save/save_head.dart';
import 'package:rift/core/save/save_sync.dart';
import 'package:rift/core/save/season.dart';
import 'package:test/test.dart';

/// Разрешение расхождений между сейвом на телефоне и сейвом в облаке.
///
/// Единственная подсистема игры, ошибка в которой стоит чужого аккаунта, и
/// единственная, которую нельзя проверить руками: чтобы два сейва разошлись
/// по-настоящему, нужны два устройства, разведённые определённой
/// последовательностью запусков. Здесь это стоит миллисекунды.
///
/// Ветки перечислены все до одной намеренно. Правило вида «возьмём тот, что
/// новее» звучит очевидно ровно до того момента, когда его записываешь
/// тестами: половина случаев ниже на нём ломается, и ломается молча.
void main() {
  SaveHead head({
    int revision = 1,
    int mirrored = 0,
    int depth = 0,
    int runs = 0,
    int outpost = 0,
    double gold = 0,
    String? season,
    String device = 'phone',
    String? account,
    DateTime? seen,
  }) =>
      SaveHead(
        version: 4,
        revision: revision,
        mirroredRevision: mirrored,
        deviceId: device,
        accountId: account,
        seasonId: season ?? Season.current.id,
        lastSeenUtc: seen ?? DateTime.utc(2026, 9, 1),
        progress: SaveProgress(
          maxDepth: depth,
          runs: runs,
          outpostLevel: outpost,
          gold: gold,
        ),
      );

  /// Нажитый сейв: рекорд, спуски, Застава.
  SaveHead played({
    int revision = 10,
    int mirrored = 0,
    String device = 'phone',
    String? account,
    DateTime? seen,
  }) =>
      head(
        revision: revision,
        mirrored: mirrored,
        depth: 47,
        runs: 12,
        outpost: 9,
        gold: 4000,
        device: device,
        account: account,
        seen: seen,
      );

  group('когда спрашивать не о чем', () {
    test('нет облака — играем локальным', () {
      final d = SaveSync.resolve(local: played());
      expect(d.action, SyncAction.keepLocal);
      expect(d.reason, 'no_remote');
      expect(d.needsPlayer, isFalse);
    });

    test('нет ни того ни другого — тоже локальный, то есть новая игра', () {
      expect(SaveSync.resolve().action, SyncAction.keepLocal);
    });

    test('нет локального — берём облачный', () {
      final d = SaveSync.resolve(remote: played());
      expect(d.action, SyncAction.takeRemote);
      expect(d.reason, 'no_local');
    });

    test('в облаке пусто, на телефоне игра — выбора не существует', () {
      final d = SaveSync.resolve(local: played(), remote: head());
      expect(d.action, SyncAction.keepLocal);
      expect(d.reason, 'remote_empty');
    });
  });

  // Главный сценарий всей затеи. Игрок переустановил игру или взял новый
  // телефон: локальный сейв свежий по ВРЕМЕНИ и пустой по СУЩЕСТВУ.
  group('переустановка', () {
    test('пустой локальный уступает нажитому облачному', () {
      final d = SaveSync.resolve(local: head(), remote: played());
      expect(d.action, SyncAction.takeRemote);
      expect(d.reason, 'fresh_install');
      expect(d.needsPlayer, isFalse,
          reason: 'восстановление после переустановки не должно '
              'требовать от игрока решения');
    });

    test('свежая отметка времени НЕ побеждает нажитый сейв', () {
      // Регрессия на правило «кто новее, тот и прав». Локальный сейв заведён
      // минуту назад, облачный лежит с прошлой недели — и всё равно
      // побеждает облачный, потому что в нём сорок семь этажей, а в
      // локальном ноль.
      final d = SaveSync.resolve(
        local: head(seen: DateTime.utc(2026, 9, 8, 12)),
        remote: played(seen: DateTime.utc(2026, 9, 1)),
      );
      expect(d.action, SyncAction.takeRemote);
    });
  });

  group('кто чей потомок', () {
    test('облако не двигалось с нашей выгрузки — играем локальным', () {
      // Обычный запуск на том же телефоне: мы выгрузили ревизию 10, с тех
      // пор доиграли до 14, облако осталось на 10.
      final d = SaveSync.resolve(
        local: played(revision: 14, mirrored: 10),
        remote: played(revision: 10, device: 'phone'),
      );
      expect(d.action, SyncAction.keepLocal);
      expect(d.reason, 'local_ahead');
    });

    test('облако двинулось, а мы нет — берём облачный', () {
      // Играли на втором телефоне. Здесь с последней синхронизации не
      // случилось ничего.
      final d = SaveSync.resolve(
        local: played(revision: 10, mirrored: 10),
        remote: played(revision: 21, device: 'tablet'),
      );
      expect(d.action, SyncAction.takeRemote);
      expect(d.reason, 'remote_ahead');
    });

    test('ревизия облака РАВНА выгруженной — это мы сами и есть', () {
      final d = SaveSync.resolve(
        local: played(revision: 10, mirrored: 10),
        remote: played(revision: 10),
      );
      expect(d.action, SyncAction.keepLocal);
    });
  });

  group('расхождение', () {
    test('двинулись оба — решает игрок', () {
      final d = SaveSync.resolve(
        local: played(revision: 14, mirrored: 10, device: 'phone'),
        remote: played(revision: 21, device: 'tablet'),
      );
      expect(d.action, SyncAction.ask);
      expect(d.reason, 'diverged');
      expect(d.needsPlayer, isTrue);
    });

    test('оба паспорта доезжают до диалога — их там показывают', () {
      final d = SaveSync.resolve(
        local: played(revision: 14, mirrored: 10),
        remote: played(revision: 21, device: 'tablet'),
      );
      expect(d.local, isNotNull);
      expect(d.remote, isNotNull);
      expect(d.local!.progress.maxDepth, 47);
    });

    test('смена аккаунта — своя причина, а не общая', () {
      // Не «две ветки одной жизни», а два разных человека на одном телефоне.
      // В отчёте их надо видеть отдельно, иначе доля расхождений врёт.
      final d = SaveSync.resolve(
        local: played(revision: 14, mirrored: 10, account: 'uid_a'),
        remote: played(revision: 21, account: 'uid_b'),
      );
      expect(d.action, SyncAction.ask);
      expect(d.reason, 'other_account');
    });

    test('сейв, который никогда не выгружался, расходится честно', () {
      // Тот самый случай после обновления игры: `mirroredRevision` = 0 из
      // миграции 3 → 4. Считать его отставшим нельзя — в нём вся игра.
      final d = SaveSync.resolve(
        local: played(revision: 5, mirrored: 0),
        remote: played(revision: 3, device: 'tablet'),
      );
      expect(d.action, SyncAction.ask);
    });
  });

  group('сезоны', () {
    test('локальный сейв прошлого сезона не загружается', () {
      final d = SaveSync.resolve(local: played(), remote: played());
      expect(d.action, isNot(SyncAction.newSeason));

      final old = SaveSync.resolve(
        local: played().copyWithSeason('season_legacy'),
        remote: played(),
      );
      expect(old.action, SyncAction.newSeason);
      expect(old.reason, contains('season_legacy'));
    });

    test('облачный сейв чужого сезона не трогается вовсе', () {
      // Документ чужого сезона — это архив. Взять его нельзя (другая игра),
      // затереть нельзя (это и есть архив).
      final d = SaveSync.resolve(
        local: played(),
        remote: played().copyWithSeason('season_1'),
      );
      expect(d.action, SyncAction.keepLocal);
      expect(d.reason, 'remote_other_season');
    });

    test('сейв без сезона считается нулевым', () {
      expect(SaveHead.fromJson({'version': 4})!.seasonId, Season.zero.id);
      expect(Season.isCurrent(Season.zero.id), isTrue);
    });

    test('архив называется по сезону и не съедает расширение', () {
      expect(SaveSync.archiveName('rift.save.json', 'season_0'),
          'rift.season_0.save.json');
      expect(SaveSync.archiveName('rift.save.json', 'season/1'),
          'rift.season_1.save.json');
    });
  });

  group('паспорт', () {
    test('пустой профиль опознаётся как пустой, нажитый — как нажитый', () {
      expect(const SaveProgress().isNewGame, isTrue);
      expect(const SaveProgress(gold: 250).isNewGame, isTrue,
          reason: 'золото не признак игры: стартовую выдачу новичку '
              'нельзя превращать в отказ поднять сейв из облака');
      expect(const SaveProgress(runs: 1).isNewGame, isFalse);
      expect(const SaveProgress(maxDepth: 3).isNewGame, isFalse);
    });

    test('паспорт переживает JSON', () {
      final source = played(revision: 7, mirrored: 5, account: 'uid');
      final back = SaveHead.fromJson(source.toJson())!;
      expect(back.revision, 7);
      expect(back.mirroredRevision, 5);
      expect(back.accountId, 'uid');
      expect(back.progress.maxDepth, 47);
      expect(back.lastSeenUtc, source.lastSeenUtc);
    });

    test('чужой документ без версии — это отсутствие документа', () {
      expect(SaveHead.fromJson(null), isNull);
      expect(SaveHead.fromJson({'revision': 5}), isNull);
    });
  });
}

extension on SaveHead {
  SaveHead copyWithSeason(String season) => SaveHead(
        version: version,
        revision: revision,
        mirroredRevision: mirroredRevision,
        deviceId: deviceId,
        accountId: accountId,
        seasonId: season,
        lastSeenUtc: lastSeenUtc,
        progress: progress,
      );
}
