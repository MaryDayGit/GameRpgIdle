/// Механическая проверка того, что контент ВЛИЯЕТ на игру.
///
/// Проверять такое чтением бесполезно: и аффикс, и способность выглядят
/// рабочими ровно до тех пор, пока их кто-нибудь не прогонит. Этот проект уже
/// дважды находил обратное — «+% к урону с тегом», который никто не читал, и
/// обещание реликта, которое разбиралось из контента и не доезжало ни до
/// одной строки кода.
///
/// Метод один и тот же для всего: прогнать ДВА одинаковых боя, отличающихся
/// только проверяемой вещью, и сравнить отпечаток — нанесённый урон, остаток
/// HP героя, число трупов. Совпал отпечаток — вещь не делает ничего.
///
///     dart run tool/audit_cli.dart              # всё
///     dart run tool/audit_cli.dart --affixes
///     dart run tool/audit_cli.dart --abilities
///     dart run tool/audit_cli.dart --tags
library;

import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/relic_def.dart';
import 'package:rift/core/model/relic_effect.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/relics.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/sim/triggers.dart';

import 'content_io.dart';

void main(List<String> args) {
  loadContentFromDisk().apply();

  final all = args.isEmpty;
  if (all || args.contains('--affixes')) _auditAffixes();
  if (all || args.contains('--abilities')) _auditAbilities();
  if (all || args.contains('--tags')) _auditTags();
  if (all || args.contains('--relics')) _auditRelics();
  if (all || args.contains('--enemies')) _auditEnemies();
}

// --------------------------------------------------------------- бестиарий --

/// Каждая повадка моба обязана менять бой, а каждая стихия — иметь того, кто
/// ею бьёт.
///
/// Второе не менее важно первого: у героя пять сопротивлений, и если по одной
/// из стихий его никто не бьёт, то целая пятая часть его защиты не проверяется
/// ничем — а игрок за неё платит слотами и аффиксами. Ровно так было с
/// Молнией: сопротивление ей существовало, бить ею было некому.
void _auditEnemies() {
  _header('БЕСТИАРИЙ · повадки и стихии');

  final pack = ContentPack.current;
  final all = [...pack.enemies, ...pack.bosses];
  final dead = <String>[];

  // --- стихии ------------------------------------------------------------------
  print('Кто чем бьёт:');
  for (final type in DamageType.values) {
    final users = [for (final e in all) if (e.damageType == type) e.name];
    print('  ${type.ru.padRight(12)} ${users.length.toString().padLeft(2)}  '
        '${users.take(4).join(', ')}${users.length > 4 ? ', …' : ''}');
    if (users.isEmpty) {
      dead.add('${type.ru}: этой стихией не бьёт никто — '
          'сопротивление ей проверять нечем');
    }
  }

  // --- слабости ------------------------------------------------------------------
  final weak = [
    for (final e in all)
      if (e.resists.values.any((v) => v < 0.0)) e.name,
  ];
  print('');
  print('Со слабостью к стихии: ${weak.length} из ${all.length}');
  if (weak.isEmpty) {
    dead.add('ни у одного моба нет слабости — выбор стихии ничего не решает');
  }

  // --- повадки ---------------------------------------------------------------------
  print('');
  print('Повадки: меняет ли каждая бой');
  _row(['повадка', 'носителей', 'сдвиг / шум', 'стенд']);
  _rule(4);

  for (final trait in EnemyTrait.values) {
    final carriers = [for (final e in all) if (e.has(trait)) e.name];

    if (carriers.isEmpty) {
      _row([trait.name, '0', '—', 'носителей нет']);
      dead.add('повадка ${trait.name}: её нет ни у одного моба');
      continue;
    }

    // Стенд: та же пачка, но с повадкой и без неё. Сравнивать разных мобов
    // бессмысленно — у них разные HP и урон, и сдвиг был бы про них, а не
    // про повадку.
    final plain = _traitProbe(const []);
    final withTrait = _traitProbe([trait]);
    final noise = _traitProbe(const [], seedOffset: 100);

    final delta = plain.deltaVs(withTrait);
    final n = plain.deltaVs(noise);
    final works = delta > n * 2.0 && delta > 0.005;

    _row([
      trait.name,
      '${carriers.length}',
      '${(delta * 100).toStringAsFixed(1)} / ${(n * 100).toStringAsFixed(1)}',
      works ? carriers.first : 'НИЧЕГО',
    ]);
    if (!works) dead.add('повадка ${trait.name} не меняет бой');
  }

  print('');
  if (dead.isEmpty) {
    print('Все ${EnemyTrait.values.length} повадок работают, '
        'все ${DamageType.values.length} стихий представлены.');
  } else {
    print('ДЫРЫ (${dead.length}):');
    for (final d in dead) {
      print('  - $d');
    }
  }
  _verdict('ENEMIES', dead.length);
}

