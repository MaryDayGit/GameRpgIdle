import 'dart:convert';

import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/sim/triggers.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Модификатор этажа трогает всё сразу: статы героя, статы мобов, число волн,
/// добычу и Эхо. Проверяется каждый эффект по отдельности — иначе «работает
/// вроде бы» означает «половина эффектов молча не читается».

/// Подменяет список модификаторов ровно одним. Тогда любая развилка выберет
/// именно его, и эффект можно наблюдать в чистом виде.
void _useSingleModifier(Map<String, Object> effects) {
  final files = readContentJson();
  final copy = jsonDecode(jsonEncode(files)) as Map<String, Object?>;
  (copy['floor_modifiers'] as Map<String, dynamic>)['modifiers'] = [
    {
      'id': 'test',
      'ru': 'Проба',
      'minus': 'минус',
      'plus': 'плюс',
      'effects': effects,
    }
  ];
  ContentPack.parse(copy).apply();
}

RunResult _run({int seed = 42, int floorCap = 40, double power = 3.0}) =>
    DescentSimulator(
      profile: HeroProfile(powerMultiplier: power),
      seed: seed,
    ).run(floorCap: floorCap);

void main() {
  setUp(() => loadContentFromDisk().apply());

  group('развилка', () {
    test('приходит только на каждый N-й этаж', () {
      for (var depth = 1; depth <= 12; depth++) {
        expect(ForkChooser.isForkFloor(depth),
            depth % Tuning.forkEveryFloors == 0,
            reason: 'этаж $depth');
      }
    });

    test('детерминирована по сиду и предлагает два разных пути', () {
      final a = ForkChooser.roll(42, 6, ForkPolicy.loot);
      final b = ForkChooser.roll(42, 6, ForkPolicy.loot);

      expect(a.options.map((m) => m.id), b.options.map((m) => m.id));
      expect(a.chosen.id, b.chosen.id);
      expect(a.options.first.id, isNot(a.options[1].id),
          reason: 'развилка из двух одинаковых вариантов — это не выбор');
    });

    test('политики выбирают по-разному', () {
      // Ищем развилку, где жадный и осторожный выборы расходятся: если такой
      // нет ни на одном этаже, политика ни на что не влияет.
      var differs = 0;
      for (var depth = 3; depth <= 300; depth += 3) {
        final loot = ForkChooser.roll(7, depth, ForkPolicy.loot).chosen;
        final safety = ForkChooser.roll(7, depth, ForkPolicy.safety).chosen;
        if (loot.id != safety.id) differs++;
      }
      expect(differs, greaterThan(10));
    });

    test('оценки политик читают именно свои эффекты', () {
      final pack = ContentPack.current;
      final hunger = pack.floorModifier('hunger')!; // +40 % лута, нет регена
      final vice = pack.floorModifier('vice')!; // боссы ×2 Эха
      final swarm = pack.floorModifier('swarm')!; // волн ×2, мобов ×2

      expect(ForkChooser.lootScore(hunger),
          greaterThan(ForkChooser.lootScore(vice)));
      expect(ForkChooser.echoScore(vice), greaterThan(0.0));
      expect(ForkChooser.dangerScore(swarm),
          greaterThan(ForkChooser.dangerScore(vice)));
    });
  });

  group('эффекты в бою', () {
    WaveRunner runner({
      required CombatModifiers mods,
      List<String> abilities = const [],
      double hpRegen = 0.0,
    }) {
      final hero = HeroState(StatBlock(
        maxHp: 100000.0,
        hpRegen: hpRegen,
        armor: 25.0,
        attackDamage: 100.0,
        attackSpeed: 1.0,
      ));
      hero.hp = hero.stats.maxHp * 0.5;

      return WaveRunner(
        bus: EventBus(),
        depth: 30,
        hero: hero,
        enemies: [
          EnemyInstance.spawn(
            const EnemyArchetype(
              id: 'x',
              name: 'X',
              hpMult: 40.0,
              dpsMult: 0.05,
              attackSpeed: 1.0,
              weight: 1.0,
            ),
            30,
          )
        ],
        rng: Rng(1),
        abilities: AbilityRuntime.fromIds(abilities, modifiers: mods),
      );
    }

    test('«Голод» выключает восстановление HP', () {
      final on = runner(mods: CombatModifiers(), hpRegen: 10.0);
      for (var i = 0; i < 50; i++) {
        on.tick();
      }

      final off = runner(
        mods: CombatModifiers()..regenDisabled = true,
        hpRegen: 10.0,
      );
      for (var i = 0; i < 50; i++) {
        off.tick();
      }

      expect(on.hero.hp, greaterThan(off.hero.hp));
    });

    test('«Тишина» гасит ауру и усиливает автоатаки', () {
      final aura = runner(
        mods: CombatModifiers(),
        abilities: const ['frost_shroud'],
      );
      aura.tick();
      expect(aura.enemies.first.slowed, isTrue);

      final silenced = runner(
        mods: CombatModifiers()..aurasDisabled = true,
        abilities: const ['frost_shroud'],
      );
      silenced.tick();
      expect(silenced.enemies.first.slowed, isFalse);

      // Плюс модификатора: автоатаки бьют сильнее.
      final plain = runner(mods: CombatModifiers());
      final boosted = runner(mods: CombatModifiers()..autoAttackDamage = 0.5);
      for (var i = 0; i < 100; i++) {
        plain.tick();
        boosted.tick();
      }
      final plainDamage = plain.enemies.first.maxHp - plain.enemies.first.hp;
      final boostedDamage =
          boosted.enemies.first.maxHp - boosted.enemies.first.hp;
      expect(boostedDamage, closeTo(plainDamage * 1.5, plainDamage * 0.01));
    });
  });

  group('эффекты этажа', () {
    test('множители статов мобов доходят до спавна', () {
      const archetype = EnemyArchetype(
        id: 'x',
        name: 'X',
        hpMult: 1.0,
        dpsMult: 1.0,
        attackSpeed: 1.0,
        weight: 1.0,
      );
      final plain = EnemyInstance.spawn(archetype, 20);
      final buffed = EnemyInstance.spawn(archetype, 20,
          hpMultiplier: 0.6, dpsMultiplier: 1.2);

      expect(buffed.maxHp, closeTo(plain.maxHp * 0.6, 1e-9));
      expect(buffed.damagePerHit, closeTo(plain.damagePerHit * 1.2, 1e-9));
    });

    test('«Рой» удваивает число волн', () {
      _useSingleModifier({'waveMultiplier': 2.0, 'mobHp': -0.4});

      final driver = DescentDriver(
        profile: HeroProfile(powerMultiplier: 3.0),
        seed: 42,
        floorCap: 10,
      );

      final waveCounts = <int, int>{};
      while (!driver.finished) {
        waveCounts[driver.depth] = driver.snapshot.waveCount;
        driver.tick();
      }

      expect(waveCounts[1], Tuning.wavesPerFloor,
          reason: 'до первой развилки путь не выбран');
      expect(waveCounts[3], Tuning.wavesPerFloor * 2,
          reason: 'развилка выбрана — путь начался');
      expect(waveCounts[4], Tuning.wavesPerFloor * 2,
          reason: 'путь держится до следующей развилки, а не один этаж');
    });

    test('«+лут» увеличивает количество найденного', () {
      _useSingleModifier({'lootQuantity': 1.0});
      final rich = _run();

      _useSingleModifier({'lootQuantity': 0.0, 'mobHp': 0.0});
      final plain = _run();

      expect(rich.itemsFound, greaterThan(plain.itemsFound));
    });

    test('«+ранг редкости» поднимает редкость выпавшего', () {
      final rng = Rng(3);
      var raised = 0;
      for (var i = 0; i < 300; i++) {
        final plain = ItemFactory.roll(ilvl: 20, rng: Rng(1000 + i));
        final better =
            ItemFactory.roll(ilvl: 20, rng: Rng(1000 + i), rarityBonus: 1);
        if (better.rarity.rank > plain.rarity.rank) raised++;
        expect(better.rarity.rank, greaterThanOrEqualTo(plain.rarity.rank));
      }
      expect(raised, greaterThan(200), reason: 'подъём гарантирован, а не шанс');

      // Потолок не пробивается.
      final top = ItemFactory.roll(ilvl: 20, rng: rng, rarityBonus: 99);
      expect(top.rarity, Rarity.relic);
    });

    test('«Тиски» добавляют Эхо за боссов', () {
      _useSingleModifier({'bossEchoMultiplier': 2.0});
      final rich = _run(floorCap: 40);

      _useSingleModifier({'bossEchoMultiplier': 1.0});
      final plain = _run(floorCap: 40);

      expect(rich.maxDepth, plain.maxDepth,
          reason: 'эффект не должен менять сам спуск');
      expect(rich.echo, greaterThan(plain.echo));
    });

    test('модификатор записывается в журнал этажа', () {
      _useSingleModifier({'lootQuantity': 0.4});
      final result = _run(floorCap: 12);

      for (final floor in result.floors) {
        // Путь начинается на первой развилке и дальше не прерывается.
        final onPath = floor.depth >= Tuning.forkEveryFloors;
        expect(floor.modifierId, onPath ? 'test' : null,
            reason: 'этаж ${floor.depth}');
      }
    });
  });
}
