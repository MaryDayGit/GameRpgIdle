import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Новые виды способностей: добивание, цепь, лечение, шипы, защита на низком
/// здоровье.
///
/// Замечание с телефона было «очень мало умений, не с чего строить билд».
/// Половина ответа — новые ВИДЫ, а не новые числа: способность, которая
/// отличается от соседней только множителем, билда не строит.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  final dummy = EnemyArchetype(
    id: 'dummy',
    name: 'Болванчик',
    hpMult: 90.0,
    dpsMult: 0.4,
    attackSpeed: 1.0,
    weight: 1.0,
  );

  /// Сила чар равна урону оружия: проверяется механика вида способности, а
  /// не то, какая ось сильнее.
  StatBlock stats({double maxHp = 100000.0}) => StatBlock(
        maxHp: maxHp,
        maxMana: 100000.0,
        armor: 25.0,
        attackDamage: 100.0,
        spellPower: 100.0,
        attackSpeed: 1.0,
        critMulti: 1.0,
      );

  /// `tough` — мешок с HP, который не умрёт за время проверки: иначе бой
  /// кончается раньше, чем способность успевает показать себя.
  final huge = EnemyArchetype(
    id: 'huge',
    name: 'Гора',
    hpMult: 4000.0,
    dpsMult: 0.4,
    attackSpeed: 1.0,
    weight: 1.0,
  );

  WaveRunner fight(
    List<String> abilities, {
    HeroState? hero,
    int enemies = 3,
    bool tough = false,
  }) {
    return WaveRunner(
      bus: EventBus(),
      depth: 5,
      hero: hero ?? HeroState(stats()),
      enemies: [
        for (var i = 0; i < enemies; i++)
          EnemyInstance.spawn(tough ? huge : dummy, 5),
      ],
      rng: Rng(7),
      abilities: AbilityRuntime.fromIds(abilities),
    );
  }

  void run(WaveRunner runner, {int ticks = 120}) {
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
  }

  group('добивание', () {
    test('бьёт больнее по раненой цели', () {
      // Способность про добивание, и выбирать она должна самого раненого:
      // иначе её бонус не срабатывает никогда.
      //
      // Сравнивается урон ПО ЦЕЛИ, а не суммарный за волну: раненая цель
      // умирает раньше, волна кончается, и суммарный урон сравнивал бы
      // разную длину боя.
      double hurt({required bool wounded}) {
        final runner = fight(const ['coup_de_grace'], enemies: 1, tough: true);
        final enemy = runner.enemies.first;
        if (wounded) enemy.hp = enemy.maxHp * 0.1;

        final before = enemy.hp;
        run(runner, ticks: 40);
        return before - enemy.hp;
      }

      expect(hurt(wounded: true), greaterThan(hurt(wounded: false)));
    });
  });

  group('цепь', () {
    test('задевает нескольких, но каждого следующего слабее', () {
      final runner = fight(const ['frost_chain_bolt'], enemies: 4);
      run(runner, ticks: 70);

      final hits = [
        for (final e in runner.enemies) e.maxHp - e.hp,
      ]..sort((a, b) => b.compareTo(a));

      expect(hits.where((h) => h > 0).length, greaterThanOrEqualTo(3),
          reason: 'цепь обязана задеть нескольких');
      expect(hits.first, greaterThan(hits[2]),
          reason: 'дальние цели получают меньше');
    });
  });

  group('лечение', () {
    test('лечит раненого и не тратится на здоровом', () {
      final wounded = HeroState(stats())..hp = 40000.0;
      final runner = fight(const ['field_dressing'], hero: wounded);
      run(runner, ticks: 60);

      expect(wounded.hp, greaterThan(40000.0));

      // На полном здоровье способность не должна жечь кулдаун и ману:
      // иначе она сработает вхолостую ровно тогда, когда нужна дальше.
      final healthy = HeroState(stats());
      final calm = fight(const ['field_dressing'], hero: healthy, enemies: 0);
      run(calm, ticks: 5);
      expect(healthy.mana, healthy.stats.maxMana);
    });
  });

  group('шипы', () {
    test('возвращают часть полученного урона ударившему', () {
      final withThorns = fight(const ['spiked_guard'], enemies: 1);
      final without = fight(const [], enemies: 1);

      run(withThorns, ticks: 200);
      run(without, ticks: 200);

      final hurtByThorns = withThorns.enemies.first.maxHp -
          withThorns.enemies.first.hp;
      final hurtPlain = without.enemies.first.maxHp - without.enemies.first.hp;

      expect(hurtByThorns, greaterThan(hurtPlain));
    });
  });

  group('защита на низком здоровье', () {
    test('срезает урон, только когда здоровья мало', () {
      double taken({required double hp, required List<String> abilities}) {
        final hero = HeroState(stats(maxHp: 10000.0))..hp = hp;
        final runner = fight(abilities, hero: hero, enemies: 2);
        run(runner, ticks: 120);
        return runner.outcome.damageTaken;
      }

      const guard = ['last_stand'];
      final low = taken(hp: 1000.0, abilities: guard);
      final lowPlain = taken(hp: 1000.0, abilities: const []);
      final high = taken(hp: 9500.0, abilities: guard);
      final highPlain = taken(hp: 9500.0, abilities: const []);

      expect(low, lessThan(lowPlain), reason: 'на низком здоровье режет');
      expect(high, closeTo(highPlain, highPlain * 0.01),
          reason: 'на полном — не трогает');
    });
  });

  test('каждый вид способности где-то используется', () {
    // Вид, объявленный в коде и не выставленный в контенте, — мёртвая ветка
    // симуляции: она проверяется тестами и не встречается игроку.
    final used = {for (final def in ContentPack.current.abilities) def.kind};
    expect(used, containsAll(AbilityKind.values));
  });
}
