import 'dart:convert';

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/sim/lair.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Логова стражей — лестница позднего этапа (раунд 36). Тест держит правила:
/// что открывается и когда, что стоит вызов, что даёт победа и чего стоит
/// поражение. Числа живут в контенте и двигаются балансом.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  EnemyArchetype guardian() => Bestiary.guardians.first;

  test('в контенте есть стражи, и у каждого есть уникальная вещь', () {
    expect(Bestiary.guardians, isNotEmpty);
    for (final g in Bestiary.guardians) {
      final uniques = ContentPack.current.relics
          .where((r) => r.source != null && r.source == g.embodies);
      expect(uniques, isNotEmpty,
          reason: '${g.id}: награда за круг — вещь босса, и её должно быть '
              'откуда взять');
    }
  });

  group('открытие', () {
    test('ниже порога логова закрыты, и золото не уходит', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth - 1);
      final m = p.roster.reserve.first;
      final gold = p.gold;

      expect(p.lairsOpen, isFalse);
      expect(p.lairBlockedReason(m, guardian().id, 1), isNotNull);
      expect(p.challengeGuardian(m, guardian().id), isNull);
      expect(p.gold, gold);
    });

    test('круг через ступень не вызывается', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth);
      final m = p.roster.reserve.first;

      expect(p.nextLairCircle(guardian().id), 1);
      expect(p.lairBlockedReason(m, guardian().id, 2), isNotNull);
      expect(p.challengeGuardian(m, guardian().id, circle: 2), isNull);
    });

    test('без золота на подношение вызова нет', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth, gold: 0);
      expect(p.challengeGuardian(p.roster.reserve.first, guardian().id),
          isNull);
    });
  });

  test('каждый круг глубже и дороже предыдущего', () {
    for (var circle = 1; circle < 20; circle++) {
      expect(Curves.lairDepth(circle + 1), greaterThan(Curves.lairDepth(circle)));
      expect(Curves.lairOffering(circle + 1),
          greaterThan(Curves.lairOffering(circle)),
          reason: 'сток обязан расти вместе с доходом');
    }
  });

  group('победа', () {
    test('первая даёт круг, два очка пассивок и вещь босса; наёмник жив', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth, stashIlvl: 500);
      final m = p.roster.reserve.first;
      final g = guardian();
      final points = p.passivePoints;
      final gold = p.gold;

      final c = p.challengeGuardian(m, g.id)!;

      expect(c.fight.won, isTrue,
          reason: 'снаряжение с 500-го этажа против первого круга');
      expect(c.firstWin, isTrue);
      expect(p.gold, closeTo(gold - Curves.lairOffering(1), 1e-6));
      expect(p.lairCircles[g.id], 1);
      expect(p.nextLairCircle(g.id), 2);
      expect(p.passivePoints, points + Curves.lairFirstKillPoints);
      expect(c.passivePoints, Curves.lairFirstKillPoints);

      expect(c.relic, isNotNull);
      expect(p.pendingLoot, contains(c.relic));
      final def = ContentPack.current.relic(c.relic!.relicId!)!;
      expect(def.source, g.embodies,
          reason: 'страж роняет вещь того босса, которого воплощает');

      expect(p.roster.reserve, contains(m));
      expect(p.roster.fallen, isNot(contains(m)));
    });

    test('повторная победа круга не добавляет', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth, stashIlvl: 500);
      final m = p.roster.reserve.first;
      final g = guardian();

      p.challengeGuardian(m, g.id);
      final points = p.passivePoints;
      final again = p.challengeGuardian(m, g.id, circle: 1)!;

      expect(again.fight.won, isTrue);
      expect(again.firstWin, isFalse);
      expect(p.lairCircles[g.id], 1);
      expect(p.passivePoints, points);
    });

    test('следующие круги очков не дают', () {
      final p = _player(maxDepth: Curves.lairUnlockDepth, stashIlvl: 900);
      final m = p.roster.reserve.first;
      final g = guardian();

      p.challengeGuardian(m, g.id);
      final points = p.passivePoints;
      final second = p.challengeGuardian(m, g.id)!;

      expect(second.fight.won, isTrue);
      expect(second.firstWin, isTrue, reason: 'второй круг взят впервые');
      expect(second.passivePoints, 0);
      expect(p.passivePoints, points);
    });
  });

  test('очков от логов не больше двух на каждого стража', () {
    final p = _player(maxDepth: 200);
    for (final g in Bestiary.guardians) {
      p.lairCircles[g.id] = 40;
    }
    expect(p.lairPassivePoints,
        Bestiary.guardians.length * Curves.lairFirstKillPoints);
    expect(p.lairPassivePointsLeft, 0);
    expect(p.lairTrophies, Bestiary.guardians.length * 40,
        reason: 'круги считаются, очки — нет');
  });

  group('умения стражей', () {
    test('у каждого стража свои умения, и они срабатывают в бою', () {
      for (final g in Bestiary.guardians) {
        expect(g.skills.length, greaterThanOrEqualTo(2), reason: g.id);

        // Долгий бой: герой, который стража почти не царапает и сам почти
        // не умирает, — против него страж успевает показать всё.
        final feed = CombatFeed(capacity: 100000);
        final runner = _enduranceFight(g, seed: 3, feed: feed);
        for (var i = 0; i < 600 && !runner.finished; i++) {
          runner.tick();
        }
        final beats = feed.drain();
        final used = {
          for (final b in beats)
            if (b.kind == BeatKind.bossSkill) b.id,
        };
        final periodic = {
          for (final s in g.skills)
            if (s.periodic) s.id,
        };
        expect(used.containsAll(periodic), isTrue,
            reason: '${g.id}: за минуту боя обязаны прозвучать все умения, '
                'кроме ярости; прозвучали $used');
        expect(beats.any((b) => b.kind == BeatKind.bossWindup), isTrue,
            reason: '${g.id}: у умения есть замах');
      }
    });

    test('умения делают стража опаснее, чем тот же страж без них', () {
      for (final g in Bestiary.guardians) {
        final bare = EnemyArchetype(
          id: g.id,
          name: g.name,
          hpMult: g.hpMult,
          dpsMult: g.dpsMult,
          attackSpeed: g.attackSpeed,
          armorMult: g.armorMult,
          damageType: g.damageType,
          resists: g.resists,
          isBoss: true,
          traits: g.traits,
          embodies: g.embodies,
        );

        // Исход, а не урон за отрезок: щит и ярость опасны тем, что затягивают
        // бой, замах — тем, что копит удар, и «урон в секунду» объявил бы
        // Грозового безобидным. Меряется запас здоровья, с которым герой,
        // уверенно бьющий стража без умений, выходит из боя со стражем с ними.
        //
        // Герой убивает стража примерно за 12 секунд: медленнее — и страж с
        // вампиризмом лечится быстрее, чем теряет, так что бой не кончается.
        // Здоровья у героя на 60 ударов стража — с запасом на любой исход.
        double hpLeft(EnemyArchetype who) {
          final probe = EnemyInstance.spawn(g, Curves.lairReferenceDepth);
          final runner = _enduranceFight(who,
              seed: 11, killIn: 12.0, heroHp: probe.damagePerHit * 60.0);
          for (var i = 0; i < 20000 && !runner.finished; i++) {
            runner.tick();
          }
          expect(runner.finished, isTrue, reason: '${who.id}: бой не кончился');
          return runner.hero.hpFraction.clamp(0.0, 1.0);
        }

        final withSkills = hpLeft(g);
        final without = hpLeft(bare);
        expect(without, greaterThan(0.0),
            reason: '${g.id}: стенд обязан побеждать стража без умений');
        expect(withSkills, lessThan(without), reason: g.id);
      }
    });

    test('контент без умений у стража не проходит валидацию', () {
      final raw = readContentJson();
      final enemies = raw['enemies'] as Map<String, dynamic>;
      ((enemies['guardians'] as List).first as Map)['skills'] = [];
      expect(() => ContentPack.parse(raw), throwsA(anything));
    });
  });

  group('своя мощь стража', () {
    // Раунд 40: одна мощь на всех держала замысел ровно у одного стража. Своя
    // мощь правит логово, не трогая чисел, которые выверяет аудит.
    EnemyArchetype copyOf(EnemyArchetype g, {double? lairMight}) =>
        EnemyArchetype(
          id: g.id,
          name: g.name,
          hpMult: g.hpMult,
          dpsMult: g.dpsMult,
          attackSpeed: g.attackSpeed,
          armorMult: g.armorMult,
          damageType: g.damageType,
          resists: g.resists,
          isBoss: true,
          traits: g.traits,
          embodies: g.embodies,
          skills: g.skills,
          lairMight: lairMight,
        );

    double hpOf(EnemyArchetype who) => LairFight.start(
          profile: HeroProfile(),
          guardian: who,
          depth: Curves.lairDepth(1),
          seed: 1,
        ).enemies.first.maxHp;

    test('без своей мощи страж берёт общую, со своей — свою', () {
      final shared = copyOf(guardian());
      final own = copyOf(guardian(), lairMight: 5.0);

      expect(hpOf(own) / hpOf(shared),
          closeTo(5.0 / Curves.lairGuardianMight, 1e-9));
    });

    test('мощь не больше нуля контент не пропускает', () {
      final raw = readContentJson();
      final enemies = raw['enemies'] as Map<String, dynamic>;
      ((enemies['guardians'] as List).first as Map)['lairMight'] = 0.0;
      expect(() => ContentPack.parse(raw), throwsA(anything));
    });
  });

  test('поражение: наёмник гибнет, подношение не возвращается', () {
    final p = _player(maxDepth: Curves.lairUnlockDepth, gold: 1e30);
    final g = guardian();
    // Далёкий круг и голый наёмник: исход не зависит от удачи.
    p.lairCircles[g.id] = 40;
    final m = p.roster.reserve.first;
    final gold = p.gold;

    final c = p.challengeGuardian(m, g.id)!;

    expect(c.fight.won, isFalse);
    expect(p.gold, lessThan(gold));
    expect(p.lairCircles[g.id], 40);
    expect(p.roster.reserve, isNot(contains(m)));
    expect(p.roster.fallen, contains(m));
    expect(c.relic, isNull);
  });

  test('бой детерминирован по сиду, а сид меняется от вызова к вызову', () {
    final p = _player(maxDepth: Curves.lairUnlockDepth, stashIlvl: 500);
    final m = p.roster.reserve.first;
    final g = guardian();

    final first = p.challengeGuardian(m, g.id)!;
    final repeat = LairFight.run(
      profile: p.heroProfileFor(m),
      guardian: g,
      depth: first.depth,
      seed: first.seed,
    );
    expect(repeat.seconds, first.fight.seconds,
        reason: 'экран повторяет ТОТ бой, чей исход уже записан');

    final second = p.challengeGuardian(m, g.id, circle: 1)!;
    expect(second.seed, isNot(first.seed),
        reason: 'иначе проигранный бой был бы приговором навсегда');
  });

  group('сейв', () {
    test('круги и счётчик вызовов переживают сохранение', () {
      final p = _player(maxDepth: 200)
        ..lairCircles['warden_ash'] = 3
        ..lairAttempts = 7;

      final loaded = SaveData.decode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: p).encode(),
      ).profile;

      expect(loaded.lairCircles['warden_ash'], 3);
      expect(loaded.lairAttempts, 7);
      expect(loaded.lairTrophies, 3);
    });

    test('сейв пятой версии открывается без логов', () {
      final p = _player(maxDepth: 200);
      final raw = jsonDecode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: p).encode(),
      ) as Map<String, dynamic>;
      raw['version'] = 5;
      (raw['profile'] as Map)
        ..remove('lairCircles')
        ..remove('lairAttempts');

      final loaded = SaveData.decode(jsonEncode(raw));
      expect(loaded.version, SaveData.currentVersion);
      expect(loaded.profile.lairCircles, isEmpty);
      expect(loaded.profile.lairAttempts, 0);
    });
  });
}

