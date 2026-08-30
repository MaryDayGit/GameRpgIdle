import 'package:rift/core/content/passive_tree_def.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/passive_tree.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/passive_rules.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Узлы дерева, меняющие ПРАВИЛА, а не числа.
///
/// Дерево из одних процентов — ползунок: любой узел заменяется любым другим
/// той же величины. Правила существуют ради узлов, ради которых билд строят.
/// Проверяется здесь именно это: что правило меняет ход боя, а не добавляет
/// ещё одно слагаемое.
/// Мешок с HP: волна не должна кончиться раньше, чем правило сработает.
final _dummy = EnemyArchetype(
  id: 'dummy',
  name: 'Болванчик',
  hpMult: 40.0,
  dpsMult: 0.05,
  attackSpeed: 1.0,
  weight: 1.0,
);

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  /// Дерево с одним взятым узлом — тем, что несёт нужное правило.
  PassiveTree treeWith(PassiveRule rule) {
    final tree = PassiveTree();
    final node = tree.nodes.firstWhere((n) => n.rule == rule);
    return PassiveTree(allocated: {node.id});
  }

  group('пересчёты статов живут в сборке билда', () {
    test('мана становится уроном', () {
      // Правило превращает один стат в другой, и это должно быть видно в
      // силе билда на экране — то есть посчитано в агрегате, а не в бою.
      final rule = treeWith(PassiveRule.manaToDamage);
      final node = rule.nodes.firstWhere(
          (n) => n.rule == PassiveRule.manaToDamage);

      const base = StatBlock(maxMana: 200.0, increasedDamage: 0.1);
      final out = rule.applyTo(base);

      expect(out.increasedDamage,
          closeTo(0.1 + 200.0 * node.ruleValue, 1e-9));
    });

    test('броня становится сопротивлением', () {
      final rule = treeWith(PassiveRule.armorToResist);
      const base = StatBlock(armor: 500.0);

      final out = rule.applyTo(base);
      expect(out.resistFire, greaterThan(0.0));
      expect(out.resistCold, out.resistFire);
      expect(out.resistVoid, out.resistFire);
    });

    test('здоровье становится бронёй', () {
      final rule = treeWith(PassiveRule.hpToArmor);
      const base = StatBlock(maxHp: 2000.0, armor: 100.0);

      expect(rule.applyTo(base).armor, greaterThan(100.0));
    });

    test('пересчёт считается от исходного билда, а не от накопленного', () {
      // Иначе «часть брони становится сопротивлением» зависела бы от того,
      // в каком порядке обходятся узлы, — а результат обязан быть один.
      final tree = treeWith(PassiveRule.hpToArmor);
      const base = StatBlock(maxHp: 1000.0, armor: 100.0);

      final once = tree.applyTo(base);
      final twice = tree.applyTo(base);
      expect(once.armor, twice.armor);
    });
  });

  group('боевые правила живут в бою', () {
    /// Волна из одного слабого моба и герой, который убивает его с одного
    /// удара: нужно ровно одно убийство.
    WaveRunner fight({
      required PassiveRules passives,
      required HeroState hero,
      double enemyHp = 1.0,
    }) {
      final enemy = EnemyInstance.spawn(_dummy, 1)..hp = enemyHp;

      return WaveRunner(
        bus: EventBus(),
        depth: 1,
        hero: hero,
        enemies: [enemy],
        rng: Rng(1),
        passives: passives,
      );
    }

    test('убийство лечит — и лечит один раз на убитого', () {
      final hero = HeroState(const StatBlock(
        maxHp: 1000.0,
        attackDamage: 1000.0,
        attackSpeed: 10.0,
        maxMana: 100.0,
      ))..hp = 500.0;

      final runner = fight(
        passives: const PassiveRules(killHeal: 0.1),
        hero: hero,
      );

      var guard = 0;
      while (!runner.finished && ++guard < 200) {
        runner.tick();
      }

      expect(hero.hp, greaterThan(500.0), reason: 'жатва обязана лечить');
      expect(hero.hp, lessThanOrEqualTo(1000.0));
    });

    test('без правила убийство не лечит', () {
      // Контроль: иначе тест выше проходил бы и на вампиризме.
      final hero = HeroState(const StatBlock(
        maxHp: 1000.0,
        attackDamage: 1000.0,
        attackSpeed: 10.0,
        maxMana: 100.0,
      ))..hp = 500.0;

      final runner = fight(passives: PassiveRules.none, hero: hero);
      var guard = 0;
      while (!runner.finished && ++guard < 200) {
        runner.tick();
      }

      expect(hero.hp, 500.0);
    });

    test('ниже половины здоровья урон умножается', () {
      double damage({required double hp, required PassiveRules passives}) {
        final hero = HeroState(const StatBlock(
          maxHp: 1000.0,
          attackDamage: 50.0,
          attackSpeed: 1.0,
          maxMana: 100.0,
        ))..hp = hp;

        final runner = fight(
          passives: passives,
          hero: hero,
          enemyHp: 1e9,
        );
        var guard = 0;
        while (guard++ < 20) {
          runner.tick();
        }
        return runner.outcome.damageDealt;
      }

      const rule = PassiveRules(lowLifeMoreDamage: 0.5);
      final healthy = damage(hp: 900.0, passives: rule);
      final wounded = damage(hp: 100.0, passives: rule);

      expect(wounded, greaterThan(healthy),
          reason: 'правило обязано срабатывать именно на низком здоровье');
      expect(damage(hp: 100.0, passives: PassiveRules.none),
          lessThan(wounded));
    });
  });


  /// Правила стихийных лучей.
  ///
  /// Пять лучей дерева добавлены вместе с пятью правилами, и каждое из них —
  /// ровно тот случай, про который сказано выше: число, которого никто не
  /// читает, — не эффект. Проверяется, что каждое доходит до боя.
  group('стихийные правила доходят до боя', () {
    WaveRunner fight({
      required PassiveRules passives,
      required List<String> abilities,
      required StatBlock stats,
      int enemies = 1,
    }) =>
        WaveRunner(
          bus: EventBus(),
          depth: 1,
          hero: HeroState(stats),
          enemies: [
            for (var i = 0; i < enemies; i++) EnemyInstance.spawn(_dummy, 1),
          ],
          rng: Rng(3),
          passives: passives,
          abilities: AbilityRuntime.fromIds(abilities),
        );

    double dealt(WaveRunner runner, {int ticks = 120}) {
      for (var i = 0; i < ticks && !runner.finished; i++) {
        runner.tick();
      }
      return runner.outcome.damageDealt;
    }

    const caster = StatBlock(
      maxHp: 1e6,
      maxMana: 1e6,
      manaRegen: 1000.0,
      spellPower: 200.0,
      attackSpeed: 1.0,
    );

    test('«Тлеющий уголь» умножает длительный урон, но не прямой', () {
      const burn = ['pyre'];
      final plain = dealt(fight(
          passives: PassiveRules.none, abilities: burn, stats: caster));
      final boosted = dealt(fight(
          passives: const PassiveRules(dotMoreDamage: 1.0),
          abilities: burn,
          stats: caster));

      expect(boosted, greaterThan(plain));

      // Прямой урон правило трогать не должно: иначе это просто ещё один
      // «+% к урону», а размен «бьёт не сразу, зато сильнее» исчезает.
      const direct = ['spark_bolt'];
      final directPlain = dealt(fight(
          passives: PassiveRules.none, abilities: direct, stats: caster));
      final directBoosted = dealt(fight(
          passives: const PassiveRules(dotMoreDamage: 1.0),
          abilities: direct,
          stats: caster));
      expect(directBoosted, closeTo(directPlain, 1.0));
    });

    test('«Стылая хватка» замедляет цель ударом', () {
      final runner = fight(
        passives: const PassiveRules(chillOnHit: 0.3),
        abilities: const [],
        stats: const StatBlock(
            maxHp: 1e6, maxMana: 100.0, attackDamage: 10.0, attackSpeed: 2.0),
      );
      dealt(runner, ticks: 30);

      expect(runner.enemies.first.slowed, isTrue,
          reason: 'ради этого правило и берут');
    });

    test('«Перескок» задевает вторую цель только Молнией', () {
      double spread(List<String> ids) {
        final runner = fight(
          passives: const PassiveRules(shockSplash: 0.5),
          abilities: ids,
          stats: caster,
          enemies: 2,
        );
        dealt(runner, ticks: 40);
        return runner.enemies.last.maxHp - runner.enemies.last.hp;
      }

      // «Разряд» бьёт по ОДНОЙ цели: всё, что достаётся второй, — перескок.
      expect(spread(const ['spark_bolt']), greaterThan(0.0));
      expect(spread(const ['flame_lash']), 0.0,
          reason: 'огонь не перескакивает');
    });

    test('«Печать увядания» умножает урон по проклятым', () {
      double hurt(PassiveRules passives) {
        final runner = fight(
          passives: passives,
          abilities: const ['conduction'],
          stats: caster,
        );
        return dealt(runner, ticks: 120);
      }

      expect(hurt(const PassiveRules(curseMoreDamage: 1.0)),
          greaterThan(hurt(PassiveRules.none)));
    });

    test('«Ум как сосуд» превращает ману в силу чар', () {
      // Пересчёт статов, а не боевое правило: он обязан быть виден в силе
      // билда на экране, то есть посчитан в агрегате.
      final tree = treeWith(PassiveRule.manaToSpellPower);
      final node =
          tree.nodes.firstWhere((n) => n.rule == PassiveRule.manaToSpellPower);

      const base = StatBlock(maxMana: 200.0, spellPower: 10.0);
      final out = tree.applyTo(base);

      expect(out.spellPower, closeTo(10.0 + 200.0 * node.ruleValue, 0.001));
    });
  });

  test('правила собираются из дерева, а не задаются руками', () {
    // Единственное место сборки: два таких места разошлись бы, и правило,
    // видимое на экране, не совпало бы с тем, что происходит в бою.
    final tree = treeWith(PassiveRule.killHeal);
    final rules = PassiveRules.from(tree);

    expect(rules.killHeal, greaterThan(0.0));
    expect(PassiveRules.from(PassiveTree()).isEmpty, isTrue);
    expect(PassiveRules.from(null).isEmpty, isTrue);
  });
}
