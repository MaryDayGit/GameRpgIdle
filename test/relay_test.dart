import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/codec.dart';
import 'package:rift/core/save/migrations.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/sim/relay_forecast.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Смена у Костра (GDD §9.4, раунд 40).
///
/// Ночь без игрока стоила одного контракта: наёмник гибнет в 23:20, слот стоит
/// до утра. Сменщик уходит вниз в секунду гибели и в сборке павшего — и всё,
/// что здесь проверяется, сводится к трём обещаниям: та же секунда, та же
/// сборка, тот же спуск, что посчитал бы прогноз.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  final t0 = DateTime.utc(2026, 9, 15, 22);
  final nextDay = t0.add(const Duration(days: 1));

  PlayerProfile camp({int campfire = 8, int tavern = 0, int mercs = 4}) {
    final profile = PlayerProfile(
      outpost: Outpost({Building.campfire: campfire, Building.tavern: tavern}),
      maxDepthEver: 60,
      gold: 1e6,
    );
    for (var i = 0; i < mercs; i++) {
      profile.roster.reserve
          .add(MercFactory.roll(Rng(i + 1), idPrefix: 'relay$i'));
    }
    return profile;
  }

  /// Доводит [contract] до гибели шагами «как при игроке»: игра открыта и
  /// замечает каждое событие через секунду после того, как оно случилось.
  void followAttended(PlayerProfile profile, Contract contract) {
    for (var guard = 0; guard < 400; guard++) {
      if (contract.awaitingCollection) return;
      final at = contract.atFork
          ? contract.forkArrivedAtUtc!.add(
              Duration(seconds: Tuning.forkWaitAwaySeconds.round() + 1))
          : contract.segmentEndsAtUtc!.add(const Duration(seconds: 1));
      profile.refreshContracts(at);
    }
    fail('спуск не кончился за 400 шагов');
  }

  group('места у Костра', () {
    test('открываются уровнями Костра', () {
      int places(int level) =>
          Outpost({Building.campfire: level}).relayPerSlot;

      expect(places(0), 0);
      expect(places(Tuning.relayFirstLevel - 1), 0);
      expect(places(Tuning.relayFirstLevel), 1);
      expect(places(Tuning.relaySecondLevel), 2);
      expect(places(Tuning.relayThirdLevel), 3);
    });

    test('каждый слот спуска получает свои места', () {
      final one = camp(campfire: Tuning.relaySecondLevel);
      final two =
          camp(campfire: Tuning.relaySecondLevel, tavern: Tuning.secondSlotLevel);

      expect(one.relayCapacity, 2);
      expect(two.relayCapacity, 4);
    });

    test('сверх мест в смену не встать', () {
      final profile = camp(campfire: Tuning.relayFirstLevel);
      expect(profile.queueRelay(profile.roster.reserve[0]), isTrue);
      expect(profile.queueRelay(profile.roster.reserve[0]), isFalse);
      expect(profile.roster.relay, hasLength(1));
    });

    test('без Костра смены нет', () {
      final profile = camp(campfire: 0);
      expect(profile.queueRelay(profile.roster.reserve.first), isFalse);
    });
  });

  test('сменщик сдаёт своё снаряжение в сундук', () {
    // Он уйдёт в вещах павшего. Комплект, запертый на человеке, который его
    // никогда не наденет, — молча потерянный комплект.
    final profile = camp();
    final merc = profile.roster.reserve.first;
    final worn = merc.gear.filledSlots;
    expect(worn, greaterThan(0), reason: 'наёмник нанят со стартовым набором');

    expect(profile.queueRelay(merc), isTrue);

    expect(merc.gear.filledSlots, 0);
    expect(profile.stash, hasLength(worn));
    expect(profile.roster.reserve, isNot(contains(merc)));
    expect(profile.roster.relay, [merc]);

    expect(profile.unqueueRelay(merc), isTrue);
    expect(profile.roster.reserve, contains(merc));
    expect(profile.roster.relay, isEmpty);
  });

  test('сменщик уходит в секунду гибели и в сборке павшего', () {
    final profile = camp();
    final first = profile.roster.reserve[0];
    final second = profile.roster.reserve[1];
    second.abilities
      ..clear()
      ..add('fortitude');
    profile.queueRelay(second);

    final a = profile.deploy(first, seed: 7, now: t0);
    final loadout = a.loadout.copy();
    profile.refreshContracts(nextDay);

    expect(profile.contracts, hasLength(2));
    final b = profile.contracts.last;

    expect(a.awaitingCollection, isTrue);
    expect(b.mercenary, same(second));
    expect(b.startedAtUtc, a.segmentEndsAtUtc,
        reason: 'сменщик уходит тогда, когда погиб павший, а не когда игра '
            'это заметила');

    for (var slot = 0; slot < Equipment.slotCount; slot++) {
      expect(b.loadout.at(slot), same(loadout.at(slot)),
          reason: 'слот $slot: снаряжение переходит слот в слот');
    }
    expect(first.gear.filledSlots, 0,
        reason: 'вещи не могут быть на двоих сразу');
    expect(b.abilities, a.abilities);
    expect(b.forkPolicy, a.forkPolicy);
    expect(b.brandRank, a.brandRank);
    expect(profile.roster.relay, isEmpty);
  });

  test('добыча павшего ждёт игрока, а снаряжение — на сменщике', () {
    final profile = camp();
    profile.queueRelay(profile.roster.reserve[1]);
    final a = profile.deploy(profile.roster.reserve[0], seed: 3, now: t0);
    profile.refreshContracts(nextDay);

    final goldBefore = profile.gold;
    final stashBefore = profile.stash.length;
    final haul = profile.collect(a);

    expect(profile.gold, goldBefore + haul.gold);
    expect(profile.stash.length, stashBefore,
        reason: 'снаряжение ушло вниз со сменщиком, возвращать нечего');
  });

  test('без игрока сменщик на развилках не стоит', () {
    // По глубине это тот же спуск, что простоявший срок и пошедший по приказу.
    // Разница — только в десяти минутах стояния, которые некому прервать.
    final profile = camp();
    profile.queueRelay(profile.roster.reserve[1]);
    profile.deploy(profile.roster.reserve[0], seed: 11, now: t0);
    profile.refreshContracts(nextDay);

    final b = profile.contracts.last;
    expect(b.forkWaitingSpent, isTrue);
    expect(b.pauses, isEmpty);
    expect(b.awaitingCollection, isTrue);
  });

  test('при игроке сменщик встаёт на развилке, как любой наёмник', () {
    final profile = camp();
    profile.queueRelay(profile.roster.reserve[1]);
    final a = profile.deploy(profile.roster.reserve[0], seed: 11, now: t0);

    followAttended(profile, a);

    final b = profile.contracts.last;
    expect(b, isNot(same(a)));
    expect(b.forkWaitingSpent, isFalse,
        reason: 'игра была открыта в секунду гибели — решать будет игрок');
  });

  test('смена проходит целиком за один догон', () {
    final profile = camp(campfire: Tuning.relayThirdLevel);
    final reserve = [...profile.roster.reserve];
    for (final merc in reserve.skip(1)) {
      expect(profile.queueRelay(merc), isTrue);
    }

    profile.deploy(reserve.first, seed: 5, now: t0);
    profile.refreshContracts(nextDay);

    expect(profile.contracts, hasLength(4));
    expect(profile.roster.relay, isEmpty);
    for (var i = 1; i < profile.contracts.length; i++) {
      expect(profile.contracts[i].startedAtUtc,
          profile.contracts[i - 1].segmentEndsAtUtc);
      expect(profile.contracts[i].awaitingCollection, isTrue);
    }
  });

  test('отзыв смену не зовёт', () {
    // Отзывает игрок, и раз он здесь — решает он.
    final profile = camp();
    profile.queueRelay(profile.roster.reserve[1]);
    final a = profile.deploy(profile.roster.reserve[0], seed: 2, now: t0);

    expect(profile.recall(a, t0.add(const Duration(seconds: 30))), isTrue);
    profile.refreshContracts(nextDay);

    expect(profile.contracts, hasLength(1));
    expect(profile.roster.relay, hasLength(1));
  });

  test('прогноз смены — тот же спуск, что настоящий догон', () {
    final profile = camp(campfire: Tuning.relaySecondLevel);
    profile.queueRelay(profile.roster.reserve[1]);
    profile.queueRelay(profile.roster.reserve[2]);
    profile.deploy(profile.roster.reserve[0], seed: 9, now: t0);

    final forecast = RelayForecast.of(profile);
    expect(forecast, isNotNull);

    profile.refreshContracts(nextDay);
    final last = profile.contracts.last;

    expect(forecast!.runs, 2);
    expect(forecast.endsAtUtc, last.segmentEndsAtUtc);
    expect(
      forecast.depth,
      profile.contracts
          .map((c) => c.result!.maxDepth)
          .reduce((a, b) => a > b ? a : b),
    );
  });

  test('прогноза нет, пока смене некого сменять', () {
    final profile = camp();
    profile.queueRelay(profile.roster.reserve[1]);
    expect(RelayForecast.of(profile), isNull);
  });

  test('игрок со сменщиком не застрял', () {
    final profile = PlayerProfile(
      outpost: Outpost({Building.campfire: Tuning.relayFirstLevel}),
    );
    final merc = MercFactory.roll(Rng(1));
    profile.roster.reserve.add(merc);
    profile.queueRelay(merc);

    expect(profile.isStranded, isFalse,
        reason: 'сменщика можно вернуть в резерв и отправить');
  });

  test('сид сменщика не зависит от запуска', () {
    final profile = camp();
    final a = profile.deploy(profile.roster.reserve[0], seed: 42, now: t0);
    final one = profile.roster.reserve[0];
    final other = profile.roster.reserve[1];

    expect(PlayerProfile.relaySeed(a, one), PlayerProfile.relaySeed(a, one));
    expect(PlayerProfile.relaySeed(a, one),
        isNot(PlayerProfile.relaySeed(a, other)));
  });

  group('сейв', () {
    PlayerProfile roundTrip(PlayerProfile profile) => SaveCodec.decodeProfile(
          SaveCodec.encodeProfile(profile),
          SaveIssues(),
        );

    test('очередь переживает сохранение по порядку', () {
      final profile = camp(campfire: Tuning.relaySecondLevel);
      profile.queueRelay(profile.roster.reserve[2]);
      profile.queueRelay(profile.roster.reserve[0]);

      final loaded = roundTrip(profile);
      expect(
        loaded.roster.relay.map((m) => m.id),
        profile.roster.relay.map((m) => m.id),
      );
    });

    test('сменщик, ушедший без игрока, после загрузки не встаёт', () {
      final profile = camp();
      profile.queueRelay(profile.roster.reserve[1]);
      profile.deploy(profile.roster.reserve[0], seed: 13, now: t0);
      profile.refreshContracts(nextDay);

      final loaded = roundTrip(profile);
      final before = profile.contracts.last.result!;
      final after = loaded.contracts.last.result!;

      expect(loaded.contracts.last.forkWaitingSpent, isTrue);
      expect(after.maxDepth, before.maxDepth);
      expect(after.totalSeconds, before.totalSeconds);
    });

    test('миграция 6 → 7 проставляет пустую смену', () {
      final raw = <String, dynamic>{
        'profile': <String, dynamic>{'roster': <String, dynamic>{}},
      };
      final up = const SaveMigrations().upgrade(raw, from: 6, target: 7);

      final profile = up['profile'] as Map;
      expect((profile['roster'] as Map)['relay'], isEmpty);
      expect(profile['echoResonance'], 0);
    });
  });
}