/// Бой против пачки с заданными повадками и без них.
///
/// Стенд подобран так, чтобы каждой повадке было что показать:
///
/// * **толстые враги** — иначе пачка гибнет раньше первого своего удара, и
///   всё, что происходит при получении урона (отражение, снятие маны,
///   вампиризм), не случается ни разу. Первая версия стенда именно так и
///   объявила мёртвыми шесть повадок из девяти;
/// * **двое хилых** — без трупов не проверить взрыв при смерти;
/// * **сопротивления у героя** — срезать нечего тому, у кого их нет;
/// * **бой длинный** — разгон и растущая броня видны не сразу.
_Print _traitProbe(List<EnemyTrait> traits, {int seedOffset = 0}) {
  EnemyArchetype archetype(double hp) => EnemyArchetype(
        id: 'trait_probe',
        name: 'Проба',
        hpMult: hp,
        dpsMult: 0.55,
        attackSpeed: 1.0,
        armorMult: 0.5,
        weight: 1.0,
        // Бьют огнём, а не физикой: сопротивления режут только стихийный
        // урон, и «срезание сопротивлений» на физической пачке неотличимо
        // от пустоты.
        damageType: DamageType.fire,
        traits: traits.toSet(),
      );

  // Герою есть что терять: сопротивления, мана и умеренный запас прочности.
  const stats = StatBlock(
    maxHp: 9000.0,
    maxMana: 100.0,
    manaRegen: 5.0,
    armor: 40.0,
    resistFire: 40.0,
    resistCold: 40.0,
    resistLightning: 40.0,
    resistVoid: 40.0,
    attackDamage: 120.0,
    spellPower: 120.0,
    attackSpeed: 1.0,
    critMulti: 1.5,
  );

  var damage = 0.0;
  var taken = 0.0;
  const seeds = 12;

  for (var s = 0; s < seeds; s++) {
    // Урон меряется по ЗАПАСУ ГЕРОЯ, а не по шине событий.
    //
    // Отражение и взрыв при смерти событий не порождают намеренно — цепочка
    // «отражение убило -> взрыв -> отражение…» была бы тем самым каскадом,
    // от которого стоят предохранители шины. Стенд, слушавший шину, обеих
    // повадок не видел и объявлял их мёртвыми.
    final bus = EventBus();
    final mods = CombatModifiers();
    final abilities = AbilityRuntime.fromIds(_casterLoadout,
        modifiers: mods, rules: RelicRules.none);
    final triggers =
        TriggerRuntime(bus: bus, abilities: abilities, mods: mods)
          ..configure(const []);

    final hero = HeroState(stats);
    final pack = [
      for (var i = 0; i < 6; i++)
        EnemyInstance.spawn(archetype(i < 2 ? 1.2 : 40.0), 40),
    ];
    final runner = WaveRunner(
      bus: bus,
      depth: 40,
      hero: hero,
      enemies: pack,
      rng: Rng(90210 + (s + seedOffset) * 7919),
      abilities: abilities,
      triggers: triggers,
      rules: RelicRules.none,
    );

    final ticks = (120.0 / Tuning.tickSeconds).round();
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }

    damage += pack.fold(0.0, (x, e) => x + (e.maxHp - e.hp));
    taken += stats.maxHp - hero.hp;
  }

  return _Print(damage / seeds, taken / seeds, 0, 0.0);
}


// -------------------------------------------------------------- реликты -----

/// Каждый реликт обязан МЕНЯТЬ ИСХОД, а не описание предмета.
///
/// Реликт — это правило, и правило без ветки в симуляции выглядит рабочим
/// ровно до тех пор, пока его никто не прогонит. Этот проект уже находил
/// такое дважды: «Оберег молчания» обещал две пассивки в слот и не давал их
/// нигде, «Венец одержимого» соблюдался симуляцией и игнорировался экраном.
///
/// Метод тот же: два одинаковых боя, отличающихся только надетым реликтом.
void _auditRelics() {
  _header('РЕЛИКТЫ · меняет ли правило исход');
  print('Каждый проверяется на стенде, где его правилу есть что делать:');
  print('спускным — спуск, боевым — бой, лечебным — смертельный бой.');
  print('');

  final pack = ContentPack.current;
  final dead = <String>[];

  _row(['реликт', 'слот', 'правило', 'сдвиг / шум', 'стенд']);
  _rule(5);

  for (final def in pack.relics) {
    final bench = _relicBench(def);
    final gear = Equipment()
      ..equipTo(_slotFor(def.kind), _relicItem(def));

    // «Парным кольцам» нечего удваивать на голом наёмнике: реликт сам по себе
    // без аффиксов, а амулет, который он выключает, вообще не надет. Правило
    // про слоты проверяется только на заполненных слотах.
    if (def.effect == RelicEffect.twinRings) {
      gear
        ..equipTo(_slotFor(GearKind.ring) + 1, _statItem(GearKind.ring))
        ..equipTo(_slotFor(GearKind.amulet), _statItem(GearKind.amulet));
    }

    final rules = RelicRules.from(gear);

    // Реликт может ЗАПРЕЩАТЬ способности: «Оберег молчания» отнимает все
    // активки, «Венец» оставляет одну. Фильтр живёт в профиле героя, и стенд
    // обязан спрашивать его же — иначе проверяется сборка, которой в игре
    // не бывает.
    final loadout = bench == null
        ? const <String>[]
        : [
            for (final d
                in HeroProfile(gear: gear, abilities: bench.abilities).loadout)
              d.id,
          ];

    if (bench == null) {
      // Правило спуска в бою не проверяется по определению: оно про этажи,
      // волны и добычу, а не про удары.
      _row([def.id, def.kind.name, def.effect.name, '— (спуск)', 'спуск']);
      final changed = _descentDiffers(gear);
      if (!changed) dead.add('${def.id} — не меняет спуск');
      continue;
    }

    final before = _probe(
      stats: bench.stats,
      abilities: bench.abilities,
      enemyDamage: bench.enemyDamage,
      seeds: bench.seeds,
      frail: bench.frail,
    );
    final noise = _probe(
      stats: bench.stats,
      abilities: bench.abilities,
      enemyDamage: bench.enemyDamage,
      seeds: bench.seeds,
      frail: bench.frail,
      seedOffset: 100,
    );
    final after = _probe(
      stats: bench.stats + _relicStats(gear),
      abilities: loadout,
      enemyDamage: bench.enemyDamage,
      seeds: bench.seeds,
      frail: bench.frail,
      rules: rules,
    );

    final delta = bench.lethal
        ? after.survivalDeltaVs(before)
        : after.deltaVs(before);
    final n = bench.lethal
        ? noise.survivalDeltaVs(before)
        : noise.deltaVs(before);
    final works = delta > n * 2.0 && delta > 0.005;

    _row([
      def.id,
      def.kind.name,
      def.effect.name,
      '${(delta * 100).toStringAsFixed(1)} / ${(n * 100).toStringAsFixed(1)}',
      works ? bench.what : 'НИЧЕГО (${bench.what})',
    ]);
    if (!works) dead.add('${def.id} (${def.effect.name}, ${bench.what})');
  }

  print('');
  if (dead.isEmpty) {
    print('Все ${pack.relics.length} реликтов меняют исход.');
  } else {
    print('НЕ ВИДНО (${dead.length} из ${pack.relics.length}):');
    for (final d in dead) {
      print('  - $d');
    }
  }
  _verdict('RELICS', dead.length);
}

