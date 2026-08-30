import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/relics.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/sim/triggers.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Реликт меняет ПРАВИЛО, а не цифру. Правило, которое никто не проверял, —
/// это строчка в описании предмета и ничего больше.

Item _relic(String id, {int ilvl = 30, double maxHp = 0.0}) {
  final def = ContentPack.current.relic(id)!;
  return Item(
    kind: def.kind,
    ilvl: ilvl,
    rarity: Rarity.relic,
    affixes: [
      if (maxHp > 0)
        AffixRoll(
          affixId: 'hp',
          stat: StatKey.maxHp,
          percentile: 1.0,
          value: maxHp,
        ),
    ],
    relicId: id,
    relicEffect: def.effect,
  );
}

Item _plain(
  GearKind kind, {
  int ilvl = 30,
  bool twoHanded = false,
  double maxHp = 0.0,
}) =>
    Item(
      kind: kind,
      ilvl: ilvl,
      rarity: Rarity.common,
      affixes: [
        if (maxHp > 0)
          AffixRoll(
            affixId: 'hp',
            stat: StatKey.maxHp,
            percentile: 1.0,
            value: maxHp,
          ),
      ],
      twoHanded: twoHanded,
    );

Equipment _gear(List<Item> items) {
  final equipment = Equipment();
  for (final item in items) {
    equipment.tryEquip(item, base: Tuning.heroBase, depth: 30);
  }
  return equipment;
}

const _archetype = EnemyArchetype(
  id: 'x',
  name: 'X',
  hpMult: 90.0,
  dpsMult: 0.05,
  attackSpeed: 1.0,
  weight: 1.0,
);

class _Fight {
  _Fight(this.runner, this.enemies);

  final WaveRunner runner;
  final List<EnemyInstance> enemies;

  void run(double seconds) {
    final ticks = (seconds / Tuning.tickSeconds).round();
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
  }

  double get damage =>
      enemies.fold(0.0, (sum, e) => sum + (e.maxHp - e.hp));
}

