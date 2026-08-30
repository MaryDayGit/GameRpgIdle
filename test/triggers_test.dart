import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/sim/triggers.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Триггер — это подписка на шину. Двенадцать подписок, которые никто не
/// проверял, — двенадцать способов молча ничего не делать или, наоборот,
/// замкнуть шину саму на себя.

const _depth = 30;

EnemyArchetype _archetype({double hpMult = 90.0}) => EnemyArchetype(
      id: 'dummy',
      name: 'Болванчик',
      hpMult: hpMult,
      dpsMult: 0.05,
      attackSpeed: 1.0,
      weight: 1.0,
    );

StatBlock _stats({double critChance = 0.0, double maxHp = 100000.0}) =>
    StatBlock(
      maxHp: maxHp,
      // Мана заведомо избыточна: тест про триггеры, а не про бюджет.
      maxMana: 100000.0,
      armor: 25.0,
      attackDamage: 100.0,
      attackSpeed: 1.0,
      critChance: critChance,
      critMulti: 1.0,
    );

class _Fight {
  _Fight(this.runner, this.hero, this.enemies, this.mods);

  final WaveRunner runner;
  final HeroState hero;
  final List<EnemyInstance> enemies;
  final CombatModifiers mods;

  void run(double seconds) {
    final ticks = (seconds / Tuning.tickSeconds).round();
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
  }

  double get damageDealt =>
      enemies.fold(0.0, (sum, e) => sum + (e.maxHp - e.hp));

  int get aliveCount => enemies.where((e) => e.alive).length;
}

