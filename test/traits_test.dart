import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Черта, объявленная в контенте, но не читаемая симуляцией, — это описание,
/// а не механика. Здесь каждая черта проверяется в лоб: тот же бой с чертой и
/// без неё обязан разойтись, и разойтись в предсказуемую сторону.

const _depth = 30;

EnemyArchetype _dummy({Set<EnemyTrait> traits = const {}}) => EnemyArchetype(
      id: 'dummy',
      name: 'Болванчик',
      // 5, а не 1.5: кривая HP мобов стала пологой (1.14 -> 1.06), и на
      // тридцатом этаже прежний болванчик умирал с одного-двух ударов —
      // «вампиризм удлиняет бой» проверять было не на чем.
      hpMult: 5.0,
      dpsMult: 0.5,
      attackSpeed: 1.0,
      packMin: 1,
      packMax: 1,
      weight: 1.0,
      traits: traits,
    );

WaveOutcome _fight(EnemyArchetype archetype, {double power = 1.0}) {
  final hero = HeroState(Tuning.heroBase.scaled(power));
  final pack = [EnemyInstance.spawn(archetype, _depth)];
  return WaveCombat(bus: EventBus(), depth: _depth)
      .run(hero, pack, Rng(12345));
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  test('замедление удлиняет бой', () {
    final plain = _fight(_dummy());
    final slow = _fight(_dummy(traits: {EnemyTrait.slowsHero}));

    expect(plain.heroAlive, isTrue);
    expect(slow.seconds, greaterThan(plain.seconds));

    // Замедление ровно на объявленную долю: бой длиннее в 1/(1−slow) раз.
    final expected = plain.seconds / (1.0 - Tuning.slowFraction);
    expect(slow.seconds, closeTo(expected, expected * 0.15));
  });

  test('вампиризм моба удлиняет бой и не даёт ему уйти выше максимума', () {
    final plain = _fight(_dummy());
    final leech = _fight(_dummy(traits: {EnemyTrait.lifesteal}));

    expect(leech.seconds, greaterThan(plain.seconds));

    final e = EnemyInstance.spawn(_dummy(traits: {EnemyTrait.lifesteal}), 1);
    e.takeDamage(e.maxHp * 0.5);
    e.heal(e.maxHp);
    expect(e.hp, e.maxHp);
  });

  test('разгон бьёт по затяжному бою, а не по первому удару', () {
    final plain = _fight(_dummy());
    final ramp = _fight(_dummy(traits: {EnemyTrait.rampUp}));

    expect(ramp.damageTaken, greaterThan(plain.damageTaken));

    // Разгон ограничен потолком: даже в очень долгом бою прибавка урона
    // не может превысить rampCap.
    final ratio = ramp.damageTaken / plain.damageTaken;
    expect(ratio, lessThan(1.0 + Tuning.rampCap));
  });

  test('срез сопротивлений виден только когда сопротивления есть', () {
    // Голый герой сопротивлений не имеет — черта обязана быть безразличной.
    final plain = _fight(_dummy());
    final shred = _fight(_dummy(traits: {EnemyTrait.shredResists}));
    expect(shred.damageTaken, closeTo(plain.damageTaken, 1e-9));

    // С сопротивлениями — обязана кусаться.
    WaveOutcome fightResistant({required bool shredded}) {
      final hero =
          HeroState(Tuning.heroBase + const StatBlock(resistFire: 50.0));
      final pack = [
        EnemyInstance.spawn(
          EnemyArchetype(
            id: 'burner',
            name: 'Поджигатель',
            hpMult: 1.5,
            dpsMult: 0.5,
            attackSpeed: 1.0,
            weight: 1.0,
            damageType: DamageType.fire,
            traits: shredded ? {EnemyTrait.shredResists} : const {},
          ),
          _depth,
        )
      ];
      return WaveCombat(bus: EventBus(), depth: _depth)
          .run(hero, pack, Rng(12345));
    }

    final safe = fightResistant(shredded: false);
    final cut = fightResistant(shredded: true);
    expect(cut.damageTaken, greaterThan(safe.damageTaken));
  });

  test('черты не стакаются: три носителя равны одному', () {
    WaveOutcome fightPack(int count) {
      final hero = HeroState(Tuning.heroBase);
      final archetype = _dummy(traits: {EnemyTrait.slowsHero});
      final pack = [
        for (var i = 0; i < count; i++)
          EnemyInstance.spawn(archetype, _depth),
      ];
      return WaveCombat(bus: EventBus(), depth: _depth)
          .run(hero, pack, Rng(12345));
    }

    // Прямое сравнение длительности бессмысленно — мобов больше. Сравниваем
    // темп: секунд на единицу нанесённого урона.
    final one = fightPack(1);
    final three = fightPack(3);
    final paceOne = one.seconds / one.damageDealt;
    final paceThree = three.seconds / three.damageDealt;
    // Допуск широкий намеренно: сравнивается ТЕМП, а он слегка плывёт от
    // любой правки боя. Ловится здесь не дрейф в проценты, а стакающееся
    // замедление — оно дало бы разницу в разы.
    expect(paceThree, closeTo(paceOne, paceOne * 0.2));
  });
}
