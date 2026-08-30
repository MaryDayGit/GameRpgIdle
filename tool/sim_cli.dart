import 'dart:math' as math;

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';

import 'package:rift/core/model/build_power.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/passive_tree.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/rng.dart';

import 'content_io.dart';

/// Балансировщик. Гоняет симуляцию headless, без Flutter.
///
/// Баланс экспоненциальной игры вслепую не настраивается: `itemGrowth` входит
/// в формулу стены в квадрате, и ошибка в 2 % меняет длину рана вдвое
/// (`docs/01-ANALYSIS.md` §1). Поэтому инструмент пишется в первую неделю,
/// а не в последнюю.
void main(List<String> args) {
  final opts = _Options.parse(args);

  // Балансировщик обязан мерить ТОТ баланс, который попадёт в игру. Значения
  // по умолчанию в коде существуют только для тестов формул; настраивать
  // по ним — значит настраивать не ту игру (`docs/02-TECH.md` §1).
  loadContentFromDisk().apply();

  switch (opts.mode) {
    case 'curve':
      _printCurves();
    case 'wall':
      _measureWall(opts);
    case 'meta':
      _runMeta(opts);
    case 'campaign':
      _runCampaign(opts);
    case 'builds':
      _compareBuilds(opts);
    case 'tree':
      _measureTree(opts);
    case 'hp':
      _measureHp(opts);
    case 'power':
      _measurePower(opts);
    case 'forks':
      _compareForks(opts);
    case 'forks-vs':
      _compareForkPlay(opts);
    case 'runs':
      _runDistribution(opts);
    default:
      _printUsage();
  }
}

// ---------------------------------------------------------------------------
// Режим: кривые
// ---------------------------------------------------------------------------