/// Предмет-реликт для стенда: без аффиксов, чтобы менял только правило.
Item _relicItem(RelicDef def) => Item(
      kind: def.kind,
      ilvl: 60,
      rarity: Rarity.relic,
      affixes: const [],
      relicId: def.id,
      relicEffect: def.effect,
    );

/// Обычный предмет с заметными статами. Нужен правилам про слоты: удваивать
/// или выключать нечего, когда слоты пусты.
Item _statItem(GearKind kind) => Item(
      kind: kind,
      ilvl: 60,
      rarity: Rarity.rare,
      affixes: [
        AffixRoll(
          affixId: 'max_hp_flat',
          stat: StatKey.maxHp,
          percentile: 1.0,
          value: 400.0,
        ),
        AffixRoll(
          affixId: 'attack_damage_flat',
          stat: StatKey.attackDamage,
          percentile: 1.0,
          value: 60.0,
        ),
      ],
    );

/// Статы, которые реликт меняет ПОМИМО правил: штраф к HP, отмена брони,
/// удвоение колец. Без них «Стеклянный венец» проверялся бы вполсилы.
StatBlock _relicStats(Equipment gear) {
  final worn = gear.apply(_base);
  final bare = Equipment().apply(_base);
  return _deltaOf(worn, bare);
}

/// Меняет ли реликт сам СПУСК: глубину, волны, добычу, Эхо, время.
///
/// Сравниваются два спуска с одним сидом, отличающиеся только надетым
/// реликтом. Правило спуска в бою не проверяется по определению: оно про
/// этажи и добычу, а не про удары.
bool _descentDiffers(Equipment gear) {
  RunResult run(Equipment worn) => DescentSimulator(
        profile: HeroProfile(gear: worn, powerMultiplier: 8.0),
        seed: 4242,
      ).run(floorCap: 40);

  final plain = run(Equipment());
  final withRelic = run(gear);

  return plain.maxDepth != withRelic.maxDepth ||
      plain.echo != withRelic.echo ||
      (plain.gold - withRelic.gold).abs() > 0.5 ||
      plain.itemsFound != withRelic.itemsFound ||
      (plain.totalSeconds - withRelic.totalSeconds).abs() > 0.05;
}

/// Стенд для реликта: там, где его правилу есть что делать.
_Bench? _relicBench(RelicDef def) => switch (def.effect) {
      // Правила спуска: этажи, волны, добыча, старт.
      RelicEffect.recordRun ||
      RelicEffect.restless ||
      RelicEffect.bossbane ||
      RelicEffect.deepStart =>
        null,

      // Живучесть видна только там, где герой гибнет.
      RelicEffect.permanentLowLife ||
      RelicEffect.armorIntoResist ||
      RelicEffect.fragilePower ||
      RelicEffect.bloodPact ||
      RelicEffect.twoHandedInOneHand =>
        const _Bench('выживание', lethal: true, withLeech: true),

      // Правилам про способности нужны способности.
      RelicEffect.singleActive ||
      RelicEffect.passivesOnly ||
      RelicEffect.freeCasts ||
      RelicEffect.swiftCasts =>
        _Bench('четыре активки', abilities: _casterLoadout),

      // Горение и проклятие: нужен тот, кто их накладывает.
      // Горение должно быть основным уроном, иначе прибавка к нему тонет в
      // ударах оружия: автоатака приглушена, критов много, бой длинный.
      RelicEffect.burnCanCrit => const _Bench('горение почти без оружия',
          abilities: ['pyre'], crit: true, caster: true, seeds: 40),
      RelicEffect.eternalCurse =>
        _Bench('проклятие', abilities: [_firstCurse()]),

      // Счётчики считают удары — нужен бой подлиннее.
      RelicEffect.doubleCounters => const _Bench('автоатака с критами',
          crit: true, seeds: 40),

      // Прочее — обычный бой.
      _ => const _Bench('автоатака'),
    };

// ---------------------------------------------------------------- стенд -----

/// Бой, в котором видно и нападение, и защиту.
///
/// Герою обязательно должно ПРИЛЕТАТЬ: иначе лечение, шипы, порог низкого
/// здоровья и все сопротивления неотличимы от пустоты. И кто-то обязательно
/// должен умереть: без трупов нечего взрывать и некого добивать.
/// Мешок нарочно толстый: если волна выкашивается за десять секунд, то
/// «+6 % к скорости атаки» и «−5 % к перезарядке» упираются не в игру, а в
/// потолок нанесённого урона — оба плеча замера показывают один и тот же
/// суммарный HP пачки, и честная прибавка выглядит мёртвой.
const _dummy = EnemyArchetype(
  id: 'probe',
  name: 'Болванчик',
  hpMult: 40.0,
  dpsMult: 0.55,
  attackSpeed: 1.0,
  armorMult: 1.0,
  weight: 1.0,
);

/// Хилый: он для того, чтобы в бою появлялись трупы.
const _frail = EnemyArchetype(
  id: 'frail',
  name: 'Хилый',
  hpMult: 1.2,
  dpsMult: 0.55,
  attackSpeed: 1.0,
  armorMult: 1.0,
  weight: 1.0,
);

EnemyArchetype _elemental(DamageType type) => EnemyArchetype(
      id: 'probe_${type.name}',
      name: type.name,
      hpMult: 40.0,
      dpsMult: 0.55,
      attackSpeed: 1.0,
      armorMult: 1.0,
      weight: 1.0,
      damageType: type,
    );

const _base = StatBlock(
  maxHp: 26000.0,
  hpRegen: 0.0,
  // Мана — ПЛОСКИЙ бюджет по дизайну (StatKey.isManaBudget): она не растёт
  // от ilvl, и стенд обязан держать её на настоящей базе. Со щедрым запасом
  // в четыре тысячи «+25 к максимуму маны» неотличимо от пустоты — и аффикс
  // выглядел бы сломанным по вине стенда, а не игры.
  maxMana: 100.0,
  manaRegen: 5.0,
  armor: 40.0,
  attackDamage: 260.0,
  spellPower: 260.0,
  attackSpeed: 1.0,
  // Криты выключены НАМЕРЕННО: они единственный заметный источник случайности
  // в бою, и с ними шум стенда держится около трёх процентов — выше, чем
  // сигнал от честной прибавки к скорости атаки. Тем аффиксам, которым криты
  // нужны, стенд их возвращает отдельно.
  critChance: 0.0,
  critMulti: 1.5,
);