/// Бой, в котором герой долго стоит и почти не бьёт: против него страж
/// успевает показать все умения.
///
/// Герой собран из статов напрямую, а не из снаряжения: вещи дают урон и
/// здоровье одним множителем, и «живучий, но беззубый» из них не собрать —
/// такой герой либо убивал стража за тик, либо умирал за тик.
WaveRunner _enduranceFight(EnemyArchetype guardian,
    {required int seed, CombatFeed? feed, double? killIn, double? heroHp}) {
  final depth = Curves.lairReferenceDepth;
  final enemy = EnemyInstance.spawn(guardian, depth,
      hpMultiplier: Curves.lairHpScale(depth));
  // [killIn] — за сколько секунд герой снёс бы стража без брони и щитов.
  // Брони у стража немного, и порядок времени боя это задаёт.
  final damage = killIn == null ? 0.001 : enemy.maxHp / killIn;
  return WaveRunner(
    bus: EventBus(),
    depth: depth,
    hero: HeroState(StatBlock(
      maxHp: heroHp ?? 1e12,
      attackDamage: damage,
      attackSpeed: 1.0,
      maxMana: 100.0,
    )),
    enemies: [enemy],
    rng: Rng(seed),
    feed: feed,
  );
}

/// Игрок с рекордом [maxDepth], одним наёмником в резерве и, если задан
/// [stashIlvl], полным комплектом вещей этого уровня в сундуке: вызов
/// досбирает пустые слоты тем же правилом, что и отправка вниз.
PlayerProfile _player({
  required int maxDepth,
  double gold = 1e40,
  int? stashIlvl,
}) {
  final p = PlayerProfile(maxDepthEver: maxDepth, gold: gold);
  p.roster.reserve.add(MercFactory.roll(
    Rng.stream(5, 0, 0, RngPurpose.tavern),
    tavernLevel: 0,
    idPrefix: 'lair',
  ));
  p.roster.reserve.first.gear.unequipAll();

  if (stashIlvl != null) {
    final rng = Rng.stream(9, stashIlvl, 0, RngPurpose.lootRoll);
    for (final kind in Equipment.slotKinds) {
      p.stash.add(ItemFactory.roll(ilvl: stashIlvl, rng: rng, kind: kind));
    }
  }
  return p;
}