_Fight _fight({
  RelicRules rules = RelicRules.none,
  List<String> abilities = const [],
  List<String> triggers = const [],
  int count = 3,
  double critChance = 0.0,
  EventBus? bus,
}) {
  final eventBus = bus ?? EventBus();
  final mods = CombatModifiers();
  final abilityRuntime =
      AbilityRuntime.fromIds(abilities, modifiers: mods, rules: rules);
  final triggerRuntime = TriggerRuntime(
    bus: eventBus,
    abilities: abilityRuntime,
    mods: mods,
  )
    ..rules = rules
    ..configure(triggers);

  final hero = HeroState(StatBlock(
    maxHp: 100000.0,
    // Мана заведомо избыточна: тест про правила реликтов, а не про бюджет.
    maxMana: 100000.0,
    armor: 25.0,
    attackDamage: 100.0,
    attackSpeed: 1.0,
    critChance: critChance,
    critMulti: 1.0,
  ));
  final pack = [
    for (var i = 0; i < count; i++) EnemyInstance.spawn(_archetype, 30),
  ];

  return _Fight(
    WaveRunner(
      bus: eventBus,
      depth: 30,
      hero: hero,
      enemies: pack,
      rng: Rng(1234),
      abilities: abilityRuntime,
      triggers: triggerRuntime,
      rules: rules,
    ),
    pack,
  );
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('двуручное оружие', () {
    test('занимает обе руки и вытесняет левую', () {
      final equipment = _gear([_plain(GearKind.offhand, maxHp: 100)]);
      expect(equipment.filledSlots, 1);

      final displaced = equipment.tryEquip(
        _plain(GearKind.weapon, twoHanded: true),
        base: Tuning.heroBase,
        depth: 30,
      );

      expect(displaced, hasLength(1), reason: 'щит обязан вернуться в рюкзак');
      expect(displaced.first.kind, GearKind.offhand);
      expect(equipment.offhandUsable, isFalse);
    });

    test('пока надет, щит не влезает', () {
      final equipment = _gear([_plain(GearKind.weapon, twoHanded: true)]);
      final left = equipment.tryEquip(
        _plain(GearKind.offhand, maxHp: 500),
        base: Tuning.heroBase,
        depth: 30,
      );
      expect(left, hasLength(1), reason: 'щит остался на руках');
      expect(equipment.at(1), isNull);
    });

    test('«Расколотый противовес» снимает запрет и берёт своё HP', () {
      final equipment = _gear([
        _plain(GearKind.weapon, twoHanded: true),
        _relic('split_counterweight'),
      ]);

      expect(equipment.offhandUsable, isTrue);
      expect(equipment.at(1)?.relicId, 'split_counterweight');

      final rules = RelicRules.from(equipment);
      final def = ContentPack.current.relic('split_counterweight')!;
      expect(rules.maxHpPenalty, closeTo(def.params.dbl('maxHpPenalty'), 1e-9));

      const base = StatBlock(maxHp: 1000.0);
      expect(equipment.apply(base).maxHp,
          closeTo(1000.0 * (1.0 - rules.maxHpPenalty), 1e-9));
    });

    test('несёт лишний аффикс и усиленные роллы', () {
      // Проверяется на настоящем ролле: правило живёт в фабрике, а не в тесте.
      var checked = 0;
      for (var seed = 0; seed < 400 && checked < 5; seed++) {
        final item = ItemFactory.roll(
          ilvl: 30,
          rng: Rng(seed),
          kind: GearKind.weapon,
        );
        if (!item.twoHanded) continue;
        checked++;
        expect(item.affixes.length + (item.triggerAffixId == null ? 0 : 1),
            (Tuning.affixSlotsByRarity[item.rarity] ?? 0) + 1);
      }
      expect(checked, greaterThan(0), reason: 'двуручники обязаны выпадать');
    });
  });

  group('правила реликтов', () {
    test('«Кожа отчаяния» режет HP, удваивает вампиризм и держит порог', () {
      final equipment = _gear([_relic('skin_of_despair')]);
      final rules = RelicRules.from(equipment);
      final def = ContentPack.current.relic('skin_of_despair')!;

      expect(rules.maxHpPenalty, closeTo(def.params.dbl('maxHpPenalty'), 1e-9));
      expect(rules.permanentLowLife, isTrue);
      expect(rules.leechMultiplier,
          closeTo(def.params.dbl('leechMultiplier'), 1e-9));

      // «Жажда» обязана считаться включённой на полном здоровье.
      final abilities =
          AbilityRuntime.fromIds(const ['thirst'], rules: rules);
      final hero = HeroState(const StatBlock(maxHp: 1000.0));
      expect(abilities.leechMultiplier(hero),
          greaterThan(def.params.dbl('leechMultiplier')));
    });

    test('«Венец одержимого» оставляет одну активку и бьёт по всей волне', () {
      final profile = HeroProfile(
        gear: _gear([_relic('crown_of_obsession')]),
        abilities: const ['cleave', 'rift', 'blade_echo', 'fortitude'],
      );

      final loadout = profile.loadout;
      expect(loadout.where((d) => d.isActive), hasLength(1));
      expect(loadout.where((d) => !d.isActive), hasLength(2));

      // Единственная активка задевает всех, хотя у «Рассекающего» targets = 1.
      final fight = _fight(
        rules: profile.relicRules,
        abilities: const ['cleave'],
      )..run(1.0);
      for (final enemy in fight.enemies) {
        expect(enemy.hp, lessThan(enemy.maxHp));
      }
    });

    test('«Оберег молчания» выключает активные способности', () {
      final profile = HeroProfile(
        gear: _gear([_relic('charm_of_silence')]),
        abilities: const ['cleave', 'rift', 'blade_echo', 'fortitude'],
      );
      expect(profile.loadout.every((d) => !d.isActive), isTrue);
      expect(profile.loadout, hasLength(2));
      expect(profile.relicRules.passivesPerSlot, 2);
    });

    // Живой прогон: «Венец должен запрещать выставить ещё умение, но это не
    // так». Правило соблюдала ОДНА симуляция — экран позволял поставить
    // четыре активки и показывал их рабочими, а вниз уходила одна. Три теста
    // ниже про то, что запрет виден там, где игрок принимает решение.
    test('«Венец»: экран называет причину и не даёт поставить вторую активку',
        () {
      final profile = PlayerProfile.newGame(seed: 7);
      final m = profile.roster.reserve.first;
      m.abilities
        ..clear()
        ..addAll(['cleave']);
      m.gear.tryEquip(_relic('crown_of_obsession'),
          base: Tuning.heroBase, depth: 30);
      expect(m.gear.relicRules.singleActive, isTrue,
          reason: 'иначе тест проверяет пустоту');

      final second = ContentPack.current.ability('rift')!;
      final reason = profile.abilityBlockedReason(m, second);
      expect(reason, isNotNull);
      expect(reason, contains('Венец'),
          reason: 'запрет обязан назвать того, кто его наложил');

      // Замена активки на другую активку — не «вторая», а та же самая.
      expect(
        profile.abilityBlockedReason(m, second, loadout: const []),
        isNull,
      );
      // Пассивке «Венец» не мешает.
      expect(
        profile.abilityBlockedReason(
            m, ContentPack.current.ability('fortitude')!),
        isNull,
      );
    });

    test('«Оберег молчания» реально даёт вдвое больше слотов', () {
      final profile = PlayerProfile.newGame(seed: 7);
      final m = profile.roster.reserve.first;
      final base = profile.abilitySlots;

      expect(profile.abilitySlotsFor(m), base);
      m.gear.tryEquip(_relic('charm_of_silence'),
          base: Tuning.heroBase, depth: 30);
      expect(profile.abilitySlotsFor(m), base * 2,
          reason: 'обещание «две пассивки в слот» разбиралось из контента, '
              'доезжало до правил и не читалось ни одной строкой');

      expect(profile.abilityRuleNote(m), contains('пассивные'));
      expect(
        profile.abilityBlockedReason(
            m, ContentPack.current.ability('cleave')!),
        isNotNull,
      );
    });

    test('снятый «Оберег» забирает лишние слоты обратно', () {
      final passives = [
        for (final d in ContentPack.current.abilities)
          if (!d.isActive) d.id,
      ].take(8).toList();
      expect(passives, hasLength(8), reason: 'иначе тест ничего не проверяет');

      final withCharm = HeroProfile(
        gear: _gear([_relic('charm_of_silence')]),
        abilities: passives,
      );
      expect(withCharm.loadout, hasLength(8));

      // Тот же набор без реликта обязан срезаться до базовых слотов, иначе
      // сборка молча переживала бы снятие оберега.
      final without = HeroProfile(gear: _gear([]), abilities: passives);
      expect(without.loadout, hasLength(Tuning.abilitySlots));
    });

    test('«Венец» и «Оберег» нельзя носить вместе', () {
      final equipment = _gear([_relic('crown_of_obsession')]);
      final left = equipment.tryEquip(
        _relic('charm_of_silence'),
        base: Tuning.heroBase,
        depth: 30,
      );

      expect(left, hasLength(1),
          reason: 'жёсткая пара: порядок надевания не должен решать');
      expect(equipment.at(8), isNull);
    });

    test('«Счётчик мгновений» отключает криты и ускоряет счётчики', () {
      final rules = RelicRules.from(_gear([_relic('counter_of_moments')]));
      expect(rules.critDisabled, isTrue);
      expect(rules.counterRate, greaterThan(1.0));

      // Криты не проходят даже при стопроцентном шансе.
      final crits = _fight(critChance: 1.0, count: 1)..run(10.0);
      final noCrits = _fight(rules: rules, critChance: 1.0, count: 1)
        ..run(10.0);
      expect(noCrits.damage, lessThan(crits.damage));

      // «Метроном» при этом срабатывает вдвое чаще.
      final plain = _fight(triggers: const ['metronome'], count: 1)..run(30.0);
      final fast =
          _fight(rules: rules, triggers: const ['metronome'], count: 1)
            ..run(30.0);
      final base = _fight(count: 1)..run(30.0);

      final plainBonus = plain.damage - base.damage;
      final fastBonus = fast.damage - base.damage;
      expect(fastBonus, greaterThan(plainBonus * 1.5));
    });

    test('«Печать тысячи глаз»: проклятие вечно и переходит на волны', () {
      final rules = RelicRules.from(_gear([_relic('seal_of_thousand_eyes')]));
      expect(rules.eternalCurse, isTrue);

      final fight = _fight(rules: rules, abilities: const ['fire_brand'])
        ..run(30.0);
      final def = ContentPack.current.ability('fire_brand')!;
      expect(fight.enemies.first.curseRemaining,
          greaterThan(def.params.dbl('duration')),
          reason: 'обычное клеймо давно бы спало');

      // Урон по непроклятым срезан. Без клейма проклятых нет вовсе — значит
      // штраф виден на всём уроне сразу.
      final penalised = _fight(rules: rules)..run(5.0);
      final plain = _fight()..run(5.0);
      expect(penalised.damage,
          closeTo(plain.damage * (1.0 - rules.uncursedPenalty), 1.0));
    });

    test('«Пепельный завет»: горение критует и копится, прямой огонь слабее',
        () {
      final rules = RelicRules.from(_gear([_relic('ash_covenant')]));
      final def = ContentPack.current.relic('ash_covenant')!;

      expect(rules.burnCanCrit, isTrue);
      expect(rules.burnMaxStacks, def.params.integer('maxStacks'));

      final enemy = EnemyInstance.spawn(_archetype, 30);
      for (var i = 0; i < 10; i++) {
        enemy.applyDot(10.0, 5.0, DamageType.fire,
            maxStacks: rules.burnMaxStacks);
      }
      expect(enemy.dotStacks, rules.burnMaxStacks,
          reason: 'потолок стаков обязан держать');
      expect(enemy.dotDamagePerSecond, 10.0 * rules.burnMaxStacks);

      // Прямой урон Огнём срезан, горение — нет.
      final plain = _fight(abilities: const ['fire_brand'], count: 1)
        ..run(0.5);
      final penalised =
          _fight(rules: rules, abilities: const ['fire_brand'], count: 1)
            ..run(0.5);
      expect(penalised.damage,
          closeTo(plain.damage * (1.0 - rules.directFirePenalty), 1.0));
    });
  });

  group('«Сапоги нисходящего» в спуске', () {
    test('волн меньше, золота нет, мелочь не подбирается', () {
      // Реликт нарочно сильнее любой находки: он не должен быть вытеснен
      // посреди замера, иначе правило перестанет действовать на полпути.
      final profile = HeroProfile(
        gear: _gear([_relic('boots_of_descent', ilvl: 400, maxHp: 1e6)]),
        powerMultiplier: 3.0,
      );
      final rules = profile.relicRules;
      expect(rules.goldEnabled, isFalse);
      expect(rules.minRarity, Rarity.rare);

      final driver = DescentDriver(profile: profile, seed: 42, floorCap: 8);
      final waves = <int>{};
      while (!driver.finished) {
        waves.add(driver.snapshot.waveCount);
        driver.tick();
      }
      expect(waves, contains(Tuning.wavesPerFloor - rules.waveReduction));
      expect(waves, isNot(contains(Tuning.wavesPerFloor)),
          reason: 'обычный этаж обязан стать короче');

      final result = driver.result;
      expect(result.gold, 0.0);

      final plain = DescentSimulator(
        profile: HeroProfile(powerMultiplier: 3.0),
        seed: 42,
      ).run(floorCap: 8);
      expect(result.itemsFound, lessThan(plain.itemsFound),
          reason: 'мелочь остаётся лежать');
    });
  });
}