/// Отпечаток боя: три числа, которых достаточно, чтобы заметить любое
/// изменение — в уроне, в живучести или в скорости зачистки.
class _Print {
  const _Print(this.damage, this.taken, this.dead, this.survived);

  /// Урон, нанесённый герою... то есть врагам.
  final double damage;

  /// Урон, ПОЛУЧЕННЫЙ героем.
  ///
  /// Именно полученный, а не остаток HP: при запасе в двадцать шесть тысяч
  /// срез входящего урона впятеро выглядит как «97 % HP вместо 99 %», и любая
  /// защита кажется мёртвой. Броня и сопротивления обязаны мериться тем, на
  /// что они влияют.
  final double taken;

  final int dead;

  /// Сколько секунд герой продержался.
  ///
  /// Единственная честная мера живучести. Запас HP не срезает входящий урон
  /// и на «полученном уроне» выглядит нулём — а именно он решает, дойдёт ли
  /// наёмник до следующего этажа. Мерить защиту можно только там, где от неё
  /// зависит смерть.
  final double survived;

  static double _rel(double a, double b) {
    final scale = a.abs() > b.abs() ? a.abs() : b.abs();
    return scale < 1e-9 ? 0.0 : (a - b).abs() / scale;
  }

  /// Насколько заметно, долей от большего из двух плеч.
  double deltaVs(_Print o) {
    final d = _rel(damage, o.damage);
    final t = _rel(taken, o.taken);
    return d > t ? d : t;
  }

  double survivalDeltaVs(_Print o) => _rel(survived, o.survived);
}

/// Среднее по нескольким семенам.
///
/// Один бой с фиксированным семенём слеп к шансам: прибавка к шансу крита
/// может не перевернуть ни одного броска за тридцать секунд, и честный аффикс
/// выглядит мёртвым. Восьми прогонов хватает, чтобы отличить «не читается» от
/// «не повезло».
_Print _probe({
  StatBlock stats = _base,
  List<String> abilities = const [],
  List<DamageType> enemyDamage = const [DamageType.physical],
  double seconds = 90.0,
  int count = 5,
  int seeds = 12,
  int seedOffset = 0,
  int frail = 2,
  RelicRules rules = RelicRules.none,
}) {
  var damage = 0.0;
  var hp = 0.0;
  var dead = 0;
  var alive = 0.0;
  for (var s = 0; s < seeds; s++) {
    final one = _probeOnce(
      stats: stats,
      abilities: abilities,
      enemyDamage: enemyDamage,
      seconds: seconds,
      count: count,
      seed: 90210 + (s + seedOffset) * 7919,
      frail: frail,
      rules: rules,
    );
    damage += one.damage;
    hp += one.taken;
    dead += one.dead;
    alive += one.survived;
  }
  return _Print(damage / seeds, hp / seeds, dead, alive / seeds);
}

_Print _probeOnce({
  required StatBlock stats,
  required List<String> abilities,
  required List<DamageType> enemyDamage,
  required double seconds,
  required int count,
  required int seed,
  required int frail,
  required RelicRules rules,
}) {
  final bus = EventBus();
  var taken = 0.0;
  bus.subscribe(
      GameEventType.onDamageTaken, (ctx) => taken += ctx.amount, 'audit');

  final mods = CombatModifiers();
  final abilityRuntime =
      AbilityRuntime.fromIds(abilities, modifiers: mods, rules: rules);
  final triggers = TriggerRuntime(bus: bus, abilities: abilityRuntime, mods: mods)
    ..rules = rules
    ..configure(const []);

  // Пассивки и ауры отдают статы НЕ через боевой рантайм, а этой свёрткой —
  // ею же пользуется `HeroProfile.aggregate`. Стенд, кормивший героя сырым
  // блоком, объявлял мёртвыми все восемь аур и оба размена статов: они
  // работали ровно там, куда стенд не смотрел.
  final defs = [
    for (final id in abilities)
      if (ContentPack.current.ability(id) case final d?) d,
  ];
  final hero = HeroState(applyPassiveAbilities(stats, defs));
  // Первые двое — хилые, остальные толстые. Без трупов не проверить ни взрыв
  // трупа, ни добивание: на стенде из одних мешков они молчат и выглядят
  // сломанными. Без толстых бой кончается за десять секунд, и в потолок
  // упираются скорость атаки с перезарядкой. Нужны и те, и другие.
  final pack = <EnemyInstance>[
    for (var i = 0; i < count; i++)
      EnemyInstance.spawn(
        enemyDamage.length == 1 && enemyDamage.first == DamageType.physical
            ? (i < frail ? _frail : _dummy)
            : _elemental(enemyDamage[i % enemyDamage.length]),
        40,
      ),
  ];

  final runner = WaveRunner(
    bus: bus,
    depth: 40,
    hero: hero,
    enemies: pack,
    rng: Rng(seed),
    abilities: abilityRuntime,
    triggers: triggers,
    rules: rules,
  );

  final ticks = (seconds / Tuning.tickSeconds).round();
  var lived = 0;
  for (var i = 0; i < ticks && !runner.finished; i++) {
    runner.tick();
    if (hero.alive) lived = i + 1;
  }

  return _Print(
    pack.fold(0.0, (s, e) => s + (e.maxHp - e.hp)),
    taken,
    pack.where((e) => e.hp <= 0).length,
    lived * Tuning.tickSeconds,
  );
}

// --------------------------------------------------------------- аффиксы ----

