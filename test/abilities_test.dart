import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Способность, объявленная в контенте, но ничего не делающая в бою, — это
/// текст в JSON. Здесь каждый `kind` проверяется в лоб: тот же бой с
/// способностью и без неё обязан разойтись, и разойтись предсказуемо.

const _depth = 30;

/// Мешок с HP: нужен, чтобы волна не кончалась раньше, чем сработает
/// способность с перезарядкой в 14 секунд.
final _dummy = EnemyArchetype(
  id: 'dummy',
  name: 'Болванчик',
  hpMult: 90.0,
  dpsMult: 0.05,
  attackSpeed: 1.0,
  weight: 1.0,
);

/// Герой с предсказуемыми статами: без крита, если не попросили обратного.
///
/// Мана заведомо избыточна: эти тесты про то, ЧТО делает способность, а не
/// про то, хватает ли на неё бюджета. Бюджет проверяется в `mana_test.dart`.
/// Сила чар равна урону оружия намеренно: проверяется механика способности,
/// а не то, какая из двух осей сильнее. Без неё способности с тегом «Чары»
/// били бы ровно ноль — и тест сообщал бы об этом как о поломке механики.
StatBlock _stats({double critChance = 0.0, double leech = 0.0}) => StatBlock(
      maxHp: 100000.0,
      maxMana: 100000.0,
      armor: 25.0,
      attackDamage: 100.0,
      spellPower: 100.0,
      attackSpeed: 1.0,
      critChance: critChance,
      critMulti: 1.0,
      leech: leech,
    );

class _Fight {
  _Fight(this.runner, this.hero, this.enemies);

  final WaveRunner runner;
  final HeroState hero;
  final List<EnemyInstance> enemies;

  void run(double seconds) {
    final ticks = (seconds / Tuning.tickSeconds).round();
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
  }

  double get enemyDamageTaken =>
      enemies.fold(0.0, (sum, e) => sum + (e.maxHp - e.hp));
}

