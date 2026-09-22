import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Раунд 41: урон на позднем этапе.
///
/// Замер `sim_cli --late` показал, что с шестидесятого контракта враг гибнет с
/// одного удара и урон не стоит ни этажа, а поздний спуск обрывают взрывы
/// трупов и отражение — урон мимо брони и сопротивлений. Тест держит три
/// правила, которые из этого выросли: взрыв и отражение идут через защиту,
/// босс бездны толще по кривой вещей и разъяряется по таймеру, а Клеймо
/// поднимает здоровье мобов своей ручкой.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  WaveRunner fight(
    EnemyInstance enemy,
    StatBlock hero, {
    int depth = 100,
    CombatFeed? feed,
  }) =>
      WaveRunner(
        bus: EventBus(),
        depth: depth,
        hero: HeroState(hero),
        enemies: [enemy],
        rng: Rng(7),
        feed: feed,
      );

  void tickFor(WaveRunner runner, double seconds) {
    final ticks = (seconds / 0.1).round();
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
  }

  group('взрыв и отражение идут через защиту', () {
    const boom = EnemyArchetype(
      id: 'test_boom',
      name: 'Головня',
      damageType: DamageType.fire,
      attackSpeed: 0.001,
      traits: {EnemyTrait.explodesOnDeath},
    );
    const mirror = EnemyArchetype(
      id: 'test_mirror',
      name: 'Громовой страж',
      attackSpeed: 0.001,
      traits: {EnemyTrait.reflects},
    );

    EnemyInstance bomb() => EnemyInstance(
          archetype: boom,
          maxHp: 1,
          damagePerHit: 100,
          armor: 0,
          attackSpeed: 0.001,
        );

    double explosionTaken(StatBlock hero) {
      final runner = fight(bomb(), hero);
      tickFor(runner, 2);
      return runner.outcome.damageTaken;
    }

    const naked =
        StatBlock(maxHp: 1e6, attackDamage: 50, attackSpeed: 5, armor: 1);

    test('броня режет взрыв', () {
      final bare = explosionTaken(naked);
      final armored = explosionTaken(naked + const StatBlock(armor: 1e6));
      expect(bare, greaterThan(0.0), reason: 'взрыв обязан бить');
      expect(armored, lessThan(bare * 0.5));
    });

    test('сопротивление режет взрыв своей стихии', () {
      final bare = explosionTaken(naked);
      final resisted =
          explosionTaken(naked + const StatBlock(resistFire: 60));
      expect(resisted, lessThan(bare));
    });

    test('у гибели от взрыва есть убийца', () {
      // Мимо единой точки урона взрыв убивал героя без записи, кто это
      // сделал: в анатомии позднего боя десять гибелей из двенадцати были
      // «без убийцы».
      final runner =
          fight(bomb(), const StatBlock(maxHp: 50, attackDamage: 50, attackSpeed: 5));
      tickFor(runner, 2);
      expect(runner.outcome.heroAlive, isFalse);
      expect(runner.outcome.killer, same(boom));
    });

    test('броня режет отражение', () {
      double reflected(StatBlock hero) {
        final runner = fight(
          EnemyInstance(
            archetype: mirror,
            maxHp: 1e12,
            damagePerHit: 100,
            armor: 0,
            attackSpeed: 0.001,
          ),
          hero,
        );
        tickFor(runner, 5);
        return runner.outcome.damageTaken;
      }

      final bare = reflected(naked);
      final armored = reflected(naked + const StatBlock(armor: 1e6));
      expect(bare, greaterThan(0.0), reason: 'отражатель обязан отвечать');
      expect(armored, lessThan(bare * 0.5));
    });
  });

  group('босс бездны — проверка урона', () {
    test('здоровье босса: у первых этажей прежнее, к глубине набора — мощь', () {
      final early = Curves.bossHpScale(5) / Curves.lairHpScale(5);
      expect(early, closeTo(1.0, 0.01),
          reason: 'босс пятого этажа — стена первого спуска при любой прибавке');

      final full = Curves.bossMightDepth;
      expect(Curves.bossHpScale(full),
          closeTo(Curves.lairHpScale(full) * Curves.bossMight, 1e-9));

      var previous = 0.0;
      for (var depth = 50; depth <= 600; depth += 50) {
        final scale = Curves.bossHpScale(depth);
        expect(scale, greaterThan(previous), reason: 'глубина $depth');
        previous = scale;
      }
    });

    test('босс, которого не убили вовремя, разъяряется', () {
      const lord = EnemyArchetype(
        id: 'test_lord',
        name: 'Владыка',
        isBoss: true,
        everyFloors: 5,
      );
      final boss = EnemyInstance(
        archetype: lord,
        maxHp: 1e12,
        damagePerHit: 1,
        armor: 0,
        attackSpeed: 1,
      );
      final feed = CombatFeed(capacity: 4096);
      final runner = fight(
        boss,
        const StatBlock(maxHp: 1e9, attackDamage: 1, attackSpeed: 1),
        depth: Curves.bossMightDepth,
        feed: feed,
      );

      tickFor(runner, 2);
      final early = runner.outcome.damageTaken;
      expect(boss.enraged, isFalse);

      tickFor(runner, 8);
      expect(boss.enraged, isTrue);
      expect(
        feed.drain().where(
            (b) => b.kind == BeatKind.bossSkill && b.id == 'boss_enrage'),
        isNotEmpty,
        reason: 'ярость видна на экране боя',
      );

      final before = runner.outcome.damageTaken;
      tickFor(runner, 2);
      final late = runner.outcome.damageTaken - before;
      expect(late, greaterThan(early),
          reason: 'разъярённый бьёт сильнее, чем в начале боя');
    });

    test('страж таймера ярости не знает — у него своя, умением', () {
      final guardian = Bestiary.guardians.first;
      final feed = CombatFeed(capacity: 4096);
      final runner = fight(
        EnemyInstance.spawn(guardian, 150, hpMultiplier: 1e9),
        const StatBlock(maxHp: 1e12, attackDamage: 1, attackSpeed: 1),
        depth: 150,
        feed: feed,
      );
      tickFor(runner, 10);
      expect(
        feed.drain().where((b) => b.id == 'boss_enrage'),
        isEmpty,
      );
    });
  });

  test('Клеймо поднимает здоровье и урон мобов разными ручками', () {
    final scavenger = ContentPack.current.enemies.first;
    final plain = EnemyInstance.spawn(scavenger, 100);
    final branded = EnemyInstance.spawn(scavenger, 100, brandRank: 10);

    expect(branded.maxHp / plain.maxHp,
        closeTo(Curves.brandMobHpMultiplier(10), 1e-9));
    expect(branded.damagePerHit / plain.damagePerHit,
        closeTo(Curves.brandMobMultiplier(10), 1e-9));
  });
}