void _auditAffixes() {
  _header('АФФИКСЫ · доезжает ли значение с предмета до боя');

  final pack = ContentPack.current;

  final dead = <String>[];
  print('Аффикс усилен в $_amplify раз, чтобы читаемость не тонула в шуме.');
  print('«в бою: да» — сдвиг вдвое перекрыл шум того же стенда.');
  print('');
  _row(['аффикс', 'стат', 'в статах', 'в бою', 'сдвиг / шум', 'на чём проверен']);
  _rule(6);

  for (final def in pack.statAffixes) {
    // Тэговые аффиксы проверяем по каждому тегу семейства отдельно: семейство
    // из пяти тегов — это пять разных обещаний, и достаточно одного
    // нечитаемого, чтобы половина сундука стала украшением.
    final tags = def.stat == StatKey.tagDamage
        ? (def.family.isEmpty ? <Tag?>[null] : def.family.cast<Tag?>())
        : <Tag?>[null];

    for (final tag in tags) {
      final label = tag == null ? def.id : '${def.id}:${tag.name}';
      final item = _itemWith(def.id, tag);
      if (item == null) {
        dead.add('$label — не удалось собрать предмет');
        continue;
      }

      // Сравниваем с ПУСТЫМ предметом того же вида, а не с голым героем:
      // у каждого вида снаряжения есть имплицит, и он попал бы в замер вместе
      // с аффиксом. Тогда замер меряет вещь, а вопрос был про аффикс.
      final blank = Item(
        kind: item.kind,
        ilvl: item.ilvl,
        rarity: item.rarity,
        affixes: const [],
      );
      final gear = Equipment()..equipTo(_slotFor(item.kind), item);
      final control = Equipment()..equipTo(_slotFor(item.kind), blank);
      final worn = HeroProfile(gear: gear, abilities: const []).aggregate();
      final bare = HeroProfile(gear: control, abilities: const []).aggregate();
      final reachedStats = _statsDiffer(worn, bare);

      // Сборка, на которой аффикс вообще может что-то значить.
      //
      // Стенд без способностей физичен: против него «+% к урону Огнём» мёртв
      // не потому, что сломан, а потому, что огня в бою нет. Проверять аффикс
      // на сборке, которой он не адресован, — способ выдумать поломку.
      final probe = _probeFor(def.stat, tag);
      if (probe == null) {
        _row([label, def.stat.name, reachedStats ? 'да' : 'НЕТ',
              '— (спуск)', '', 'читается в спуске']);
        if (!reachedStats) dead.add('$label — не доезжает до статов');
        continue;
      }

      final before = _probe(
        stats: probe.stats,
        abilities: probe.abilities,
        enemyDamage: probe.enemyDamage,
        seconds: probe.seconds,
        seeds: probe.seeds,
        frail: probe.frail,
      );

      // Порог шума: те же статы, другие семена. Бой стохастичен, и любое
      // изменение статов слегка сдвигает поток случайности — «не ноль» само
      // по себе ничего не доказывает. Ниже этого порога сдвиг неотличим от
      // невезения, а мы искали читаемость аффикса, а не удачу.
      final noiseProbe = _probe(
        stats: probe.stats,
        abilities: probe.abilities,
        enemyDamage: probe.enemyDamage,
        seconds: probe.seconds,
        seeds: probe.seeds,
        frail: probe.frail,
        seedOffset: 100,
      );
      final noise = probe.lethal
          ? noiseProbe.survivalDeltaVs(before)
          : noiseProbe.deltaVs(before);

      // Аффикс усилен: один ролл двадцатого уровня тонет в шуме даже когда
      // читается исправно. Вопрос стенда — «доезжает ли значение до боя», а
      // не «много ли даёт один предмет»; на второй отвечает баланс.
      final after = _probe(
        stats: probe.stats + _deltaOf(worn, bare).scaled(_amplify),
        abilities: probe.abilities,
        enemyDamage: probe.enemyDamage,
        seconds: probe.seconds,
        seeds: probe.seeds,
        frail: probe.frail,
      );

      final delta = probe.lethal
          ? after.survivalDeltaVs(before)
          : after.deltaVs(before);
      final reachedFight = delta > noise * 2.0 && delta > 0.005;

      _row([
        label,
        def.stat.name,
        reachedStats ? 'да' : 'НЕТ',
        reachedFight ? 'да' : 'НЕТ',
        '${(delta * 100).toStringAsFixed(1)} % / шум ${(noise * 100).toStringAsFixed(1)}',
        probe.what,
      ]);

      if (!reachedStats) dead.add('$label — не доезжает до статов');
      if (!reachedFight) dead.add('$label — не влияет на бой (${probe.what})');
    }
  }

  print('');
  if (dead.isEmpty) {
    print('Все аффиксы доезжают до боя.');
  } else {
    print('НЕ РАБОТАЮТ (${dead.length}):');
    for (final d in dead) {
      print('  - $d');
    }
  }
  _verdict('AFFIXES', dead.length);
}

/// Чем проверять аффикс. `null` — в бою не проверяется вовсе.
class _Bench {
  const _Bench(this.what, {
    this.abilities = const [],
    this.enemyDamage = const [DamageType.physical],
    this.caster = false,
    this.lethal = false,
    this.crit = false,
    this.full = false,
    this.withLeech = false,
    this.seeds = 12,
  });

  final String what;
  final List<String> abilities;
  final List<DamageType> enemyDamage;

  /// Длительность замера. Общая для всех стендов: разная длина сделала бы
  /// сдвиги несравнимыми между строками отчёта.
  double get seconds => 90.0;

  /// Стенд, где автоатака почти отключена.
  ///
  /// Иначе множитель на способность тонет: автоатака бьёт непрерывно и даёт
  /// львиную долю урона, и удвоение способности, дающей десятую часть, видно
  /// как пять процентов от целого. Мы проверяем, ЧИТАЕТСЯ ли множитель, и
  /// смотреть на него надо там, где он на виду.
  final bool caster;

  /// Стенд, на котором герой ГИБНЕТ. Только на нём видно защиту.
  final bool lethal;

  /// Криты включены: без них множителю крита нечего множить.
  final bool crit;

  /// Автоатака в полную силу — чтобы в бою появлялись трупы.
  final bool full;