_Fight _fight({
  List<String> abilities = const [],
  List<String> triggers = const [],
  int count = 3,
  double hpMult = 90.0,
  StatBlock? stats,
  EventBus? bus,
  int seed = 1234,
}) {
  final eventBus = bus ?? EventBus();
  final mods = CombatModifiers();
  final abilityRuntime =
      AbilityRuntime.fromIds(abilities, modifiers: mods);
  final triggerRuntime = TriggerRuntime(
    bus: eventBus,
    abilities: abilityRuntime,
    mods: mods,
  )..configure(triggers);

  final hero = HeroState(stats ?? _stats());
  final pack = [
    for (var i = 0; i < count; i++)
      EnemyInstance.spawn(_archetype(hpMult: hpMult), _depth),
  ];

  return _Fight(
    WaveRunner(
      bus: eventBus,
      depth: _depth,
      hero: hero,
      enemies: pack,
      rng: Rng(seed),
      abilities: abilityRuntime,
      triggers: triggerRuntime,
    ),
    hero,
    pack,
    mods,
  );
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  test('Метроном усиливает каждый N-й удар', () {
    final plain = _fight()..run(60.0);
    final metronome = _fight(triggers: const ['metronome'])..run(60.0);

    final def = ContentPack.current.triggerAffix('metronome')!;
    final n = def.params.integer('n');
    final multiplier = def.params.dbl('multiplier');

    // Каждый N-й удар вместо одного урона наносит `multiplier`.
    final expected = 1.0 + (multiplier - 1.0) / n;
    expect(metronome.damageDealt / plain.damageDealt, closeTo(expected, 0.03));
  });

  test('Разряд сбрасывает перезарядку и способность кастуется чаще', () {
    final stats = _stats(critChance: 1.0);
    final plain = _fight(abilities: const ['cleave'], stats: stats)..run(30.0);
    final discharge = _fight(
      abilities: const ['cleave'],
      triggers: const ['discharge'],
      stats: stats,
    )..run(30.0);

    expect(discharge.damageDealt, greaterThan(plain.damageDealt));
  });

  test('Гон копит стаки при убийствах и не пробивает потолок', () {
    final chase = _fight(
      triggers: const ['chase'],
      count: 6,
      hpMult: 0.4,
    )..run(20.0);

    final def = ContentPack.current.triggerAffix('chase')!;
    final maxBonus =
        def.params.dbl('value') * def.params.integer('maxStacks');

    expect(chase.aliveCount, lessThan(6), reason: 'кто-то должен умереть');
    expect(chase.runner.abilities.buffAttackSpeed, greaterThan(0.0));
    expect(chase.runner.abilities.buffAttackSpeed,
        lessThanOrEqualTo(maxBonus + 1e-9),
        reason: 'потолок стаков обязан держать');
  });

  test('Тлен вешает горение от способности с нужным тегом', () {
    final withFire = _fight(
      abilities: const ['fire_brand'],
      triggers: const ['smoulder'],
    )..run(1.0);
    expect(withFire.enemies.first.dotRemaining, greaterThan(0.0));

    // Способность без тега Огонь триггер не трогает.
    final withoutFire = _fight(
      abilities: const ['cleave'],
      triggers: const ['smoulder'],
    )..run(1.0);
    expect(withoutFire.enemies.first.dotRemaining, 0.0);
  });

  test('Отчаяние включается ниже порога и выключается выше', () {
    final def = ContentPack.current.triggerAffix('desperation')!;
    final threshold = def.params.dbl('threshold');

    final healthy = _fight(triggers: const ['desperation'])..run(1.0);
    expect(healthy.mods.moreDamage, 0.0);
    expect(healthy.mods.lessArmor, 0.0);

    final wounded = _fight(triggers: const ['desperation']);
    wounded.hero.hp = wounded.hero.stats.maxHp * (threshold - 0.05);
    wounded.run(1.0);

    expect(wounded.mods.moreDamage, closeTo(def.params.dbl('moreDamage'), 1e-9));
    expect(wounded.mods.lessArmor, closeTo(def.params.dbl('lessArmor'), 1e-9));

    // И это должно быть видно по урону, а не только по флагу.
    final plain = _fight();
    plain.hero.hp = plain.hero.stats.maxHp * (threshold - 0.05);
    plain.run(10.0);

    final boosted = _fight(triggers: const ['desperation']);
    boosted.hero.hp = boosted.hero.stats.maxHp * (threshold - 0.05);
    boosted.run(10.0);

    expect(boosted.damageDealt, greaterThan(plain.damageDealt));
  });

  test('Двойной удар удваивает каст по таймеру', () {
    final plain = _fight(abilities: const ['cleave'])..run(30.0);
    final doubled = _fight(
      abilities: const ['cleave'],
      triggers: const ['double_strike'],
    )..run(30.0);

    expect(doubled.damageDealt, greaterThan(plain.damageDealt));
  });

  test('Мор распространяет проклятие на всю волну', () {
    final plain = _fight(abilities: const ['fire_brand'])..run(1.0);
    expect(plain.enemies.where((e) => e.cursed).length, 1);

    final spread = _fight(
      abilities: const ['fire_brand'],
      triggers: const ['pestilence'],
    )..run(1.0);
    expect(spread.enemies.every((e) => e.cursed), isTrue);
  });

  test('Отражение бьёт атакующего', () {
    // Моб должен пережить бой: иначе оба замера упрутся в его максимум HP
    // и покажут одно и то же число независимо от триггера.
    final plain = _fight(count: 1, hpMult: 400.0)..run(60.0);
    final reflect =
        _fight(triggers: const ['reflection'], count: 1, hpMult: 400.0)
          ..run(60.0);

    expect(plain.aliveCount, 1, reason: 'замер испорчен, если моб умер');

    expect(reflect.damageDealt, greaterThan(plain.damageDealt));
  });

  test('Авангард усиливает первый удар по волне и только его', () {
    final hits = <double>[];
    final bus = EventBus();
    final fight = _fight(triggers: const ['vanguard'], bus: bus, count: 1);

    // Подписка после сборки боя: триггеры пересобирают свои подписки в
    // configure, и до этого момента чужой слушатель поставить некуда.
    bus.subscribe(GameEventType.onHit, (ctx) => hits.add(ctx.amount), 'лог');
    fight.run(5.0);

    expect(hits.length, greaterThan(2));
    final def = ContentPack.current.triggerAffix('vanguard')!;
    expect(hits.first / hits[1],
        closeTo(1.0 + def.params.dbl('moreDamage'), 1e-6));
    expect(hits[1], closeTo(hits[2], 1e-9),
        reason: 'бонус разовый, а не постоянный');
    expect(fight.mods.firstHitPending, isFalse);
  });

  test('Кровавая дань лечит за убийство проклятого', () {
    final fight = _fight(
      abilities: const ['fire_brand'],
      triggers: const ['blood_tithe'],
      count: 4,
      hpMult: 0.4,
    );
    fight.hero.hp = fight.hero.stats.maxHp * 0.5;
    final before = fight.hero.hp;
    fight.run(20.0);

    expect(fight.aliveCount, lessThan(4));
    expect(fight.hero.hp, greaterThan(before),
        reason: 'мобы бьют слабо, вырасти HP мог только от дани');
  });

  test('Резонанс тотемов продлевает баф', () {
    final def = ContentPack.current.triggerAffix('totem_resonance')!;
    final ability = ContentPack.current.ability('totem_of_fury')!;
    final base = ability.params.dbl('duration');

    final plain = _fight(abilities: const ['totem_of_fury'])
      ..run(base + 0.5);
    expect(plain.runner.abilities.buffAttackSpeed, 0.0);

    final boosted = _fight(
      abilities: const ['totem_of_fury'],
      triggers: const ['totem_resonance'],
    )..run(base + 0.5);
    expect(boosted.runner.abilities.buffAttackSpeed, greaterThan(0.0));

    // И значение бафа тоже выросло.
    expect(
      boosted.runner.abilities.buffAttackSpeed,
      closeTo(ability.params.dbl('value') * (1.0 + def.params.dbl('rate')),
          1e-9),
    );
  });

  test('Ледяная цепь замедляет соседей при смерти замедленного', () {
    final chain = _fight(
      abilities: const ['frost_shroud'],
      triggers: const ['frost_chain'],
      count: 5,
      // Мешок под эту проверку подбирается отдельно: нужно, чтобы за восемь
      // секунд кто-то умер, но не все. Кривая HP мобов стала пологой, и
      // прежние 2.0 не доживали до конца проверки.
      hpMult: 5.0,
    )..run(8.0);

    expect(chain.aliveCount, inInclusiveRange(1, 4),
        reason: 'кто-то должен умереть, но не все');
    expect(chain.enemies.where((e) => e.alive && e.slowed).length,
        greaterThan(0));
  });

  group('предохранители', () {
    test('триггеры не выбивают шину в аномалию', () {
      // Самая опасная комбинация: крит сбрасывает кулдаун, крит вешает дот,
      // удар усиливается — всё на одном тике.
      final bus = EventBus();
      final fight = _fight(
        abilities: const ['cleave', 'ashfield', 'fire_brand'],
        triggers: const ['metronome', 'discharge', 'vanguard'],
        stats: _stats(critChance: 1.0),
        bus: bus,
      )..run(60.0);

      expect(fight.damageDealt, greaterThan(0.0));
      expect(bus.hasAnomalies, isFalse);
    });

    test('добавка от триггера не порождает событий', () {
      var hits = 0;
      final bus = EventBus()
        ..subscribe(GameEventType.onHit, (_) => hits++, 'счётчик');
      final fight = _fight(triggers: const ['metronome'], bus: bus, count: 1)
        ..run(30.0);

      var plainHits = 0;
      final plainBus = EventBus()
        ..subscribe(GameEventType.onHit, (_) => plainHits++, 'счётчик');
      _fight(bus: plainBus, count: 1).run(30.0);

      expect(fight.damageDealt, greaterThan(0.0));
      expect(hits, plainHits,
          reason: 'иначе «каждый N-й удар» считал бы сам себя');
    });
  });
}