void _printCurves() {
  _header('КРИВЫЕ ПРОГРЕССИИ');

  print('tau (длина мягкого разгона)   : ${Curves.tau.toStringAsFixed(1)} этажей');
  print('Рост HP моба                  : ${Curves.mobHpGrowth}');
  print('Рост урона моба               : ${Curves.mobDpsGrowth}');
  print('Рост силы предмета (g)        : ${Curves.itemGrowth.toStringAsFixed(6)}');
  print('  -> удлинение за удвоение    : '
      '${Curves.runExtensionPerDoubling.toStringAsFixed(2)} этажей '
      '(= ln4 / ln(a*b), задаётся только кривой мобов)');
  print('Рост времени этажа            : ${Curves.floorTimeGrowth.toStringAsFixed(6)}');
  print('  -> замедление за 40 этажей  : x${Curves.slowdownOver(40).toStringAsFixed(1)}');
  print('');
  print('Два неравенства, на которых стоит прогрессия:');
  print('  добыча двигает прогресс (g > sqrt(a*b)) : '
      '${Curves.lootLoopGain > 1.0 ? "ДА" : "НЕТ — вперёд тянут только деревья"}'
      '  множитель ${Curves.lootLoopGain.toStringAsFixed(3)}');
  print('  спуск обрывает смерть   (g < b)         : '
      '${Curves.deathEndsRuns ? "ДА" : "НЕТ — спуск упрётся в таймаут, прести́ж сломан"}');

  print('');
  _row(['d', 'd_eff', 'HP моба', 'DPS моба', 'itemScale', 'Эхо']);
  _rule(6);
  for (final d in [1, 5, 10, 20, 30, 40, 50, 60, 80, 100, 125, 150, 200]) {
    _row([
      '$d',
      Curves.dEff(d).toStringAsFixed(1),
      _sci(Curves.mobHp(d)),
      _sci(Curves.mobDps(d)),
      _sci(Curves.itemScale(d)),
      _sci(Curves.echo(d).toDouble()),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Режим: распределение глубины смерти
// ---------------------------------------------------------------------------

void _runDistribution(_Options o) {
  _header('РАСПРЕДЕЛЕНИЕ ГЛУБИНЫ · ${o.runs} ранов, Клеймо ${o.brand}');

  final depths = <int>[];
  final times = <double>[];
  final endings = <RunEnding, int>{};
  var anomalies = 0;
  RunResult? sample;

  final sw = Stopwatch()..start();
  for (var i = 0; i < o.runs; i++) {
    final profile = HeroProfile(powerMultiplier: o.power);
    final result = DescentSimulator(
      profile: profile,
      seed: o.seed + i,
      brandRank: o.brand,
    ).run(floorCap: o.floorCap, recordFloors: i == 0);

    depths.add(result.maxDepth);
    times.add(result.totalSeconds);
    endings.update(result.ending, (v) => v + 1, ifAbsent: () => 1);
    anomalies += result.anomalies;
    sample ??= result;
  }
  sw.stop();

  depths.sort();
  times.sort();

  print('Глубина    p10 ${_p(depths, 0.10)}  медиана ${_p(depths, 0.50)}  '
      'p90 ${_p(depths, 0.90)}  макс ${depths.last}');
  print('Время рана медиана ${_dur(_pd(times, 0.50))}  '
      'p90 ${_dur(_pd(times, 0.90))}');
  print('Эхо за медианный ран: ${Curves.echo(_p(depths, 0.50), brandRank: o.brand)}');
  print('Исходы: ${endings.entries.map((e) => "${e.key.name} ${e.value}").join(", ")}');

  // Где именно обрывается ран. Если почти всё приходится на боссов, значит
  // кривая обычных этажей ни на что не влияет и вся балансировка §2.2 — впустую.
  var onBoss = 0;
  var onBigBoss = 0;
  for (final d in depths) {
    final deathFloor = d + 1;
    if (deathFloor % 10 == 0) {
      onBigBoss++;
    } else if (deathFloor % 5 == 0) {
      onBoss++;
    }
  }
  final regular = depths.length - onBoss - onBigBoss;
  print('Этаж смерти: большой босс ${_pct(onBigBoss, depths.length)}  '
      'босс ${_pct(onBoss, depths.length)}  '
      'обычный ${_pct(regular, depths.length)}');
  print('Аномалии шины событий: $anomalies');
  print('Время расчёта: ${sw.elapsedMilliseconds} мс на ${o.runs} ранов');

  final s = sample!;
  print('');
  _header('ПРОФИЛЬ ЭТАЖЕЙ (ран №1)');
  _row(['этаж', 'сек', 'урон получ.', 'предметов']);
  _rule(4);
  final step = s.floors.length <= 40 ? 1 : 5;
  for (final f in s.floors) {
    if (f.depth % step != 0 && f.depth != s.floors.last.depth) continue;
    _row([
      '${f.depth}',
      f.seconds.toStringAsFixed(1),
      f.damageTaken.toStringAsFixed(0),
      '${f.itemsFound}',
    ]);
  }
}

// ---------------------------------------------------------------------------
// Режим: сравнение политик развилки
// ---------------------------------------------------------------------------

void _compareForks(_Options o) {
  _header('ПОЛИТИКИ РАЗВИЛКИ · ${o.runs} ранов на политику');
  print('Политика — это то, что выбирает наёмник вместо отсутствующего игрока.');
  print('Если строки сходятся, выбор пути не значит ничего, и развилку можно');
  print('не показывать вовсе.');
  print('');

  // Найденное — не то же самое, что принесённое: рюкзак ограничен, и всё
  // сверх него распыляется в золото. Политика, которая «про добычу», обязана
  // выигрывать в рюкзаке и золоте, а не в числе поднятых с пола предметов.
  // Рюкзак всегда полон, поэтому «сколько принёс» ничего не различает.
  // Различает КАЧЕСТВО принесённого: уровень предметов и доля редких.
  _row(['политика', 'медиана', 'Эхо', 'ilvl рюкзака', 'редких+', 'осколки',
    'золото']);
  _rule(7);

  for (final policy in ForkPolicy.values) {
    final depths = <int>[];
    var echo = 0.0;
    var haulIlvl = 0.0;
    var haulItems = 0;
    var rares = 0;
    var shards = 0;
    var gold = 0.0;

    for (var i = 0; i < o.runs; i++) {
      final r = DescentSimulator(
        profile: HeroProfile(powerMultiplier: o.power),
        seed: o.seed + i,
        brandRank: o.brand,
        forkPolicy: policy,
      ).run(floorCap: o.floorCap, recordFloors: false);

      depths.add(r.maxDepth);
      echo += r.echo;
      for (final item in r.haul.items) {
        haulIlvl += item.ilvl;
        haulItems++;
        if (item.rarity.index >= Rarity.rare.index) rares++;
      }
      shards += r.haul.shards.length;
      gold += r.gold;
    }
    depths.sort();

    _row([
      policy.ru,
      '${_p(depths, 0.50)}',
      (echo / o.runs).toStringAsFixed(0),
      haulItems == 0 ? '—' : (haulIlvl / haulItems).toStringAsFixed(1),
      (rares / o.runs).toStringAsFixed(1),
      (shards / o.runs).toStringAsFixed(1),
      _sci(gold / o.runs),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Режим: сравнение билдов
// ---------------------------------------------------------------------------

/// Архетипы билдов. Это не баланс, а сценарии замера: набор способностей,
/// который игрок реально соберёт, если пойдёт по одному тегу.
const _builds = <String, List<String>>{
  'Стартовый': ['cleave', 'blade_echo'],
  // --- ось Атак: растёт от урона оружия -------------------------------------
  'Удар': ['cleave', 'blade_echo', 'fortitude', 'totem_of_fury'],
  'Кровь': ['bloodletting', 'thirst', 'cleave', 'blade_echo'],
  'Добивание': ['coup_de_grace', 'cleave', 'butcher', 'blade_echo'],
  'Танк': ['fortitude', 'frost_shroud', 'thirst', 'cleave'],
  'Живучесть': ['field_dressing', 'spiked_guard', 'last_stand', 'cleave'],
  // --- пропитка: оружейная сборка, перешедшая на стихию ---------------------
  'Клинок в огне': ['ember_infusion', 'flame_lash', 'blade_echo', 'ashfield'],
  'Клинок во льду': ['rime_infusion', 'cleave', 'frost_bite', 'blade_echo'],
  'Клинок в грозе': ['storm_infusion', 'cleave', 'blade_echo', 'butcher'],
  // --- ось Чар: растёт от силы чар ------------------------------------------
  'Огонь': ['ember_burst', 'pyre', 'fire_brand', 'ashfield'],
  'Холод': ['frost_spike', 'glacier_shard', 'frost_shroud', 'hoarfrost'],
  'Молния': ['spark_bolt', 'arc_lash', 'conduction', 'overcharge'],
  'Пустота': ['rift', 'void_lance', 'hex_of_frailty', 'abyss_seal'],
  'Яд': ['venom', 'hex_of_frailty', 'abyss_seal', 'void_lance'],
  'Цепь': ['frost_chain_bolt', 'arc_lash', 'frost_shroud', 'spark_bolt'],
  'Тотемы': ['cinder_totem', 'thunder_totem', 'winter_totem', 'null_totem'],
  'Доты': ['pyre', 'static_field', 'hoarfrost', 'venom'],
  // Ауры резервируют ману: сборка сильна статами, но кастует редко.
  'Ауры': ['war_cry', 'stone_stance', 'cleave', 'blade_echo'],
  'Три ауры': ['war_cry', 'stone_stance', 'blood_oath', 'cleave'],
  'Пустые слоты': [],
};

void _compareBuilds(_Options o) {
  _header('СРАВНЕНИЕ БИЛДОВ · ${o.runs} ранов на билд');
  print('Разные билды обязаны давать разные распределения глубины. Если все');
  print('строки сходятся — способности не влияют ни на что, и четыре слота');
  print('перестают быть выбором.');
  print('');

  _row(['билд', 'медиана', 'p10', 'p90', 'ран', 'смертью']);
  _rule(6);

  for (final entry in _builds.entries) {
    final depths = <int>[];
    var deaths = 0;
    var seconds = 0.0;

    for (var i = 0; i < o.runs; i++) {
      final r = DescentSimulator(
        profile: HeroProfile(
          abilities: entry.value,
          powerMultiplier: o.power,
        ),
        seed: o.seed + i,
        brandRank: o.brand,
      ).run(floorCap: o.floorCap, recordFloors: false);

      depths.add(r.maxDepth);
      seconds += r.totalSeconds;
      if (r.ending == RunEnding.death) deaths++;
    }
    depths.sort();

    _row([
      entry.key,
      '${_p(depths, 0.50)}',
      '${_p(depths, 0.10)}',
      '${_p(depths, 0.90)}',
      _dur(seconds / o.runs),
      _pct(deaths, o.runs),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Режим: откуда берётся сила билда
// ---------------------------------------------------------------------------

/// Разбирает силу билда по источникам.
///
/// Вопрос, на который до этого режима отвечать было нечем: сколько силы даёт
/// снаряжение, сколько деревья, сколько ранг наёмника. Без ответа любая
/// правка баланса — догадка о том, какой рычаг сильнее.
///
/// Разбирается ТОТ профиль, который получается настоящей игрой: сначала
/// прогоняется кампания, потом с итогового игрока по очереди снимаются
/// источники.
///
/// Считается двумя способами, и оба нужны:
///
///  * **вклад по очереди** — сколько добавляет источник, когда его включают
///    следующим. Сумма сходится с итогом, но зависит от порядка;
///  * **чего лишимся** — насколько просядет собранный билд, если убрать
///    один источник. Порядка нет, зато сумма НЕ сходится с итогом: источники
///    множатся друг на друга, и это видно по расхождению.
void _measurePower(_Options o) {
  _header('СИЛА БИЛДА ПО ИСТОЧНИКАМ · после ${o.metaRuns} ранов');

  final player = _playCampaign(o, runs: o.metaRuns, onStop: print);
  // Наёмник, которого игрок отправил бы СЛЕДУЮЩИМ: снаряжение возвращается
  // в сундук вместе с добычей, поэтому у живого наёмника его нет, пока он не
  // собран. Собираем тем же способом, что и отправка.
  final merc = player.roster.reserve.isNotEmpty
      ? player.roster.reserve.first
      : MercFactory.roll(Rng(1), idPrefix: 'power');
  merc.gear.equipFrom(
    player.stash,
    base: Tuning.heroBase,
    depth: player.maxDepthEver < 1 ? 1 : player.maxDepthEver,
  );

  // Глубина, на которой сравниваются билды: рекорд игрока. Броня и
  // сопротивления работают против урона ЭТОЙ глубины, и на первом этаже
  // разбор показал бы не ту картину.
  final depth = player.maxDepthEver < 10 ? 10 : player.maxDepthEver;

  print('Наёмник: ${merc.name}, ${merc.rank.forGender(merc.gender)}, '
      '${merc.trait.forGender(merc.gender)}');
  print('Рекорд глубины: ${player.maxDepthEver}, '
      'сравнение на этаже $depth');
  print('');

  // Профиль собирается вручную из тех же частей, что и в игре, чтобы каждую
  // можно было выключить.
  double power({
    bool gear = true,
    bool abilities = true,
    bool echo = true,
    bool passives = true,
    bool rank = true,
    bool trait = true,
  }) {
    final profile = HeroProfile(
      gear: gear ? merc.gear.copy() : Equipment(),
      abilities: abilities ? merc.abilities : const <String>[],
      tree: echo ? player.tree : null,
      passives: passives ? player.passives : null,
      powerMultiplier: rank ? merc.rank.statMultiplier : 1.0,
      traitStats: trait ? merc.trait.apply : null,
    );
    return BuildPower.of(profile.aggregate(), depth,
        loadout: profile.loadout);
  }

  final bare = power(
    gear: false,
    abilities: false,
    echo: false,
    passives: false,
    rank: false,
    trait: false,
  );
  final full = power();

  _row(['источник', 'вклад по очереди', 'доля', 'чего лишимся']);
  _rule(4);

  String pct(double value, double of) =>
      of <= 0 ? '—' : '${(value * 100 / of).toStringAsFixed(0)} %';

  // Вклад по очереди: включаем источники один за другим.
  var running = bare;
  final steps = <(String, double)>[];

  final withGear = power(
      abilities: false, echo: false, passives: false, rank: false, trait: false);
  steps.add(('Снаряжение', withGear - running));
  running = withGear;

  final withAbilities =
      power(echo: false, passives: false, rank: false, trait: false);
  steps.add(('Способности', withAbilities - running));
  running = withAbilities;

  final withEcho = power(passives: false, rank: false, trait: false);
  steps.add(('Древо Эха', withEcho - running));
  running = withEcho;

  final withPassives = power(rank: false, trait: false);
  steps.add(('Дерево пассивок', withPassives - running));
  running = withPassives;

  final withRank = power(trait: false);
  steps.add(('Ранг наёмника', withRank - running));
  running = withRank;

  steps.add(('Черта наёмника', full - running));

  // Чего лишимся: снимаем по одному из собранного билда.
  final losses = <String, double>{
    'Снаряжение': full - power(gear: false),
    'Способности': full - power(abilities: false),
    'Древо Эха': full - power(echo: false),
    'Дерево пассивок': full - power(passives: false),
    'Ранг наёмника': full - power(rank: false),
    'Черта наёмника': full - power(trait: false),
  };

  _row(['Голый герой', _sci(bare), pct(bare, full), '—']);
  for (final (name, gain) in steps) {
    _row([
      name,
      _sci(gain),
      pct(gain, full),
      _sci(losses[name] ?? 0.0),
    ]);
  }
  _rule(4);
  _row(['Итого', _sci(full), '100 %', '']);

  final lossSum = losses.values.fold(0.0, (a, b) => a + b);
  print('');
  print('Сумма «чего лишимся» = ${_sci(lossSum)} против итога ${_sci(full)}.');
  print('Расхождение — не ошибка: источники множатся друг на друга, и убрать');
  print('два по очереди дороже, чем каждый по отдельности.');
  print('');
  print('Что с этим делать: если один источник даёт больше половины силы,');
  print('остальные — украшение, и правки баланса в них ничего не изменят.');

  // Застава и Клеймо в силу билда не входят: они меняют не статы, а добычу
  // и правила. Показываем отдельной строкой, чтобы их не искали в таблице.
  print('');
  print('Вне таблицы: Застава (${_buildTotal(player.outpost)}/'
      '${Building.values.length * Building.maxLevel}) даёт добычу и удобство, '
      'а не статы;');
  print('Клеймо (ранг ${player.brandRank}) поднимает мобов, а не героя.');

  // --- Проверка симуляцией ---------------------------------------------------
  //
  // Формула силы билда считает только урон и живучесть по статам. Она не
  // видит ни того, что делает способность в бою, ни вампиризма, ни качества
  // добычи — поэтому «Способности −1 %» в таблице выше означает не «мешают»,
  // а «формула их не умеет». Единственный честный ответ здесь — прогнать
  // спуск и посмотреть на глубину.
  int medianDepth({List<String>? abilities, MercRank? rank}) {
    final depths = <int>[];
    for (var seed = 1; seed <= 24; seed++) {
      final profile = HeroProfile(
        gear: merc.gear.copy(),
        abilities: abilities ?? merc.abilities,
        tree: player.tree,
        passives: player.passives,
        powerMultiplier: (rank ?? merc.rank).statMultiplier,
        traitStats: merc.trait.apply,
      );
      depths.add(DescentSimulator(profile: profile, seed: seed)
          .run(floorCap: 400)
          .maxDepth);
    }
    depths.sort();
    return _p(depths, 0.50);
  }

  print('');
  _header('ПРОВЕРКА СИМУЛЯЦИЕЙ · медиана глубины на 24 сидах');
  print('Формула выше считает статы. Здесь считается то, что происходит.');
  print('');

  final asIs = medianDepth();
  _row(['вариант', 'глубина', 'разница']);
  _rule(3);
  _row(['как есть', '$asIs', '—']);

  final noAbilities = medianDepth(abilities: const []);
  _row(['без способностей', '$noAbilities', '${noAbilities - asIs}']);

  for (final rank in MercRank.values) {
    if (rank == merc.rank) continue;
    final d = medianDepth(rank: rank);
    _row(['ранг ${rank.ru}', '$d', '${d - asIs}']);
  }

  print('');
  print('Если «без способностей» отличается на пару этажей, четыре слота');
  print('решают меньше, чем один уровень Заставы, — и это повод не для');
  print('правки чисел, а для разговора о том, зачем слоты нужны.');
}

// ---------------------------------------------------------------------------
// Режим: как ведёт себя здоровье по ходу рана
// ---------------------------------------------------------------------------

/// Профиль здоровья: сколько наёмник теряет на каждом этаже и как глубоко
/// проседает.
///
/// Замечание с телефона звучало как «HP наёмника не реагирует». Ощущение
/// надо перевести в число: если на большинстве этажей минимум здоровья
/// близок к единице, полоска и правда стоит — и виновата не полоска, а
/// отдых, возвращающий больше, чем стоит этаж.
void _measureHp(_Options o) {
  _header('ПРОФИЛЬ ЗДОРОВЬЯ · сид ${o.seed}');
  print('Минимум за этаж — самое низкое здоровье в бою. Если он держится');
  print('около 100 %, полоска стоит на месте: этаж стоит меньше, чем');
  print('возвращает отдых между этажами.');
  print('');

  final result = DescentSimulator(
    profile: HeroProfile(powerMultiplier: o.power),
    seed: o.seed,
    brandRank: o.brand,
  ).run(floorCap: o.floorCap);

  _row(['этаж', 'минимум HP', 'урон за этаж', 'секунд']);
  _rule(4);

  // Печатается не каждый этаж: их бывает полторы сотни, и таблица на весь
  // экран отвечает хуже, чем десяток строк по ходу спуска.
  final floors = result.floors;
  final step = floors.length <= 20 ? 1 : (floors.length / 20).ceil();

  for (var i = 0; i < floors.length; i += step) {
    final f = floors[i];
    _row([
      '${f.depth}',
      '${(f.lowestHpFraction * 100).round()} %',
      f.damageTaken.toStringAsFixed(0),
      f.seconds.toStringAsFixed(1),
    ]);
  }

  // Последние пять этажей — целиком: смерть приходит именно там, и важно,
  // видно ли её приближение.
  if (floors.length > 5) {
    print('');
    print('Последние пять этажей:');
    for (final f in floors.skip(floors.length - 5)) {
      _row([
        '${f.depth}',
        '${(f.lowestHpFraction * 100).round()} %',
        f.damageTaken.toStringAsFixed(0),
        f.seconds.toStringAsFixed(1),
      ]);
    }
  }

  // Итог одной строкой: доля этажей, где здоровье вообще заметно двигалось.
  var moved = 0;
  for (final f in floors) {
    if (f.lowestHpFraction < 0.9) moved++;
  }
  print('');
  print('Этажей, где здоровье падало ниже 90 %: '
      '$moved из ${floors.length} '
      '(${floors.isEmpty ? 0 : (moved * 100 / floors.length).round()} %)');
  print('Исход: ${result.ending.name}, глубина ${result.maxDepth}');
}

// ---------------------------------------------------------------------------
// Режим: что даёт дерево пассивок
// ---------------------------------------------------------------------------

/// Сколько глубины приносит дерево, если вкладывать всё в один луч.
///
/// Замер существует ради одного вопроса, который живой прогон задал прямо:
/// «дерево слабо чувствуется». Ощущение надо перевести в число — и держать
/// его на глазах, как стену и распределение глубины.
/// Сборка, которой мерится луч.
///
/// Стихийные лучи состоят из теговых узлов, и физическому стартовому набору
/// они не дают НИЧЕГО. Померив «Пепел» стандартным лоадаутом, замер честно
/// показывал бы +18 против +33 у Клыка — и вывод «стихии слабее» был бы
/// артефактом замера, а не свойством игры.
///
/// Поэтому у каждого луча свой лоадаут: луч меряется тем игроком, который в
/// него и пойдёт.
const _clusterBuilds = <String, List<String>>{
  'ember': ['ember_burst', 'pyre', 'fire_brand', 'ashfield'],
  'frost': ['frost_spike', 'glacier_shard', 'hoarfrost', 'frost_shroud'],
  'storm': ['spark_bolt', 'arc_lash', 'static_field', 'overcharge'],
  'abyss': ['void_lance', 'rift', 'hex_of_frailty', 'venom'],
  'arcane': ['spark_bolt', 'ember_burst', 'frost_spike', 'void_lance'],
};

/// Та же стихия, но собранная на ПРОПИТКЕ: автоатака бьёт стихией, и теговые
/// узлы усиливают то, чем наносится львиная доля урона.
///
/// Две сборки на один луч печатаются рядом намеренно. Разница между ними —
/// это цена того, что способности вносят в урон мало: на чарах луч даёт
/// вдвое меньше, чем на пропитке, при одних и тех же узлах.
const _infusionBuilds = <String, List<String>>{
  'ember': ['ember_infusion', 'flame_lash', 'blade_echo', 'ashfield'],
  'frost': ['rime_infusion', 'cleave', 'frost_bite', 'blade_echo'],
  'storm': ['storm_infusion', 'cleave', 'blade_echo', 'butcher'],
  'abyss': ['void_infusion', 'cleave', 'blade_echo', 'butcher'],
};

void _measureTree(_Options o) {
  _header('ДЕРЕВО ПАССИВОК · ${o.runs} ранов на строку');
  print('Вкладываем очки в один луч и смотрим, что это даёт. Если строки');
  print('сходятся с «без дерева» — очки за глубину не значат ничего.');
  print('');
  print('Стихийный луч меряется сборкой, которая его тегами пользуется:');
  print('физическому стартовому набору теговые узлы не дают ничего, и');
  print('замер «в среднем» сравнивал бы луч с самим собой без дерева.');
  print('');

  final cap = Curves.passivePointCap;
  _row(['луч', 'без дерева', '${cap ~/ 2} очков', '$cap очков', 'прирост']);
  _rule(5);

  final clusters = <String>{
    for (final node in PassiveTree().nodes)
      if (!node.isRoot) node.cluster,
  };

  int median(PassiveTree? tree, List<String>? build) {
    final depths = <int>[];
    for (var i = 0; i < o.runs; i++) {
      final r = DescentSimulator(
        profile: HeroProfile(
          passives: tree,
          abilities: build,
          powerMultiplier: o.power,
        ),
        seed: o.seed + i,
        brandRank: o.brand,
      ).run(floorCap: o.floorCap, recordFloors: false);
      depths.add(r.maxDepth);
    }
    depths.sort();
    return _p(depths, 0.50);
  }

  for (final cluster in clusters) {
    final build = _clusterBuilds[cluster];
    final half = _fillCluster(cluster, cap ~/ 2);
    final full = _fillCluster(cluster, cap);

    // «Без дерева» считается ТОЙ ЖЕ сборкой: иначе прирост смешивал бы в себе
    // разницу между лоадаутами и разницу от очков.
    final bare = median(null, build);
    final a = median(half, build);
    final b = median(full, build);
    _row([
      cluster,
      '$bare',
      '$a',
      '$b',
      '+${b - bare}',
    ]);
  }

  print('');
  print('Та же стихия, собранная на ПРОПИТКЕ: автоатака бьёт стихией, и');
  print('теговые узлы усиливают то, чем наносится львиная доля урона.');
  print('Разрыв между двумя таблицами — это цена того, что способности');
  print('вносят в урон мало.');
  print('');
  _row(['луч', 'без дерева', '${cap ~/ 2} очков', '$cap очков', 'прирост']);
  _rule(5);

  for (final entry in _infusionBuilds.entries) {
    final build = entry.value;
    final bare = median(null, build);
    final b = median(_fillCluster(entry.key, cap), build);
    _row([
      entry.key,
      '$bare',
      '${median(_fillCluster(entry.key, cap ~/ 2), build)}',
      '$b',
      '+${b - bare}',
    ]);
  }
}

/// Набирает [points] очков, идя ПО ОДНОМУ лучу, пока он не кончится.
///
/// Политика замера, а не совет игроку: нужен воспроизводимый «игрок, который
/// вложился в одну тему», чтобы сравнивать лучи между собой.
PassiveTree _fillCluster(String cluster, int points) {
  final tree = PassiveTree();
  var guard = 0;

  while (tree.spent < points && ++guard < 500) {
    String? pick;
    var best = 1 << 30;

    for (final node in tree.nodes) {
      if (node.cluster != cluster && !node.isRoot) continue;
      if (!tree.canAllocate(node.id, points)) continue;

      final distance = node.x * node.x + node.y * node.y;
      if (distance < best) {
        best = distance;
        pick = node.id;
      }
    }

    // Луч кончился раньше очков — добираем чем придётся: иначе строка
    // сравнивала бы разное число вложенных очков.
    pick ??= _anyAllocatable(tree, points);
    if (pick == null || !tree.allocate(pick, points)) break;
  }
  return tree;
}

String? _anyAllocatable(PassiveTree tree, int points) {
  for (final node in tree.nodes) {
    if (tree.canAllocate(node.id, points)) return node.id;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Режим: замер стены
// ---------------------------------------------------------------------------

void _measureWall(_Options o) {
  _header('ЗАМЕР СТЕНЫ · сколько этажей даёт удвоение силы сборки');
  print('Аналитический прогноз: '
      '${Curves.runExtensionPerDoubling.toStringAsFixed(1)} этажей '
      '(ln4 / ln(a*b) — сила внутри спуска заморожена)');
  print('');

  // Среднее, а не медиана: медиана квантуется этажами боссов и на дельте
  // в 40 этажей даёт ±10 шума. И регрессия по многим точкам, а не одна
  // разность крайних — иначе любой локальный порог читается как тренд.
  final multipliers = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0];
  final xs = <double>[];
  final ys = <double>[];

  _row(['множитель', 'ср. глубина', 'дельта', 'смертью']);
  _rule(4);

  double? prev;
  for (final m in multipliers) {
    var sum = 0.0;
    var deaths = 0;
    for (var i = 0; i < o.runs; i++) {
      final profile = HeroProfile(powerMultiplier: m);
      final r = DescentSimulator(
        profile: profile,
        seed: o.seed + i,
        brandRank: o.brand,
      ).run(floorCap: o.floorCap, recordFloors: false);
      sum += r.maxDepth;
      if (r.ending == RunEnding.death) deaths++;
    }
    final mean = sum / o.runs;
    xs.add(math.log(m) / math.ln2);
    ys.add(mean);

    _row([
      'x${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)}',
      mean.toStringAsFixed(1),
      prev == null ? '—' : '+${(mean - prev).toStringAsFixed(1)}',
      _pct(deaths, o.runs),
    ]);
    prev = mean;
  }

  // Два режима, а не один. Настоящее снаряжение надо ещё НАЙТИ: короткий ран
  // обрывается раньше, чем девять слотов успевают догнать глубину, поэтому в
  // начале удвоение силы даёт меньше этажей, чем обещает формула. С ростом
  // силы отставание снаряжения выходит на постоянную величину, и наклон
  // сходится к целевому. Одна регрессия по всем точкам смешивает эти режимы
  // и показывает среднее между разгоном и установившимся значением — то есть
  // не показывает ничего.
  final split = 3; // x1..x3 — разгон, дальше — установившийся режим
  final early = _linearSlope(xs.sublist(0, split + 1), ys.sublist(0, split + 1));
  final steady = _linearSlope(xs.sublist(split), ys.sublist(split));

  print('');
  print('Разгон  (x1..x3)  : ${early.toStringAsFixed(1)} этажей / удвоение');
  print('Режим   (x3..x16) : ${steady.toStringAsFixed(1)} этажей / удвоение');

  // Сверяемся с МОДЕЛЬЮ, а не с ручкой: ручки больше нет, удлинение
  // определяется кривой мобов, и вопрос ровно один — сходится ли симуляция с
  // тем, что предсказывает арифметика.
  //
  // Модель систематически оптимистичнее симуляции: она не знает ни про
  // потолки брони и сопротивлений, ни про боссов, ни про то, что глубокие
  // этажи занимают больше времени и волна успевает добить героя.
  final model = Curves.runExtensionPerDoubling;
  final drift = (steady - model).abs() / model;

  print('Модель            : ${model.toStringAsFixed(1)} этажей');
  // Порог свободный намеренно: модель не знает про потолки брони и
  // сопротивлений, про боссов и про то, что глубокий этаж тянется дольше и
  // волна успевает добить героя. Расхождение в четверть — это нормальная
  // разница между арифметикой и симуляцией; вдвое — это ошибка в выводе.
  print('Расхождение       : ${(drift * 100).toStringAsFixed(1)} %'
      '${drift > 0.35 ? "  <-- ТРЕБУЕТ ВНИМАНИЯ" : "  OK"}');
  print('');
  print('Чем это настраивается: ТОЛЬКО кривой мобов. Сила сборки внутри');
  print('спуска заморожена — наёмник не переодевается, — поэтому риск растёт');
  print('как (a*b)^d, а удвоение сборки делит его на четыре:');
  print('  Δd = ln4 / ln(a*b).');
  print('Рост предметов (g) на это число не влияет вовсе. Он отвечает за');
  print('другое: уводит ли добытое снаряжение СЛЕДУЮЩИЙ спуск глубже.');
  print('Это показывает --curve строкой «добыча двигает прогресс».');
  print('');
  print('Цель проверяется по установившемуся режиму. Разгон ниже — это не');
  print('ошибка, а следствие того, что снаряжение добывается, а не выдаётся:');
  print('за 35 этажей девять слотов не успевают дорасти до глубины.');
  print('');
  print('Доля смертей ниже 100 % означает, что ран обрывается таймаутом волны,');
  print('а не гибелью героя. Тезис «смерть = прести́ж» при этом не работает.');
}

// ---------------------------------------------------------------------------
// Режим: мета-прогрессия
// ---------------------------------------------------------------------------

void _runMeta(_Options o) {
  _header('МЕТА-ПРОГРЕССИЯ · ${o.metaRuns} ранов подряд, Клеймо ${o.brand}');
  print('Снаряжение переживает смерть, Эхо вкладывается в силу.');
  print('');

  final meta = MetaProgression(seed: o.seed, brandRank: o.brand);

  _row(['ран', 'глубина', 'время', 'Эхо', 'узлов', 'слотов', 'ср. ilvl']);
  _rule(7);

  var cumulativeSeconds = 0.0;
  for (var i = 0; i < o.metaRuns; i++) {
    final r = meta.nextRun(floorCap: o.floorCap);
    meta.spendEcho();
    cumulativeSeconds += r.totalSeconds;
    _row([
      '${i + 1}',
      '${r.maxDepth}',
      _dur(r.totalSeconds),
      '${r.echo}',
      '${meta.nodesBought}',
      '${meta.profile.gear.filledSlots}/${Tuning.gearSlots}',
      meta.profile.gear.averageIlvl.toStringAsFixed(0),
    ]);
  }

  print('');
  print('Суммарное игровое время: ${_dur(cumulativeSeconds)}');
  print('Золота накоплено       : ${_sci(meta.profile.gold)}');
  final first = meta.history.first.maxDepth;
  final last = meta.history.last.maxDepth;
  print('Глубина: $first -> $last  (+${last - first} за ${o.metaRuns} ранов)');
}

// ---------------------------------------------------------------------------
// Режим: полный цикл
// ---------------------------------------------------------------------------

/// Порядок вложения золота в Заставу.
///
/// Таверна первой: лучший наёмник даёт больше, чем любой процент лута,
/// потому что ранг умножает ВЕСЬ StatBlock. Оружейная второй — она кормит
/// сундук. Остальное — удобство.
/// Кто отвечает на развилки в кампании.
enum ForkPlay {
  /// Игрока нет: решает приказ. Так мерился баланс до живых развилок.
  absent,

  /// Игрок есть и всегда жмёт смелый путь. Верхняя граница жадности.
  bold,

  /// Игрок есть, но смелым путём не пользуется. Контроль: без него нельзя
  /// отличить «третий путь работает» от «просто выбирать лучше, чем приказ».
  plain,
}

/// Проводит спуск до конца, отвечая на развилки по стратегии [play].
void _playForks(PlayerProfile player, Contract contract, ForkPlay play) {
  var now = contract.startedAtUtc;

  if (play != ForkPlay.absent) {
    var guard = 0;
    while (guard++ < 500) {
      now = contract.segmentEndsAtUtc!.add(const Duration(seconds: 1));
      player.refreshContracts(now);
      if (!contract.atFork) break;

      final choice = switch (play) {
        ForkPlay.bold => Fork.boldIndex,
        ForkPlay.plain => 0,
        ForkPlay.absent => 0,
      };
      if (!player.chooseFork(contract, choice, now)) break;
    }
  }

  player.refreshContracts(now.add(const Duration(days: 1)));
}

bool _traceCampaign = false;

const _buildOrder = [
  Building.tavern,
  Building.armory,
  Building.vault,
  Building.campfire,
  Building.altar,
  Building.forge,
  Building.cartographer,
  Building.shardBench,
];

/// Прогоняет полный цикл: наём, спуск, добыча, вложения — [runs] раз.
///
/// Отдельно от печати таблицы намеренно: этим же циклом пользуется разбор
/// силы билда (`--power`). Разбирать надо ТОТ профиль, который получается
/// настоящей игрой, а не собранный руками — иначе замер отвечает про
/// выдуманного игрока.
PlayerProfile _playCampaign(
  _Options o, {
  required int runs,
  void Function(
    int index,
    PlayerProfile player,
    Mercenary merc,
    RunResult result,
    int brand,
  )? onRun,
  void Function(String message)? onStop,
}) {
  final player = PlayerProfile();
  // Стартовый наёмник выдаётся бесплатно: без него игроку нечем начать.
  player.roster.reserve.add(Mercenary(
    id: 'starter',
    name: 'Корвин Ржавый',
    rank: MercRank.ragged,
    trait: MercTrait.hardy,
  ));

  for (var i = 0; i < runs; i++) {
    final rng = Rng.stream(o.seed, i, 0, RngPurpose.offline);

    // 1. Таверна: обновить кандидатов и нанять лучшего доступного.
    // Обновление Таверны бесплатно, и живой игрок жмёт его, пока не увидит
    // того, кого может позволить. Автоматика обязана вести себя так же:
    // иначе замер упирается в тупик, которого в игре нет.
    //
    // Список читается у профиля: там же живёт доброволец, которого Таверна
    // отдаёт даром игроку без наёмников и без золота.
    List<Mercenary> affordable() => player.tavernCandidates
        .where((m) => player.hireCostOf(m) <= player.gold)
        .toList()
      ..sort((a, b) => b.rank.index.compareTo(a.rank.index));

    player.refreshTavern(rng);
    var rerolls = 0;
    while (affordable().isEmpty && ++rerolls <= 20) {
      player.refreshTavern(rng);
    }

    final pool = affordable();
    if (pool.isNotEmpty) player.hire(pool.first);

    if (player.roster.reserve.isEmpty) {
      onStop?.call('Контракт ${i + 1}: нет наёмников и не хватает золота '
          'на найм.');
      break;
    }

    // 2. Отправить лучшего из резерва.
    player.roster.reserve.sort((a, b) => b.rank.index.compareTo(a.rank.index));
    final merc = player.roster.reserve.first;
    // Клеймо: балансировщик лезет по лестнице, а не сидит на нуле. Иначе
    // эндгейм нечем померить — прогрессия упирается в плато и стоит.
    final brand = o.brand > 0 ? o.brand : player.brandRankUnlocked;
    player.setBrandRank(brand);

    final contract =
        player.deploy(merc, seed: o.seed + i * 7919, brandRank: brand);

    // 3. Пройти спуск и забрать добычу.
    //
    // Балансировщик живёт вне времени: ему нужен результат, а не ожидание.
    // По умолчанию часы перематываются на сутки — это модель ОТСУТСТВУЮЩЕГО
    // игрока: наёмник встаёт на первой развилке, выстаивает бюджет ожидания
    // и доходит спуск по приказу.
    //
    // `--forkplay` подставляет вместо этого присутствующего игрока: тогда на
    // каждой развилке кто-то отвечает, и видно, сколько присутствие стоит в
    // ГЛУБИНЕ за двадцать контрактов, а не в добыче за один спуск. Разница
    // принципиальная: сундук мал, и лишняя добыча, не поместившаяся в него,
    // просто уходит в переплавку.
    _playForks(player, contract, o.forkPlay);

    // Результат читается ПОСЛЕ перемотки: при отправке посчитан только
    // первый отрезок, до ближайшей развилки.
    final result = contract.result!;

    player.collect(contract);
    // Разбор добычи: рюкзак бесконечен, и находки ждут решения игрока.
    // Балансировщик разбирает их как средний игрок — лучшее в сундук,
    // остальное в золото. Не разобрать значило бы мерить игру, в которой
    // добыча не доезжает до сборки вовсе.
    player.autoSortLoot();
    player.autoSpendEcho();
    _spendPassivePoints(player, _usefulTags(merc.abilities));

    // 4. Вложить золото в Заставу.
    for (final b in _buildOrder) {
      // Резерв на следующий задаток: иначе автоматика вкладывает всё в
      // Заставу и на следующем ране идёт вниз Оборванцем.
      while (player.gold -
                  Roster.hireCost(MercRank.blade,
                      maxDepthEver: player.maxDepthEver) >
              player.outpost.upgradeCost(b) &&
          player.canUpgradeBuilding(b)) {
        if (!player.upgradeBuilding(b)) break;
      }
    }

    onRun?.call(i, player, merc, result, brand);
  }

  return player;
}

/// Сравнение стратегий на развилках по МНОГИМ сидам.
///
/// Одна кампания — один сид, а кампания это длинная цепь: неудачный третий
/// спуск обваливает Заставу и тянет за собой все семнадцать оставшихся.
/// Разброс между сидами больше разницы между стратегиями, и вывод по одному
/// прогону — это вывод о сиде, а не о механике.
void _compareForkPlay(_Options o) {
  _header('РАЗВИЛКИ · присутствие игрока против приказа');
  print('${o.metaRuns} контрактов × ${o.runs} сидов на стратегию.');
  print('Вопрос один: платит ли присутствие — и наказывает ли жадность.');
  print('');

  _row(['кто играет', 'глубина', 'разброс', 'к приказу']);
  _rule(4);

  var baseline = 0.0;

  for (final play in ForkPlay.values) {
    final depths = <int>[];

    for (var s = 0; s < o.runs; s++) {
      final player = _playCampaign(
        _Options(
          mode: o.mode,
          runs: o.runs,
          metaRuns: o.metaRuns,
          seed: o.seed + s * 104729,
          brand: o.brand,
          power: o.power,
          floorCap: o.floorCap,
          forkPlay: play,
        ),
        runs: o.metaRuns,
      );
      depths.add(player.maxDepthEver);
    }

    depths.sort();
    final mean = depths.reduce((a, b) => a + b) / depths.length;
    if (play == ForkPlay.absent) baseline = mean;

    _row([
      _forkPlayRu[play]!,
      mean.toStringAsFixed(1),
      '${depths.first}..${depths.last}',
      baseline <= 0 || play == ForkPlay.absent
          ? '—'
          : '${((mean / baseline - 1) * 100).toStringAsFixed(0)} %',
    ]);
  }

  print('');
  print('Третий путь обязан быть ЛУЧШИМ: платой за него служит присутствие,');
  print('а не минус в бою. Если «всегда смело» не обгоняет приказ — награда');
  print('за то, что игрок зашёл, не работает.');
}

const _forkPlayRu = {
  ForkPlay.absent: 'приказ (нет игрока)',
  ForkPlay.plain: 'здесь, без смелого',
  ForkPlay.bold: 'здесь, всегда смело',
};

void _runCampaign(_Options o) {
  _header('ПОЛНЫЙ ЦИКЛ · ${o.metaRuns} контрактов, Клеймо ${o.brand}');
  print('Наёмник = ран. Добыча выдаётся только при закрытии контракта.');
  print('');

  _row(['№', 'наёмник', 'ранг', 'глубина', 'Клеймо', 'пассивки', 'золото',
      'Застава']);
  _rule(8);

  var cumulativeSeconds = 0.0;

  final player = _playCampaign(
    o,
    runs: o.metaRuns,
    onStop: print,
    onRun: (i, player, merc, result, brand) {
      cumulativeSeconds += result.totalSeconds;
      if (_traceCampaign) {
        // ignore: avoid_print
        print('  контракт ${i + 1}: глубина ${result.maxDepth}, '
            'Эхо ${result.echo}, вещей ${result.itemsFound}, '
            'сундук ${player.stash.length}, '
            'узлов ${player.tree.bought.length}, '
            'золото ${player.gold.toStringAsFixed(0)}');
      }
      _row([
        '${i + 1}',
        merc.name,
        merc.rank.forGender(merc.gender),
        '${result.maxDepth}',
        '$brand',
        '${player.passives.spent}/${player.passivePoints}',
        _sci(player.gold),
        '${_buildTotal(player.outpost)}/'
            '${Building.values.length * Building.maxLevel}',
      ]);
    },
  );

  print('');
  print('Суммарное игровое время : ${_dur(cumulativeSeconds)}');
  // Простой на развилках — тоже время по настенным часам, и замер обязан его
  // называть. Балансировщик моделирует ОТСУТСТВУЮЩЕГО игрока: тот выстаивает
  // весь бюджет ожидания на каждом спуске. Игрок, который отвечает, платит
  // секунды вместо минут — это и есть награда за присутствие.
  print('  простой на развилках    : '
      '${_dur(o.metaRuns * Tuning.forkWaitSeconds)} '
      '(только если игрока нет)');
  print('Максимальная глубина    : ${player.maxDepthEver}');
  print('Узлов древа Эха         : ${player.tree.nodesBought}');
  print('Сундук Заставы          : ${player.stash.length}/${player.outpost.stashSlots}');
  print('Павших наёмников        : ${player.roster.fallen.length}');
  print('');
  _row(['постройка', 'уровень', 'эффект']);
  _rule(3);
  for (final b in Building.values) {
    _row([
      b.ru,
      '${player.outpost.levelOf(b)}/${Building.maxLevel}',
      b.description,
    ]);
  }
}

int _buildTotal(Outpost o) =>
    Building.values.fold(0, (a, b) => a + o.levelOf(b));

// ---------------------------------------------------------------------------
// Вспомогательное
// ---------------------------------------------------------------------------

class _Options {
  _Options({
    required this.mode,
    required this.runs,
    required this.metaRuns,
    required this.seed,
    required this.brand,
    required this.power,
    required this.floorCap,
    required this.forkPlay,
  });

  final String mode;
  final int runs;
  final int metaRuns;
  final int seed;
  final int brand;
  final double power;
  final int floorCap;

  /// Кто отвечает на развилки в кампании. По умолчанию — никто: баланс
  /// меряется по отсутствующему игроку, присутствующий это верхняя граница.
  final ForkPlay forkPlay;

  static _Options parse(List<String> args) {
    var mode = 'runs';
    var runs = 200;
    var metaRuns = 15;
    var seed = 42;
    var brand = 0;
    var power = 1.0;
    var floorCap = 2000;
    var forkPlay = ForkPlay.absent;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String next() => i + 1 < args.length ? args[++i] : '';
      switch (a) {
        case '--curve':
          mode = 'curve';
        case '--wall':
          mode = 'wall';
        case '--campaign':
          mode = 'campaign';
          final v = int.tryParse(i + 1 < args.length ? args[i + 1] : '');
          if (v != null) metaRuns = int.parse(next());
        case '--meta':
          mode = 'meta';
          final v = int.tryParse(i + 1 < args.length ? args[i + 1] : '');
          if (v != null) metaRuns = int.parse(next());
        case '--tree':
          mode = 'tree';
        case '--hp':
          mode = 'hp';
        case '--power-split':
          mode = 'power';
          final v = int.tryParse(i + 1 < args.length ? args[i + 1] : '');
          if (v != null) metaRuns = int.parse(next());
        case '--builds':
          mode = 'builds';
        case '--forks':
          mode = 'forks';
        case '--dist':
          mode = 'runs';
        case '--runs':
          // Только количество прогонов: режим не трогаем, иначе
          // `--wall --runs 120` молча превращается в `--dist`.
          runs = int.tryParse(next()) ?? runs;
        case '--seed':
          seed = int.tryParse(next()) ?? seed;
        case '--brand':
          brand = int.tryParse(next()) ?? brand;
        case '--power':
          power = double.tryParse(next()) ?? power;
        case '--floor-cap':
          floorCap = int.tryParse(next()) ?? floorCap;
        case '--forks-vs':
          mode = 'forks-vs';
        case '--trace':
          _traceCampaign = true;
        case '--forkplay':
          final name = next();
          forkPlay = ForkPlay.values.firstWhere(
            (v) => v.name == name,
            orElse: () => ForkPlay.absent,
          );
        case '--help' || '-h':
          mode = 'help';
      }
    }

    return _Options(
      mode: mode,
      runs: runs,
      metaRuns: metaRuns,
      seed: seed,
      brand: brand,
      power: power,
      floorCap: floorCap,
      forkPlay: forkPlay,
    );
  }
}

void _printUsage() {
  print('''
Балансировщик «Расселины».

  dart run tool/sim_cli.dart [режим] [опции]

Режимы:
  --runs N        распределение глубины смерти по N ранам (по умолчанию)
  --curve         таблица кривых прогрессии
  --wall          замер: сколько этажей даёт удвоение силы билда
  --meta N        N ранов подряд со сквозным снаряжением и Эхом
  --campaign N    полный цикл: таверна -> наём -> контракт -> добыча -> Застава
  --builds        сравнение лоадаутов способностей
  --forks         сравнение политик выбора на развилке

Опции:
  --seed S        базовый сид (42)
  --brand R       ранг Клейма Бездны 0..5 (0)
  --power M       искусственный множитель силы билда (1.0)
  --floor-cap N   потолок этажей на ран (2000)
  --forkplay S    кто отвечает на развилки: absent|plain|bold|smart (absent)
  --forks-vs      сравнение всех четырёх стратегий по многим сидам
''');
}

void _header(String title) {
  print('');
  print('=== $title ${'=' * math.max(0, 62 - title.length)}');
}

final List<int> _widths = [18, 17, 15, 14, 14, 14, 14];

void _row(List<String> cells) {
  final b = StringBuffer();
  for (var i = 0; i < cells.length; i++) {
    b.write(cells[i].padRight(i < _widths.length ? _widths[i] : 14));
  }
  print(b.toString().trimRight());
}

void _rule(int cols) {
  var total = 0;
  for (var i = 0; i < cols; i++) {
    total += i < _widths.length ? _widths[i] : 14;
  }
  print('-' * total);
}

int _p(List<int> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final i = ((sorted.length - 1) * q).round();
  return sorted[i];
}

double _pd(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0.0;
  final i = ((sorted.length - 1) * q).round();
  return sorted[i];
}

String _dur(double seconds) {
  if (seconds.isInfinite || seconds.isNaN) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).round();
  if (h > 0) return '${h}ч ${m}м';
  if (m > 0) return '${m}м ${s}с';
  return '${s}с';
}

String _sci(double v) {
  if (v.abs() < 1000) return v.toStringAsFixed(1);
  if (v.abs() < 1e6) return '${(v / 1e3).toStringAsFixed(1)}k';
  if (v.abs() < 1e9) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v.abs() < 1e12) return '${(v / 1e9).toStringAsFixed(1)}G';
  return v.toStringAsExponential(2);
}

String _pct(int n, int total) =>
    total == 0 ? '0%' : '${(100.0 * n / total).toStringAsFixed(0)}%';

/// Наклон линейной регрессии — глубина как функция log2(силы билда).
double _linearSlope(List<double> xs, List<double> ys) {
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return den == 0.0 ? 0.0 : num / den;
}

/// Политика вложения очков дерева пассивок для балансировщика.
///
/// Идёт ПО ЛУЧАМ, а не вширь: сперва луч, который сборке подходит, до конца,
/// потом следующий. Это не оптимальная сборка — оптимальную мерить
/// бессмысленно, её соберут единицы, — а воспроизводимый игрок, который
/// выбрал тему и держится её.
///
/// Раньше политика была «вширь: любой доступный узел, ближайший к корню», и
/// это было разумно, пока лучей было восемь. Когда их стало тринадцать, те же
/// двадцать девять очков перестали доходить хоть до одного крупного узла:
/// замер показал падение кампании с 79 этажей до 58, и падение было целиком
/// свойством ПОЛИТИКИ, а не игры. Модель среднего игрока обязана меняться
/// вместе с тем, что она моделирует.
void _spendPassivePoints(PlayerProfile player, Set<Tag> useful) {
  final tree = player.passives;

  // Порядок лучей: сперва те, чьи теговые узлы сборке что-то дают, потом
  // остальные. Внутри группы — по числу подходящих узлов.
  final score = <String, int>{};
  final clusters = <String>{};
  for (final node in tree.nodes) {
    if (node.isRoot) continue;
    clusters.add(node.cluster);
    if (node.stat == StatKey.tagDamage && node.tag != null) {
      score[node.cluster] =
          (score[node.cluster] ?? 0) + (useful.contains(node.tag) ? 1 : -1);
    }
  }

  final order = clusters.toList()
    ..sort((a, b) {
      final byScore = (score[b] ?? 0).compareTo(score[a] ?? 0);
      return byScore != 0 ? byScore : a.compareTo(b);
    });

  var guard = 0;
  for (final cluster in order) {
    while (player.passivePointsLeft > 0 && ++guard < 1000) {
      String? pick;
      var best = 1 << 30;

      for (final node in tree.nodes) {
        if (node.cluster != cluster) continue;
        if (!tree.canAllocate(node.id, player.passivePoints)) continue;

        // Ближе к центру — раньше: луч выкупается от корня наружу.
        final distance = node.x * node.x + node.y * node.y;
        if (distance < best) {
          best = distance;
          pick = node.id;
        }
      }

      if (pick == null) break;
      if (!player.allocatePassive(pick)) break;
    }
    if (player.passivePointsLeft <= 0) break;
  }
}

/// Теги, которые сборка реально использует: свои у способностей плюс теги
/// автоатаки, которая есть всегда.
Set<Tag> _usefulTags(List<String> abilities) {
  final tags = <Tag>{Tag.attack, Tag.strike, Tag.physical};
  for (final id in abilities) {
    final def = ContentPack.current.ability(id);
    if (def != null) tags.addAll(def.tags);
  }
  return tags;
}