  /// У героя есть вампиризм: множителю вампиризма нужно что множить.
  final bool withLeech;

  /// Сколько хилых в пачке. На смертельном стенде их не должно быть вовсе:
  /// герой выкашивает их первыми, входящий урон падает, и замер живучести
  /// начинает мерить скорость зачистки вместо живучести.
  int get frail => lethal ? 0 : 2;

  /// Сколько семян усреднять. Критовым стендам нужно больше: они и есть
  /// источник шума, который мы иначе примем за сигнал.
  final int seeds;

  StatBlock get stats {
    var out = _base;
    if (crit) out = out + const StatBlock(critChance: 0.25);
    if (withLeech) out = out + const StatBlock(leech: 0.05);
    if (full) out = out + const StatBlock(attackDamage: 240.0);
    if (caster) out = out + const StatBlock(attackDamage: -180.0);
    if (lethal) {
      // Запас урезан до полутора тысяч. С двадцатью шестью тысячами герой
      // доживает до конца любого замера и вся защита показывает ровный ноль;
      // с тремя сотнями он гибнет за шесть секунд, и разрешения не хватает
      // уже наоборот. Полторы тысячи дают около тридцати секунд — середину
      // окна, где видно и вверх, и вниз.
      //
      // Урезание идёт ПОСЛЕДНИМ: раньше оно стояло первым и возвращало блок,
      // не применив ни криты, ни вампиризм — и «удвоенный вампиризм» честно
      // удваивал ноль.
      out = out + const StatBlock(maxHp: -24500.0);
    }
    return out;
  }
}

/// Во сколько раз усиливается проверяемый аффикс.
const _amplify = 20.0;


/// Активки, которые упираются в бюджет маны и в перезарядку.
/// Четыре активки подряд — стенд для перезарядки и бюджета маны.
///
/// Отбирать по `manaCost > 0` нельзя: в контенте таких НЕТ ни одной, и фильтр
/// молча возвращал пустой список — стенд «четыре активки» шёл без единой
/// активки и объявлял мёртвым всё, что на них завязано.
List<String> get _casterLoadout => [
      for (final a in ContentPack.current.abilities)
        if (a.type == AbilityType.active && _dealsDamage(a)) a.id,
    ].take(4).toList();

_Bench? _probeFor(StatKey stat, Tag? tag) {
  switch (stat) {
    case StatKey.lootQuality:
    case StatKey.lootQuantity:
    case StatKey.goldFind:
      return null;

    // Сопротивление огню проверяется огнём. Против смешанной пачки оно
    // срезает четверть входящего и тонет в разрешении замера — «не работает»
    // означало бы «мы его не туда приложили».
    case StatKey.resistFire:
      return const _Bench('только огонь',
          enemyDamage: [DamageType.fire], lethal: true);
    case StatKey.resistCold:
      return const _Bench('только холод',
          enemyDamage: [DamageType.cold], lethal: true);
    case StatKey.resistLightning:
      return const _Bench('только молния',
          enemyDamage: [DamageType.lightning], lethal: true);
    case StatKey.resistVoid:
      return const _Bench('только пустота',
          enemyDamage: [DamageType.voidType], lethal: true);

    case StatKey.maxHp:
    case StatKey.maxHpPct:
    case StatKey.hpRegen:
    case StatKey.armor:
    case StatKey.armorPct:
    case StatKey.leech:
      return const _Bench('выживание под огнём', lethal: true);

    case StatKey.spellPower:
      return _Bench('чары', abilities: [_firstSpell()], caster: true);

    case StatKey.critChance:
      return const _Bench('автоатака, шанс крита', seeds: 40);
    case StatKey.critMulti:
      return const _Bench('автоатака с критами', crit: true, seeds: 40);

    case StatKey.cooldownReduction:
    case StatKey.maxMana:
    case StatKey.manaRegen:
      // Мана и перезарядка ограничивают только того, кто в них упёрся.
      // На автоатаке у обеих нет работы, и их «мёртвость» была бы выдумкой
      // стенда, а не свойством игры.
      return _Bench('четыре активки подряд', abilities: _casterLoadout);

    case StatKey.tagDamage:
      if (tag == null) return null;
      // «Аура» множит не урон, а силу ауры. Замедление от «Морозного покрова»
      // видно там же, где видна любая защита, — на смертельном стенде: чем
      // медленнее враги, тем дольше живёт герой.
      if (tag == Tag.aura) {
        return const _Bench('«Морозный покров», выживание',
            abilities: ['frost_shroud'], lethal: true);
      }
      final user = _firstDamagingWith(tag);
      if (user == null) return null;
      // Теги автоатаки меряем на обычном стенде: она их и носит, и глушить
      // её означало бы глушить сам предмет проверки.
      final autoTag = tag == Tag.physical || tag == Tag.attack ||
          tag == Tag.strike;
      return _Bench('«$user»', abilities: [user], caster: !autoTag);

    default:
      return const _Bench('автоатака');
  }
}

String _firstCurse() => ContentPack.current.abilities
    .firstWhere((a) => a.kind == AbilityKind.curse)
    .id;

String _firstSpell() => ContentPack.current.abilities
    .firstWhere((a) => a.isSpell && _dealsDamage(a))
    .id;

String? _firstDamagingWith(Tag tag) {
  for (final a in ContentPack.current.abilities) {
    if (a.tags.contains(tag) && _dealsDamage(a)) return a.id;
  }
  return null;
}

Item? _itemWith(String affixId, Tag? tag) {
  final def = ContentPack.current.statAffix(affixId);
  if (def == null || def.kinds.isEmpty) return null;
  final kind = def.kinds.first;
  return Item(
    kind: kind,
    ilvl: 60,
    rarity: Rarity.rare,
    affixes: [
      AffixRoll(
        affixId: def.id,
        stat: def.stat,
        percentile: 1.0,
        value: def.scales ? def.base * Curves.itemScale(60) : def.base,
        tag: tag,
      ),
    ],
  );
}