_Fight _fight(
  List<String> abilityIds, {
  int count = 3,
  StatBlock? stats,
  EventBus? bus,
  int seed = 1234,
}) {
  final hero = HeroState(stats ?? _stats());
  final enemies = [
    for (var i = 0; i < count; i++) EnemyInstance.spawn(_dummy, _depth),
  ];
  final runner = WaveRunner(
    bus: bus ?? EventBus(),
    depth: _depth,
    hero: hero,
    enemies: enemies,
    rng: Rng(seed),
    abilities: AbilityRuntime.fromIds(abilityIds),
  );
  return _Fight(runner, hero, enemies);
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('активные', () {
    test('Рассекающий удар добавляет урон и бьёт по одной цели', () {
      final plain = _fight(const [])..run(10.0);
      final cleave = _fight(const ['cleave'])..run(10.0);

      expect(cleave.enemyDamageTaken, greaterThan(plain.enemyDamageTaken));

      // targets = 1: способность не должна задевать соседей. Урон по второму
      // мобу возможен только от автоатак, а они бьют первого живого.
      expect(cleave.enemies[1].hp, cleave.enemies[1].maxHp);
    });

    test('Разлом бьёт по всей волне', () {
      final rift = _fight(const ['rift'])..run(10.0);
      for (final enemy in rift.enemies.skip(1)) {
        expect(enemy.hp, lessThan(enemy.maxHp),
            reason: 'targets = 99 обязан задеть всех');
      }
    });

    test('Огненное клеймо проклинает, и проклятый получает больше', () {
      final brand = _fight(const ['fire_brand'])..run(8.0);
      expect(brand.enemies.first.cursed, isTrue);
      expect(brand.enemies.first.curseIncrease, greaterThan(0.0));

      // Тот же бой без клейма наносит меньше — и это не только урон самой
      // способности: проклятие поднимает и автоатаки.
      final plain = _fight(const [])..run(8.0);
      expect(brand.enemyDamageTaken, greaterThan(plain.enemyDamageTaken * 1.2));
    });

    test('Кровопуск вешает дот, и дот тикает сам', () {
      final fight = _fight(const ['bloodletting'])..run(0.5);
      final target = fight.enemies.first;
      expect(target.dotRemaining, greaterThan(0.0));

      final before = target.hp;
      final dotDps = target.dotDps;
      fight.run(1.0);
      expect(target.hp, lessThan(before - dotDps * 0.5),
          reason: 'дот обязан наносить урон помимо автоатак');
    });

    test('Тотем ярости разгоняет атаку и баф кончается', () {
      final totem = _fight(const ['totem_of_fury']);
      totem.run(0.2);

      // Баф 8 секунд: сравниваем нанесённое за первые 5 с и за 5 с после
      // истечения. Медленнее — значит баф спал.
      final start = totem.enemyDamageTaken;
      totem.run(5.0);
      final withBuff = totem.enemyDamageTaken - start;

      totem.run(5.0); // баф кончился на 8-й секунде
      final afterStart = totem.enemyDamageTaken;
      totem.run(5.0);
      final withoutBuff = totem.enemyDamageTaken - afterStart;

      expect(withBuff, greaterThan(withoutBuff));
    });

    test('Морозный шип бьёт больнее по замедленным', () {
      final plain = _fight(const ['frost_spike'])..run(6.0);
      final withAura = _fight(const ['frost_spike', 'frost_shroud'])..run(6.0);

      // Аура замедляет, шип получает бонус. Замедление само по себе урона
      // не добавляет — оно режет скорость атаки мобов, а не их защиту.
      expect(withAura.enemyDamageTaken, greaterThan(plain.enemyDamageTaken));
    });

    test('перезарядка не обнуляется между волнами', () {
      final hero = HeroState(_stats());
      final abilities = AbilityRuntime.fromIds(const ['totem_of_fury']);
      final bus = EventBus();

      List<EnemyInstance> pack() =>
          [for (var i = 0; i < 2; i++) EnemyInstance.spawn(_dummy, _depth)];

      final first = WaveRunner(
        bus: bus,
        depth: _depth,
        hero: hero,
        enemies: pack(),
        rng: Rng(1),
        abilities: abilities,
      );
      for (var i = 0; i < 20; i++) {
        first.tick(); // 2 секунды: тотем скастовался, кулдаун 14 с
      }

      final second = WaveRunner(
        bus: bus,
        depth: _depth,
        hero: hero,
        enemies: pack(),
        rng: Rng(1),
        abilities: abilities,
      );
      second.tick();

      expect(abilities.buffAttackSpeed, greaterThan(0.0),
          reason: 'баф ещё держится');

      // Прокручиваем до истечения бафа: если бы кулдаун обнулился со сменой
      // волны, тотем перекастовался бы и баф не спал бы никогда.
      for (var i = 0; i < 100; i++) {
        second.tick();
      }
      expect(abilities.buffAttackSpeed, 0.0);
    });
  });

  group('пассивные', () {
    test('Эхо клинка добавляет удары, не трогая кулдауны', () {
      // Шанс 20 %: на десятке ударов ноль срабатываний — это каждый девятый
      // сид. Меряем на длинном бою, иначе тест зелёный через раз.
      final plain = _fight(const [])..run(60.0);
      final echo = _fight(const ['blade_echo'])..run(60.0);

      expect(echo.enemyDamageTaken, greaterThan(plain.enemyDamageTaken));
      final def = ContentPack.current.ability('blade_echo')!;
      final ratio = echo.enemyDamageTaken / plain.enemyDamageTaken;
      expect(ratio, closeTo(1.0 + def.params.dbl('chance'), 0.15),
          reason: 'прибавка обязана сойтись с объявленным шансом');
    });

    test('Ледяной покров замедляет атакующих', () {
      final plain = _fight(const [], count: 1)..run(10.0);
      final shroud = _fight(const ['frost_shroud'], count: 1)..run(10.0);

      expect(shroud.enemies.first.slowed, isTrue);
      expect(shroud.runner.outcome.damageTaken,
          lessThan(plain.runner.outcome.damageTaken));
    });

    test('Стойкость меняет статы билда, а не правила боя', () {
      final bare = HeroProfile(abilities: const []).aggregate();
      final tough = HeroProfile(abilities: const ['fortitude']).aggregate();

      final def = ContentPack.current.ability('fortitude')!;
      expect(tough.armor,
          closeTo(bare.armor * (1.0 + def.params.dbl('armorPct')), 1e-9));
      expect(tough.increasedAttackSpeed,
          closeTo(bare.increasedAttackSpeed + def.params.dbl('attackSpeedPct'),
              1e-9));
    });

    test('Жажда удваивает вампиризм ниже порога', () {
      final def = ContentPack.current.ability('thirst')!;
      final abilities = AbilityRuntime.fromIds(const ['thirst']);

      final hero = HeroState(_stats(leech: 0.05));
      expect(abilities.leechMultiplier(hero), 1.0);

      hero.hp = hero.stats.maxHp * (def.params.dbl('threshold') - 0.01);
      expect(abilities.leechMultiplier(hero),
          closeTo(def.params.dbl('leechMultiplier'), 1e-9));
    });

    test('Пепелище вешает горение с крита', () {
      final fight = _fight(
        const ['ashfield'],
        stats: _stats(critChance: 1.0),
        count: 1,
      )..run(2.0);

      expect(fight.enemies.first.dotRemaining, greaterThan(0.0));
      expect(fight.enemies.first.dotType, DamageType.fire);
    });

    test('Печать бездны взрывает только проклятых', () {
      // Без проклятия взрыва быть не должно.
      final noCurse = _fight(const ['abyss_seal'], count: 2);
      noCurse.enemies.first.hp = 1.0;
      noCurse.run(1.0);
      expect(noCurse.enemies[1].hp, noCurse.enemies[1].maxHp);

      final cursed = _fight(const ['abyss_seal', 'fire_brand'], count: 2);
      cursed.run(0.2); // клеймо повесило проклятие на первого
      expect(cursed.enemies.first.cursed, isTrue);
      cursed.enemies.first.hp = 1.0;
      cursed.run(1.0);
      expect(cursed.enemies[1].hp, lessThan(cursed.enemies[1].maxHp));
    });
  });

  group('предохранители', () {
    test('доты не порождают событий', () {
      // Правило из `docs/02-TECH.md` §2.3: иначе горение, наложенное критом,
      // замыкает шину саму на себя.
      final bus = EventBus();
      var hits = 0;
      bus.subscribe(GameEventType.onHit, (_) => hits++, 'счётчик');

      final withDot = _fight(const ['bloodletting'], bus: bus, count: 1);
      withDot.run(6.0);
      final withDotHits = hits;

      hits = 0;
      final plainBus = EventBus()
        ..subscribe(GameEventType.onHit, (_) => hits++, 'счётчик');
      final plain = _fight(const [], bus: plainBus, count: 1)..run(6.0);

      // Урона от дота больше, а событий onHit — столько же: они приходят
      // только от автоатак и каста.
      expect(withDot.enemyDamageTaken, greaterThan(plain.enemyDamageTaken));
      expect(withDotHits, lessThanOrEqualTo(hits + 2),
          reason: 'лишние onHit могут прийти только от каста, не от тиков дота');
    });

    test('одноимённые эффекты обновляются, а не складываются', () {
      final enemy = EnemyInstance.spawn(_dummy, _depth);
      enemy.applyDot(10.0, 5.0, DamageType.fire);
      enemy.applyDot(10.0, 5.0, DamageType.fire);
      expect(enemy.dotDps, 10.0, reason: 'два источника горения — одно горение');

      enemy.applyDot(25.0, 1.0, DamageType.fire);
      expect(enemy.dotDps, 25.0, reason: 'сильнейший источник вытесняет слабый');
      expect(enemy.dotRemaining, 5.0, reason: 'длительность берётся большая');
    });

    test('сокращение перезарядки не доводит её до нуля', () {
      final fast = HeroState(StatBlock(
        maxHp: 100000.0,
        maxMana: 100000.0,
        armor: 25.0,
        attackDamage: 100.0,
        attackSpeed: 1.0,
        cooldownReduction: 5.0, // абсурдное значение — предохранитель обязан
      ));
      final abilities = AbilityRuntime.fromIds(const ['cleave']);
      final enemies = [EnemyInstance.spawn(_dummy, _depth)];
      final runner = WaveRunner(
        bus: EventBus(),
        depth: _depth,
        hero: fast,
        enemies: enemies,
        rng: Rng(5),
        abilities: abilities,
      );

      final normal = _fight(const ['cleave'], count: 1)..run(10.0);
      for (var i = 0; i < 100; i++) {
        runner.tick();
      }

      final boosted = enemies.first.maxHp - enemies.first.hp;
      expect(boosted, greaterThan(normal.enemyDamageTaken));
      expect(boosted, lessThan(normal.enemyDamageTaken * 12),
          reason: 'без пола перезарядки каст шёл бы каждый тик');
    });
  });
}
