import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/save/save_head.dart';
import 'package:rift/core/save/save_sync.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift/core/telemetry/analytics_event.dart';
import 'package:rift/core/telemetry/analytics_sink.dart';
import 'package:rift/core/telemetry/game_events.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

Mercenary _merc() => Mercenary(
      id: 'm',
      name: 'Тестовый',
      rank: MercRank.ragged,
      trait: MercTrait.hardy,
    );

PlayerProfile _player() {
  final p = PlayerProfile();
  p.roster.reserve.add(_merc());
  return p;
}

SaveHead _head({int revision = 1, int mirrored = 0, int depth = 10}) => SaveHead(
      version: 4,
      revision: revision,
      mirroredRevision: mirrored,
      seasonId: Season.current.id,
      lastSeenUtc: DateTime.utc(2026, 9, 1),
      progress: SaveProgress(maxDepth: depth, runs: 3, outpostLevel: 2),
    );

/// Перематывает часы на месяц вперёд: спуск считается отрезками до развилок,
/// и «до конца» — это до конца всей цепочки, а не до ближайшей паузы.
List<Contract> _waitOut(PlayerProfile p) =>
    p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 30)));

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  // Главная причина, по которой этот файл существует.
  //
  // GA4 не сообщает об отброшенном событии ничем: приложение не падает, в
  // логе пусто, а колонки в отчёте просто нет — и узнаётся это через сутки
  // после релиза, когда данные уже потеряны безвозвратно (историю GA4 не
  // пересобирает). Единственное место, где это ловится вовремя, — здесь.
  group('лимиты GA4', () {
    test('каждое событие каталога уходит целиком', () {
      final p = _player();
      final m = p.roster.reserve.first;
      final contract = p.deploy(m, seed: 42);
      _waitOut(p);
      final result = contract.result!;

      final catalogue = <AnalyticsEvent>[
        GameEvents.runStarted(contract, p),
        GameEvents.runEnded(contract, result, p, record: true),
        GameEvents.forkChoice(
          depth: 40,
          option: 2,
          byPlayer: true,
          waitedSeconds: 30,
          policy: 'loot',
        ),
        GameEvents.haulCollected(result.haul, latencySeconds: 3600),
        GameEvents.lootDecision(kind: 'keep', ilvl: 40, auto: false),
        GameEvents.outpostUpgrade(Building.tavern, p),
        GameEvents.echoNode('echo_node_id', p),
        GameEvents.passiveAlloc('passive_node_id', p),
        GameEvents.passiveReset(p),
        GameEvents.brandRank(2, p),
        GameEvents.mercHired('ragged', p),
        GameEvents.relayQueued(p),
        GameEvents.relayTakeover(contract, p),
        GameEvents.tutorialStep('first_deploy'),
        GameEvents.tutorialDone(skipped: false),
        GameEvents.notificationsAnswer(granted: true),
        GameEvents.languageSet('ru'),
        GameEvents.anomaly(contract, result),
        // Сейв, аккаунт, сезон. Проверяются наравне с остальным: событие о
        // потерянном сейве, которое GA4 обрежет, — это потерянный сейв, о
        // котором мы не узнаем.
        GameEvents.saveSync(SaveSync.resolve(local: _head(), remote: _head())),
        GameEvents.saveConflictResolved(
          tookRemote: true,
          local: const SaveProgress(maxDepth: 40, runs: 12),
          remote: const SaveProgress(maxDepth: 12, runs: 2),
        ),
        GameEvents.saveRecovered('primary'),
        GameEvents.saveFailed('write'),
        GameEvents.cloudError('write'),
        GameEvents.accountLink('already_in_use'),
        GameEvents.seasonStart('season_0', 'season_1'),
        GameEvents.achievementUnlocked('first_blood', p),
      ];

      for (final event in catalogue) {
        expect(
          event.problems,
          isEmpty,
          reason: 'событие "${event.name}" GA4 обрежет молча',
        );
      }
    });

    test('свойства игрока влезают в 24 и 36 символов', () {
      final props = GameEvents.properties(
        _player(),
        lang: 'ru',
        season: Season.current.id,
        account: 'google',
      );
      props.forEach((name, value) {
        final (cleanName, cleanValue) = AnalyticsEvent.property(name, value);
        expect(cleanName, name, reason: 'имя свойства "$name" обрежется');
        expect(cleanValue, value, reason: 'значение "$value" обрежется');
      });
    });

    test('приведение чинит то, что можно починить', () {
      final event = AnalyticsEvent('Плохое Имя!', {
        'Слишком Длинное Значение': 'x' * 200,
        'флаг': true,
        'пусто': null,
      }).sanitized();

      // Имя приведено к допустимому, а не отброшено: событие с испорченным
      // именем всё равно полезнее отсутствующего.
      expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(event.name), isTrue);
      expect(event.problems, isEmpty);

      // `null` не существует для GA4 — параметр с ним не отправляется вовсе.
      expect(event.params.keys.any((k) => k.contains('пусто')), isFalse);

      // `bool` GA4 тоже не принимает: 0/1 — единственный способ его довезти.
      expect(event.params.values, contains(1));

      for (final value in event.params.values) {
        if (value is String) {
          expect(value.length,
              lessThanOrEqualTo(AnalyticsEvent.paramValueMaxLength));
        }
      }
    });

    test('зарезервированный префикс Google — это проблема, а не мелочь', () {
      // Такое событие не доедет вообще, и молча: имя, начинающееся с
      // `firebase_`, SDK считает своим.
      expect(const AnalyticsEvent('firebase_run').problems, isNotEmpty);
      expect(const AnalyticsEvent('ga_depth').problems, isNotEmpty);
    });

    test('двадцать шестой параметр — потеря, а не обрезка', () {
      final fat = AnalyticsEvent('fat', {
        for (var i = 0; i < 30; i++) 'p$i': i,
      });
      expect(fat.problems, isNotEmpty);
      expect(fat.sanitized().params, hasLength(AnalyticsEvent.paramsMax));
    });
  });

  group('спуск доезжает до события', () {
    test('run_ended несёт глубину, конец и причину гибели', () {
      final p = _player();
      final m = p.roster.reserve.first;
      final contract = p.deploy(m, seed: 42);
      _waitOut(p);
      final result = contract.result!;

      final event = GameEvents.runEnded(contract, result, p, record: true);

      expect(event.params['max_depth'], result.maxDepth);
      expect(event.params['ending'], result.ending.name);
      expect(event.params['floors'], result.floors.length);
      // Причина гибели — то, ради чего событие и снимается: «на 47 этаже всех
      // убивает Владыка Пепла» видно только по нему.
      expect(event.params['killed_by'], isNotNull);
      expect(event.params['record'], isTrue);
    });

    test('run_started описывает решение игрока, а не итог', () {
      final p = _player();
      final m = p.roster.reserve.first;
      final contract = p.deploy(m, seed: 7);

      final event = GameEvents.runStarted(contract, p);

      expect(event.params['brand_rank'], contract.brandRank);
      expect(event.params['fork_policy'], contract.forkPolicy.name);
      expect(event.params['abilities'],
          GameEvents.abilityFingerprint(contract.abilities));
    });

    test('развилки, выбранные игроком, отделены от выбранных приказом', () {
      // Ставка игры в том, что за развилкой возвращаются. Проверить её можно
      // только если оба числа едут в одном событии: без спуска игрок не
      // выбрал ни одной, и `forks_player` обязан быть нулём — а не равным
      // общему числу развилок.
      final p = _player();
      final m = p.roster.reserve.first;
      final contract = p.deploy(m, seed: 42);
      _waitOut(p);

      final event =
          GameEvents.runEnded(contract, contract.result!, p, record: false);

      expect(event.params['forks_player'], 0);
      expect(event.params['forks'], contract.result!.forksTaken);
    });
  });

  group('свёртки', () {
    test('глубина ложится в корзины, по которым можно группировать', () {
      expect(GameEvents.depthBucket(0), '0');
      expect(GameEvents.depthBucket(7), '0-9');
      expect(GameEvents.depthBucket(47), '40-49');
      expect(GameEvents.depthBucket(99), '90-99');
      expect(GameEvents.depthBucket(150), '100-199');
      expect(GameEvents.depthBucket(4000), '1000+');
    });

    test('задержка возвращения — по порядкам', () {
      expect(GameEvents.latencyBucket(30), '<1m');
      expect(GameEvents.latencyBucket(1200), '10-60m');
      expect(GameEvents.latencyBucket(3600 * 8), '6-24h');
      expect(GameEvents.latencyBucket(3600 * 40), '>24h');
    });

    test('сборка сортируется: порядок слотов не создаёт вторую сборку', () {
      expect(
        GameEvents.abilityFingerprint(['cleave', 'ember_infusion']),
        GameEvents.abilityFingerprint(['ember_infusion', 'cleave']),
      );
    });
  });

  group('сток', () {
    test('пустой сток ничего не делает и не падает', () {
      const sink = NoopAnalyticsSink();
      sink.log(const AnalyticsEvent('run_ended'));
      sink.setProperty('depth_bucket', '40-49');
      sink.setCollectionEnabled(false);
    });

    test('записывающий сток отдаёт события по имени', () {
      final sink = RecordingAnalyticsSink()
        ..log(const AnalyticsEvent('run_started'))
        ..log(const AnalyticsEvent('run_ended', {'max_depth': 12}))
        ..log(const AnalyticsEvent('run_ended', {'max_depth': 40}));

      expect(sink.named('run_ended'), hasLength(2));
      expect(sink.last('run_ended')!.params['max_depth'], 40);
      expect(sink.last('fork_choice'), isNull);
    });
  });
}