/// Номер СЛОТА, а не индекс в перечислении.
///
/// Колец два, поэтому номера расходятся начиная с амулета: в перечислении он
/// седьмой, в снаряжении — восьмой. По индексу перечисления амулет уезжал во
/// второе кольцо, и реликт амулета не надевался вовсе — аудит показывал
/// «ничего не делает» там, где предмет просто не был надет.
int _slotFor(GearKind kind) => Equipment.slotKinds.indexOf(kind);

bool _statsDiffer(StatBlock a, StatBlock b) =>
    _deltaOf(a, b) != const StatBlock();

StatBlock _deltaOf(StatBlock worn, StatBlock bare) => StatBlock(
      maxHp: worn.maxHp - bare.maxHp,
      hpRegen: worn.hpRegen - bare.hpRegen,
      maxMana: worn.maxMana - bare.maxMana,
      manaRegen: worn.manaRegen - bare.manaRegen,
      armor: worn.armor - bare.armor,
      resistFire: worn.resistFire - bare.resistFire,
      resistCold: worn.resistCold - bare.resistCold,
      resistLightning: worn.resistLightning - bare.resistLightning,
      resistVoid: worn.resistVoid - bare.resistVoid,
      attackDamage: worn.attackDamage - bare.attackDamage,
      spellPower: worn.spellPower - bare.spellPower,
      increasedDamage: worn.increasedDamage - bare.increasedDamage,
      increasedAttackSpeed:
          worn.increasedAttackSpeed - bare.increasedAttackSpeed,
      critChance: worn.critChance - bare.critChance,
      critMulti: worn.critMulti - bare.critMulti,
      cooldownReduction: worn.cooldownReduction - bare.cooldownReduction,
      leech: worn.leech - bare.leech,
      lootQuality: worn.lootQuality - bare.lootQuality,
      lootQuantity: worn.lootQuantity - bare.lootQuantity,
      goldFind: worn.goldFind - bare.goldFind,
      tagDamage: {
        for (final e in worn.tagDamage.entries)
          e.key: e.value - (bare.tagDamage[e.key] ?? 0.0),
      },
    );

// ------------------------------------------------------------- способности --

bool _dealsDamage(AbilityDef def) => switch (def.kind) {
      AbilityKind.directDamage ||
      AbilityKind.dot ||
      AbilityKind.chainDamage ||
      AbilityKind.execute ||
      AbilityKind.corpseExplosion ||
      AbilityKind.summonTotem ||
      AbilityKind.curse ||
      AbilityKind.critApplyDot ||
      AbilityKind.thorns ||
      AbilityKind.infusion =>
        true,
      _ => false,
    };

void _auditAbilities() {
  _header('СПОСОБНОСТИ · меняет ли она исход одинакового боя');
  print('Каждая проверяется на стенде, где ей есть что делать: лечению и');
  print('порогам здоровья нужен смертельный бой, повтору чар — чары рядом,');
  print('крит-эффектам — криты, взрыву трупа — трупы. Стенд без этого');
  print('объявляет мёртвым то, на что просто не смотрит.');
  print('');

  final pack = ContentPack.current;

  final dead = <String>[];
  _row(['способность', 'тип', 'механика', 'ось', 'сдвиг / шум', 'стенд']);
  _rule(6);

  for (final def in pack.abilities) {
    final bench = _benchFor(def);
    final companions = bench.abilities;

    final before = _probe(
      stats: bench.stats,
      abilities: companions,
      seconds: bench.seconds,
      seeds: bench.seeds,
      frail: bench.frail,
      enemyDamage: bench.enemyDamage,
    );
    final noiseProbe = _probe(
      stats: bench.stats,
      abilities: companions,
      seconds: bench.seconds,
      seeds: bench.seeds,
      frail: bench.frail,
      enemyDamage: bench.enemyDamage,
      seedOffset: 100,
    );
    final after = _probe(
      stats: bench.stats,
      abilities: [def.id, ...companions],
      seconds: bench.seconds,
      seeds: bench.seeds,
      frail: bench.frail,
      enemyDamage: bench.enemyDamage,
    );

    final noise = bench.lethal
        ? noiseProbe.survivalDeltaVs(before)
        : noiseProbe.deltaVs(before);
    final delta = bench.lethal
        ? after.survivalDeltaVs(before)
        : after.deltaVs(before);
    final works = delta > noise * 2.0 && delta > 0.005;

    _row([
      def.id,
      def.type.name,
      def.kind.name,
      def.isSpell ? 'чары' : 'оружие',
      '${(delta * 100).toStringAsFixed(1)} / ${(noise * 100).toStringAsFixed(1)}',
      works ? bench.what : 'НИЧЕГО (${bench.what})',
    ]);
    if (!works) dead.add('${def.id} (${def.kind.name}, ${bench.what})');
  }

  print('');
  if (dead.isEmpty) {
    print('Все ${pack.abilities.length} способностей меняют исход боя.');
  } else {
    print('НЕ ВИДНО НА СТЕНДЕ (${dead.length} из ${pack.abilities.length}):');
    for (final d in dead) {
      print('  - $d');
    }
  }
  _verdict('ABILITIES', dead.length);
}

/// Стенд для конкретной способности.
///
/// Способность проверяется не «вообще», а там, где у неё есть работа. Лечение
/// на бессмертном герое, повтор чар без чар и взрыв трупа без трупов дают
/// ровный ноль — и это свойство замера, а не игры.
_Bench _benchFor(AbilityDef def) {
  // Ауры, отдающие защитный стат, видны только когда герой гибнет.
  final auraStat = def.kind == AbilityKind.auraStat
      ? def.params.str('stat')
      : '';
  final defensiveAura = auraStat == 'leech' ||
      auraStat.startsWith('resist') ||
      auraStat == 'maxHp' ||
      auraStat == 'armor' ||
      auraStat == 'hpRegen';

  if (defensiveAura) {
    // Сопротивление огню проверяется огнём: против физической пачки оно
    // ровно ноль, и это про стенд, а не про ауру.
    final byElement = <String, DamageType>{
      'resistFire': DamageType.fire,
      'resistCold': DamageType.cold,
      'resistLightning': DamageType.lightning,
      'resistVoid': DamageType.voidType,
    }[auraStat];
    if (byElement != null) {
      return _Bench('выживание под ${byElement.ru.toLowerCase()}',
          enemyDamage: [byElement], lethal: true);
    }
    // Вампиризму нужно, чтобы было что умножать: у героя без вампиризма
    // «удвоенный вампиризм» — это по-прежнему ноль.
    return const _Bench('выживание', lethal: true, withLeech: true);
  }
  if (auraStat == 'cooldownReduction' ||
      auraStat == 'manaRegen' ||
      auraStat == 'maxMana') {
    // Перезарядка и мана ограничивают того, кто в них упёрся. Без активок
    // рядом ни та, ни другая не имеют работы.
    return _Bench('четыре активки', abilities: _casterLoadout);
  }

  switch (def.kind) {
    case AbilityKind.heal:
    case AbilityKind.lowLifeGuard:
    case AbilityKind.conditionalLeech:
      return const _Bench('выживание', lethal: true, withLeech: true);

    case AbilityKind.repeatSpell:
      // Повторять нечего, если чар в сборке нет.
      return _Bench('рядом чары', abilities: [_firstSpell()], caster: true);

    case AbilityKind.repeatAttack:
      return const _Bench('автоатака');

    case AbilityKind.critApplyDot:
      return const _Bench('с критами', crit: true, seeds: 40);

    case AbilityKind.corpseExplosion:
      // Взрывать нечего без трупов, а трупу мало умереть — он обязан быть
      // ПРОКЛЯТ. Значит стенду нужны трое сразу: проклятие в сборке, урон
      // на добивание и кто-то хилый, кого успеют добить.
      return _Bench('с проклятыми трупами',
          abilities: [_firstCurse()], full: true);

    default:
      return const _Bench('приглушённая автоатака', caster: true);
  }
}

// -------------------------------------------------------------------- теги --

void _auditTags() {
  _header('ТЕГИ · есть ли под каждый и способности, и снаряжение');

  final pack = ContentPack.current;

  final affixTags = <Tag>{
    for (final a in pack.statAffixes)
      if (a.stat == StatKey.tagDamage) ...a.family,
  };
  final treeTags = <Tag>{
    for (final node in pack.passiveTree.nodes)
      if (node.stat == StatKey.tagDamage && node.tag != null) node.tag!,
  };

  _row(['тег', 'ось', 'умений', 'с уроном', 'аффикс', 'древо']);
  _rule(6);

  final gaps = <String>[];
  for (final tag in Tag.values) {
    final abilities = [
      for (final a in pack.abilities)
        if (a.tags.contains(tag)) a
    ];
    final damaging = abilities.where(_dealsDamage).length;

    _row([
      tag.ru,
      _axisOf(tag),
      '${abilities.length}',
      '$damaging',
      affixTags.contains(tag) ? 'да' : 'НЕТ',
      treeTags.contains(tag) ? 'да' : 'НЕТ',
    ]);

    // «Аура» усиливает НЕ урон, а величину самой ауры: ауры урона не наносят
    // вовсе. Требовать от неё способностей с уроном — значит требовать того,
    // чего в ней по определению нет.
    final needsDamage = tag != Tag.aura;

    if (abilities.isEmpty ||
        (needsDamage && damaging == 0) ||
        !affixTags.contains(tag)) {
      _gapTags.add(tag);
    }
    if (abilities.isEmpty) gaps.add('${tag.ru}: нет ни одной способности');
    if (needsDamage && damaging == 0 && abilities.isNotEmpty) {
      gaps.add('${tag.ru}: есть способности, но ни одна не наносит урон — '
          'множитель «+% к урону» некому применить');
    }
    if (!affixTags.contains(tag)) {
      gaps.add('${tag.ru}: ни один аффикс не даёт множителя с этим тегом');
    }
  }

  print('');
  if (gaps.isEmpty) {
    print('Каждый тег закрыт и способностями, и снаряжением.');
  } else {
    print('ДЫРЫ (${gaps.length}):');
    for (final g in gaps) {
      print('  - $g');
    }
  }
  // Дыры по тегам перечисляются поимённо: «Аура» — известная и принятая,
  // остальные обязаны валить проверку. Список, а не счётчик, потому что
  // «дыр стало на одну больше» ничего не говорит о том, какая появилась.
  _verdict('TAGS', gaps.length,
      detail: [for (final tag in _gapTags) tag.name].join(','));
}

final _gapTags = <Tag>{};

/// Строка вердикта латиницей.
///
/// Русский текст выше читает человек, эту строку — тест. На Windows консоль
/// отдаёт вывод в кодировке системы, и проверка, ловившая русскую фразу,
/// падала на кракозябрах при полностью исправном аудите. Проверять надо то,
/// что не зависит от того, кто как настроил терминал.
void _verdict(String what, int failures, {String detail = ''}) {
  print('AUDIT-$what: ${failures == 0 ? "OK" : "FAIL $failures"}'
      '${detail.isEmpty ? "" : " [$detail]"}');
}

String _axisOf(Tag tag) {
  if (Tag.elements.contains(tag)) return 'стихия';
  if (Tag.forms.contains(tag)) return 'форма';
  if (tag == Tag.projectile || tag == Tag.area) return 'доставка';
  return 'механика';
}

// ------------------------------------------------------------------ печать --

void _header(String title) {
  print('');
  print('=' * 78);
  print(title);
  print('=' * 78);
}

final _widths = <int, int>{};

void _row(List<String> cells) {
  final buf = StringBuffer();
  for (var i = 0; i < cells.length; i++) {
    final w = _widths[i] ??= _defaultWidth(i, cells.length);
    buf.write(cells[i].padRight(w));
    if (i < cells.length - 1) buf.write(' ');
  }
  print(buf.toString().trimRight());
}

int _defaultWidth(int i, int total) => i == 0 ? 24 : 14;

void _rule(int cols) {
  final buf = StringBuffer();
  for (var i = 0; i < cols; i++) {
    buf.write('-' * (_widths[i] ?? _defaultWidth(i, cols)));
    if (i < cols - 1) buf.write(' ');
  }
  print(buf.toString());
}
