import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../model/enemy.dart';
import '../model/echo_tree.dart';
import '../model/haul.dart';
import '../model/hero.dart';
import '../model/item.dart';
import '../content/floor_modifier_def.dart';
import '../model/stat_block.dart';
import '../model/tags.dart';
import 'abilities.dart';
import 'combat.dart';
import 'combat_feed.dart';
import 'fork.dart';
import 'loot.dart';
import 'relics.dart';
import 'triggers.dart';
import 'events.dart';
import 'passive_rules.dart';
import 'rng.dart';

/// Как завершился ран.
enum RunEnding {
  /// Герой погиб — штатный конец, прести́ж.
  death,

  /// Упёрлись в потолок этажей (только для тестов и балансировщика).
  floorCap,

  /// Упёрлись в лимит времени: игрок закрыл приложение / офлайн-кап.
  timeCap,

  /// Волна не убивается за таймаут. Для игрока это неотличимо от стены,
  /// но модели важно различать: здесь герой ещё жив.
  stalled,

  /// Игрок закрыл контракт вручную (GDD §8). Наёмник жив, добыча при нём.
  recalled,

  /// Наёмник встал на развилке и ждёт решения.
  ///
  /// Не конец спуска, а пауза в нём: спуск продолжится с того же места, как
  /// только решение появится — от игрока или от политики по истечении
  /// бюджета ожидания. Отдельное окончание, а не флаг, потому что вызывающий
  /// обязан различать «наёмник погиб» и «наёмник ждёт»: в первом случае
  /// добыча едет наверх, во втором — нет.
  atFork,
}

class FloorRecord {
  FloorRecord({
    required this.depth,
    required this.seconds,
    required this.damageTaken,
    required this.survived,
    required this.itemsFound,
    required this.gold,
    this.modifierId,
    this.lowestHpFraction = 1.0,
  });

  final int depth;
  final double seconds;
  final double damageTaken;
  final bool survived;
  final int itemsFound;
  final double gold;

  /// Модификатор, действовавший на этаже. `null` — этаж без развилки.
  final String? modifierId;

  /// Самая низкая доля здоровья на этаже. Это и есть «критический момент»
  /// для журнала: не «много урона», а «чуть не умер».
  final double lowestHpFraction;
}

class RunResult {
  RunResult({
    required this.maxDepth,
    required this.ending,
    required this.totalSeconds,
    required this.echo,
    required this.gold,
    required this.itemsFound,
    required this.floors,
    required this.anomalies,
    required this.haul,
    required this.damageByType,
    required this.bossesKilled,
    this.killedBy,
    this.pendingFork,
    this.forksTaken = 0,
  });

  final int maxDepth;
  final RunEnding ending;
  final double totalSeconds;
  final int echo;
  final double gold;
  final int itemsFound;
  final List<FloorRecord> floors;

  /// Срабатывания предохранителей шины событий. Ненулевое значение —
  /// признак аномалии баланса, а не нормальной работы.
  final int anomalies;

  /// Рюкзак наёмника. Игроку достаётся только когда контракт закрыт.
  final Haul haul;

  /// Кто добил наёмника. `null`, если ран кончился не смертью.
  final String? killedBy;

  /// Развилка, на которой спуск остановился. Не `null` только при
  /// [RunEnding.atFork].
  final Fork? pendingFork;

  /// Сколько развилок спуск прошёл. Нужно вызывающему, чтобы знать, сколько
  /// решений уже учтено, и не спросить об одном и том же дважды.
  final int forksTaken;

  /// Спуск не кончился, а ждёт решения на развилке.
  bool get awaitingFork => ending == RunEnding.atFork;

  /// Нанесённый за ран урон по типам.
  ///
  /// Задания читают из него долю: «нанесите половину урона Молнией» — это
  /// цель про БИЛД, а не про глубину, и других таких целей в игре нет.
  final Map<DamageType, double> damageByType;

  /// Боссы, которых наёмник действительно уложил.
  ///
  /// Дойти до этажа босса и убить босса — разные события: ран может
  /// оборваться ровно на нём, и задание «победите Владыку Пепла» обязано
  /// отличать одно от другого.
  final Set<String> bossesKilled;

  /// Доля урона данного типа за ран. Ноль, если урона не было вовсе.
  double shareOf(DamageType type) {
    var total = 0.0;
    for (final v in damageByType.values) {
      total += v;
    }
    if (total <= 0.0) return 0.0;
    return (damageByType[type] ?? 0.0) / total;
  }

  /// Скользящее среднее по последним 5 этажам — то, чем офлайн-модель
  /// калибрует аналитический расчёт (GDD §9.1).
  double get avgFloorSecondsLast5 {
    if (floors.isEmpty) return 0.0;
    final tail = floors.length <= 5
        ? floors
        : floors.sublist(floors.length - 5);
    return tail.fold<double>(0.0, (a, f) => a + f.seconds) / tail.length;
  }

  double secondsAtDepth(int depth) {
    for (final f in floors) {
      if (f.depth == depth) return f.seconds;
    }
    return 0.0;
  }
}

/// Драйвер спуска: этаж → волны → сундук → следующий этаж.
class DescentSimulator {
  DescentSimulator({
    required this.profile,
    required this.seed,
    this.brandRank = 0,
    this.startDepth = 1,
    this.backpackCapacityOverride,
    this.salvageRate = 0.35,
    this.outpostLootQuality = 0.0,
    this.outpostLootQuantity = 0.0,
    this.restHealBonus = 0.0,
    this.forkPolicy = ForkPolicy.loot,
    this.forkChoices = const [],
    this.pauseAtUnchosenFork = false,
    this.riftModifier,
    EventBus? bus,
  }) : bus = bus ?? EventBus();

  final HeroProfile profile;
  final int seed;
  final int brandRank;
  final int startDepth;

  /// Вместимость рюкзака. Обычно приходит из ранга наёмника.
  final int? backpackCapacityOverride;

  final double salvageRate;

  /// Вклад Заставы: качество и количество лута, отдых между этажами.
  final double outpostLootQuality;
  final double outpostLootQuantity;
  final double restHealBonus;

  /// Что выбирает наёмник на развилке, когда игрока нет (GDD §2.6).
  final ForkPolicy forkPolicy;

  /// Решения игрока на развилках, по порядку: индекс пути в `Fork.options`.
  ///
  /// Спуск — функция от снимка, сида и ЭТОГО списка. Ничего больше хранить не
  /// нужно: при каждом новом решении спуск пересчитывается с начала за
  /// три-шесть миллисекунд и получается тик в тик тем же. Поэтому и сохранение
  /// не хранит состояние симуляции — только список решений.
  final List<int> forkChoices;

  /// Останавливать ли спуск на развилке, для которой решения ещё нет.
  ///
  /// Балансировщику и повтору это не нужно: им нужен спуск целиком, и там
  /// решает политика. Нужно живой игре — ради того, чтобы было чего ждать.
  /// Модификатор разлома дня: действует на КАЖДОМ этаже, а не между
  /// развилками. `null` — обычный спуск.
  final FloorModifierDef? riftModifier;

  final bool pauseAtUnchosenFork;

  final EventBus bus;

  /// Спуск, посчитанный целиком и мгновенно. Тонкая обёртка над
  /// [DescentDriver]: одна математика на балансировщик, офлайн и экран.
  RunResult run({
    int floorCap = 100000,
    double timeCapSeconds = double.infinity,
    bool recordFloors = true,
  }) {
    final driver = DescentDriver(
      profile: profile,
      seed: seed,
      brandRank: brandRank,
      startDepth: startDepth,
      backpackCapacityOverride: backpackCapacityOverride,
      salvageRate: salvageRate,
      outpostLootQuality: outpostLootQuality,
      outpostLootQuantity: outpostLootQuantity,
      restHealBonus: restHealBonus,
      bus: bus,
      floorCap: floorCap,
      timeCapSeconds: timeCapSeconds,
      recordFloors: recordFloors,
      forkPolicy: forkPolicy,
      forkChoices: forkChoices,
      pauseAtUnchosenFork: pauseAtUnchosenFork,
      riftModifier: riftModifier,
    );
    while (!driver.finished) {
      driver.tick();
    }
    return driver.result;
  }
}

/// Что показывать на экране прямо сейчас.
///
/// Снимок, а не ссылки на живые объекты: UI не должен уметь дотянуться до
/// боевого состояния и что-нибудь в нём поменять.
class DescentSnapshot {
  const DescentSnapshot({
    required this.depth,
    required this.waveIndex,
    required this.waveCount,
    this.resting = false,
    this.restProgress = 1.0,
    required this.isBossWave,
    required this.enemyName,
    required this.enemiesAlive,
    required this.waveProgress,
    required this.heroHpFraction,
    required this.totalSeconds,
    required this.finished,
  });

  final int depth;

  /// Номер волны на этаже, с единицы. У боя с боссом — [waveCount].
  final int waveIndex;
  final int waveCount;

  /// Идёт переход между этажами: боя нет, наёмник отдыхает и лечится.
  ///
  /// Экрану боя это нужно не для красоты. Отдых занимает пять секунд времени
  /// рана, и без объяснения он выглядит как зависшая игра — живой прогон
  /// назвал это «бой стоит секунд пять, потом прыгает вперёд».
  final bool resting;

  /// Доля пройденного отдыха, 0..1.
  final double restProgress;
  final bool isBossWave;

  final String enemyName;
  final int enemiesAlive;

  /// Доля волны, которую герой уже снёс.
  final double waveProgress;

  final double heroHpFraction;
  final double totalSeconds;
  final bool finished;
}

/// Спуск как машина состояний: этаж → волны → босс → награды → отдых.
///
/// Существует ради одного требования: балансировщику нужен ран, посчитанный
/// мгновенно, а экрану — тот же ран, идущий на глазах игрока. Реализация при
/// этом обязана быть одна, иначе бой и офлайн-догонялка разъедутся, и это
/// причина №1 смерти проектов жанра (`docs/01-ANALYSIS.md` §3).
///
/// Поэтому наружу торчит [tick] — один шаг симуляции, — а батч-режим
/// (`DescentSimulator.run`) сводится к `while (!finished) tick()`.
class DescentDriver {
  DescentDriver({
    required this.profile,
    required this.seed,
    this.brandRank = 0,
    this.startDepth = 1,
    this.backpackCapacityOverride,
    this.salvageRate = 0.35,
    this.outpostLootQuality = 0.0,
    this.outpostLootQuantity = 0.0,
    this.restHealBonus = 0.0,
    EventBus? bus,
    this.floorCap = 100000,
    this.timeCapSeconds = double.infinity,
    this.recordFloors = true,
    this.forkPolicy = ForkPolicy.loot,
    this.forkChoices = const [],
    this.pauseAtUnchosenFork = false,
    this.riftModifier,
    this.feed,
  }) : bus = bus ?? EventBus() {
    this.bus.resetDiagnostics();

    hero = HeroState(profile.aggregate());

    // Рантайм способностей живёт на уровне РАНА: кулдауны и баффы не должны
    // обнуляться между волнами, иначе способность с перезарядкой 14 с была бы
    // готова к началу каждой волны.
    _mods = CombatModifiers()
      ..deathThreshold = profile.tree?.hasDeathThreshold ?? false;
    _rules = profile.relicRules;
    _abilities =
        AbilityRuntime(profile.loadout, modifiers: _mods, rules: _rules);
    _triggers = TriggerRuntime(
      bus: this.bus,
      abilities: _abilities,
      mods: _mods,
    )
      ..rules = _rules
      ..configure(profile.gear.triggerIds);
    haul = Haul(
      capacity: backpackCapacityOverride ?? 12,
      salvageRate: salvageRate,
    );

    // «Канат глубин» опускает наёмника ещё ниже — это его награда за
    // урезанный запас здоровья.
    _depth = startDepth + profile.startDepthBonus + _rules.startDepthBonus;

    // Разлом действует с первого этажа, а не с первой развилки: между ними
    // может быть два этажа, и «модификатор дня», не работающий в начале дня,
    // выглядел бы поломкой.
    _modifier = riftModifier;
    _maxDepth = _depth - 1;

    if (_depth - startDepth < floorCap) {
      _beginFloor();
    } else {
      _finish(RunEnding.floorCap);
    }
  }

  final HeroProfile profile;
  final int seed;
  final int brandRank;
  final int startDepth;
  final int? backpackCapacityOverride;
  final double salvageRate;

  /// Оружейная: качество и количество лута в спуске (GDD §6.2).
  ///
  /// Приходят числами снаружи, а не берутся из Заставы: ядро не знает про
  /// постройки. Иначе симуляция потянула бы за собой весь профиль игрока и
  /// перестала бы быть переиспользуемой.
  final double outpostLootQuality;
  final double outpostLootQuantity;

  /// Костёр: прибавка к доле HP, восстанавливаемой между этажами.
  final double restHealBonus;

  final EventBus bus;

  final int floorCap;
  final double timeCapSeconds;
  final bool recordFloors;

  /// Канал наблюдения для экрана. `null` в офлайне и у балансировщика:
  /// анимацию там некому смотреть, а миллионы тиков не должны платить за
  /// записи, которые никто не заберёт (`combat_feed.dart`).
  final CombatFeed? feed;

  /// Что выбирает наёмник на развилке, когда игрока нет (GDD §2.6).
  final ForkPolicy forkPolicy;

  /// Решения игрока на развилках, по порядку: индекс пути в `Fork.options`.
  ///
  /// Спуск — функция от снимка, сида и ЭТОГО списка. Ничего больше хранить не
  /// нужно: при каждом новом решении спуск пересчитывается с начала за
  /// три-шесть миллисекунд и получается тик в тик тем же. Поэтому и сохранение
  /// не хранит состояние симуляции — только список решений.
  final List<int> forkChoices;

  /// Останавливать ли спуск на развилке, для которой решения ещё нет.
  ///
  /// Балансировщику и повтору это не нужно: им нужен спуск целиком, и там
  /// решает политика. Нужно живой игре — ради того, чтобы было чего ждать.
  final bool pauseAtUnchosenFork;

  /// Модификатор разлома дня. В отличие от модификатора развилки, действует
  /// от первого этажа до последнего — в этом и состоит лицо дня.
  final FloorModifierDef? riftModifier;


  late final HeroState hero;
  late final Haul haul;
  late AbilityRuntime _abilities;
  late final TriggerRuntime _triggers;
  late final CombatModifiers _mods;

  /// Поправки боя за весь ран. Наружу — ради журнала и тестов: по ним видно,
  /// сработал ли «Порог» древа Эха.
  CombatModifiers get mods => _mods;
  RelicRules _rules = RelicRules.none;

  /// Боевые правила дерева пассивок. Считаются один раз на ран: дерево
  /// заперто вместе с остальным лоадаутом с момента отправки.
  late final PassiveRules _passives = PassiveRules.from(profile.passives);

  final List<FloorRecord> floors = [];

  late int _depth;
  late int _maxDepth;
  double _totalSeconds = 0.0;
  double _gold = 0.0;
  int _items = 0;
  RunEnding _ending = RunEnding.floorCap;

  /// Сколько развилок уже пройдено. Индекс в [forkChoices]: решения хранятся
  /// по ПОРЯДКУ, а не по глубине — так список остаётся списком, а не картой с
  /// дырами, и его нечем рассинхронизировать.
  int _forkIndex = 0;

  /// Развилка, на которой спуск остановился.
  Fork? _pendingFork;
  bool _finished = false;

  // Состояние текущего этажа.
  late Rng _floorRng;
  late Rng _lootRng;
  double _floorSeconds = 0.0;
  double _floorDamage = 0.0;
  double _floorLowestHp = 1.0;
  String? _killedBy;
  bool _survived = true;
  bool _stalled = false;
  EnemyArchetype? _boss;
  Fork? _fork;
  FloorModifierDef? _modifier;
  /// Стартовое значение учитывает реликты: на этажах без развилки
  /// модификатора нет, а «Рог охоты» действует всегда.
  late double _mobHpMultiplier = 1.0 + _rules.mobHpBonus;
  double _mobDpsMultiplier = 1.0;
  double _bonusEcho = 0.0;

  /// Этажей без реликта. Гарантия от невезения (GDD §5.4): без неё игрок
  /// может пройти сотню этажей и не увидеть ни одного билд-архетипа.
  int _floorsSinceRelic = 0;
  int _waveCount = 0;
  int _waveIndex = 0;
  bool _bossPending = false;
  bool _inBossWave = false;

  /// Урон по типам за весь ран и уложенные боссы — то, из чего задания
  /// строят цели про билд, а не про глубину.
  final List<double> _damageByType =
      List<double>.filled(DamageType.values.length, 0.0);
  final Set<String> _bossesKilled = <String>{};

  WaveRunner? _runner;

  /// Остаток времени, не набравший полного тика. Копится, а не отбрасывается:
  /// иначе при 60 кадрах в секунду симуляция отставала бы от часов.
  double _carry = 0.0;

  bool get finished => _finished;

  int get depth => _depth;
  int get maxDepth => _maxDepth;
  /// Игровых секунд по ЗАВЕРШЁННЫМ этажам.
  double get totalSeconds => _totalSeconds;

  /// Игровых секунд с начала спуска, включая текущий, ещё не пройденный этаж.
  ///
  /// Отличие от [totalSeconds] решающее для всего, что показывает бой прямо
  /// сейчас: `totalSeconds` растёт скачками, только когда этаж закрыт, и
  /// перемотка по нему всегда попадает на границу этажей — то есть на начало
  /// первой волны, где герой уже отдохнул и полон здоровья. Наблюдатель видел
  /// бы вечные 100 % HP и нулевой прогресс волны.
  /// Отдых прибавляется к [totalSeconds] целиком в момент конца этажа —
  /// так числа рана остаются теми же, что и были. А здесь ещё не прошедшая
  /// его часть вычитается: наблюдателю время обязано идти ровно, иначе экран
  /// замирает ровно на длину отдыха и потом прыгает вперёд.
  double get elapsedSeconds =>
      _totalSeconds -
      _restRemaining +
      _floorSeconds +
      (_runner?.seconds ?? 0.0);

  /// Текущая волна. `null`, когда боя сейчас нет: ран кончился или идёт
  /// переход между этажами ([resting]).
  WaveRunner? get wave => _runner;

  DescentSnapshot get snapshot {
    final runner = _runner;
    var alive = 0;
    if (runner != null) {
      for (final e in runner.enemies) {
        if (e.alive) alive++;
      }
    }
    return DescentSnapshot(
      depth: _depth,
      // На отдыхе волн уже нет: следующая начнётся после перехода. Номер
      // «4 из 3» в этот момент читался бы как ошибка счёта.
      waveIndex: resting
          ? 1
          : (_inBossWave ? _waveCount : _waveIndex + 1).clamp(1, _waveCount),
      waveCount: _waveCount,
      resting: resting,
      restProgress: restProgress,
      isBossWave: _inBossWave,
      enemyName: runner == null || runner.enemies.isEmpty
          ? ''
          : runner.enemies.first.archetype.name,
      enemiesAlive: alive,
      waveProgress: runner?.waveProgress ?? 1.0,
      heroHpFraction: hero.hpFraction,
      totalSeconds: _totalSeconds,
      finished: _finished,
    );
  }

  RunResult get result => RunResult(
        maxDepth: _maxDepth,
        ending: _ending,
        totalSeconds: _totalSeconds,
        // Древо больше не множит само Эхо: с раунда 20 узлы дают статы и
        // правила, а не «+N % ко всему». Множить награду на силу билда значило
        // бы платить дважды за одно вложение.
        echo: (Curves.echo(_maxDepth, brandRank: brandRank) + _bonusEcho)
            .round(),
        gold: _gold,
        itemsFound: _items,
        floors: floors,
        anomalies: bus.cascadeOverflows + bus.budgetOverflows,
        haul: haul,
        damageByType: {
          for (final type in DamageType.values)
            if (_damageByType[type.index] > 0.0)
              type: _damageByType[type.index],
        },
        bossesKilled: Set.unmodifiable(_bossesKilled),
        killedBy: _killedBy,
        pendingFork: _pendingFork,
        forksTaken: _forkIndex,
      );

  /// Закрывает спуск по воле игрока: наёмник разворачивается и уходит наверх.
  ///
  /// Всё, что он успел набрать, остаётся при нём, Эхо считается по достигнутой
  /// глубине без штрафа — наказывать не за что (GDD §8). Отзыв обрывает ран
  /// там, где он есть СЕЙЧАС, поэтому и результат берётся отсюда же, а не
  /// пересчитывается: пересчёт был бы вторым источником правды.
  void recall() {
    if (_finished) return;
    _finish(RunEnding.recalled);
  }

  /// Один шаг симуляции: 100 мс игрового времени.
  void tick() {
    if (_finished) return;

    // Отдых между этажами занимает время РАНА, а не пропускается разом.
    //
    // Раньше переход прибавлял пять секунд к часам одним движением. Для
    // пакетного расчёта разницы нет, а наблюдатель за боем видел ровно то,
    // на что и пожаловался живой прогон: экран замирает на пять секунд, а
    // потом прыгает вперёд. Часы рана при этом шли, а тики — нет.
    if (_restRemaining > 0.0) {
      _restRemaining -= Tuning.tickSeconds;
      if (_restRemaining <= 0.0) {
        _restRemaining = 0.0;
        _beginFloor();
      }
      return;
    }

    final runner = _runner!;
    runner.tick();
    if (runner.finished) _closeWave();
  }

  /// Сколько игровых секунд отдыха осталось. Ноль — идёт бой.
  double _restRemaining = 0.0;

  /// Идёт ли переход между этажами. Наружу — ради экрана боя: пауза, которую
  /// нечем объяснить, читается как зависшая игра.
  bool get resting => _restRemaining > 0.0;

  /// Доля пройденного отдыха, 0..1.
  double get restProgress => _restRemaining <= 0.0
      ? 1.0
      : 1.0 - _restRemaining / Tuning.restSecondsBetweenFloors;

  /// Прокрутить `seconds` игрового времени. Возвращает число сделанных тиков.
  ///
  /// Ускорение x2/x4 — это вызов с бо́льшим `seconds`, а НЕ увеличенный dt:
  /// шаг фиксирован, иначе детерминизм и сверка офлайна ломаются.
  int advance(double seconds) {
    if (seconds <= 0.0) return 0;
    _carry += seconds;
    final dt = Tuning.tickSeconds;
    var done = 0;
    while (_carry >= dt && !_finished) {
      _carry -= dt;
      tick();
      done++;
    }
    if (_finished) _carry = 0.0;
    return done;
  }

  // --- Машина состояний ------------------------------------------------------

  void _beginFloor() {
    _floorRng = Rng.stream(seed, _depth, 0, RngPurpose.combat);
    _lootRng = Rng.stream(seed, _depth, 0, RngPurpose.lootRoll);

    _floorSeconds = 0.0;
    _floorDamage = 0.0;
    _floorLowestHp = 1.0;
    _survived = true;
    _stalled = false;

    // Развилка выбирает ПУТЬ, а не этаж: модификатор держится до следующей
    // развилки. Иначе выбор касался бы одного этажа из трёх и не значил бы
    // почти ничего — замерено, политики выбора расходились на 1 этаж глубины.
    // Развилка может ОСТАНОВИТЬ спуск: если решения на неё ещё нет, а
    // останавливаться разрешено, наёмник встаёт и ждёт. Этаж при этом не
    // начинается вовсе — иначе он посчитался бы по старому модификатору, а
    // потом ещё раз по выбранному.
    if (ForkChooser.isForkFloor(_depth) && !_rollFork()) return;

    _boss = Bestiary.bossFor(_depth);
    _waveCount =
        _boss != null ? Tuning.wavesPerBossFloor : Tuning.wavesPerFloor;
    final waveMultiplier = _modifier?.value(FloorEffect.waveMultiplier) ?? 0.0;
    if (waveMultiplier > 0.0) {
      _waveCount = (_waveCount * waveMultiplier).round();
    }
    if (_rules.waveReduction > 0) {
      _waveCount = (_waveCount - _rules.waveReduction).clamp(1, 1000);
    }
    _waveIndex = 0;
    _bossPending = _boss != null;
    _inBossWave = false;

    _beginWave();
  }

  void _beginWave() {
    if (_waveIndex < _waveCount) {
      _runner = WaveRunner(
        bus: bus,
        depth: _depth,
        hero: hero,
        enemies: _spawnPack(_waveIndex),
        rng: _floorRng,
        abilities: _abilities,
        triggers: _triggers,
        rules: _rules,
        passives: _passives,
        feed: feed,
      );
      return;
    }
    if (_bossPending) {
      _bossPending = false;
      _inBossWave = true;
      _runner = WaveRunner(
        bus: bus,
        depth: _depth,
        hero: hero,
        enemies: [EnemyInstance.spawn(_boss!, _depth, brandRank: brandRank)],
        rng: _floorRng,
        abilities: _abilities,
        triggers: _triggers,
        rules: _rules,
        passives: _passives,
        feed: feed,
      );
      return;
    }
    _endFloor();
  }

  void _closeWave() {
    final outcome = _runner!.outcome;
    for (var i = 0; i < _damageByType.length; i++) {
      _damageByType[i] += outcome.damageByType[i];
    }
    _floorSeconds += outcome.seconds;
    _floorDamage += outcome.damageTaken;
    if (outcome.lowestHpFraction < _floorLowestHp) {
      _floorLowestHp = outcome.lowestHpFraction;
    }
    if (outcome.killer != null) _killedBy = outcome.killer!.name;

    if (!outcome.heroAlive) {
      _survived = false;
      _endFloor();
      return;
    }
    if (outcome.timedOut) {
      _stalled = true;
      _endFloor();
      return;
    }

    if (_inBossWave) {
      // Дошёл до босса и уложил босса — разные события: сюда попадают только
      // те, кого волна пережила, а `heroAlive` и таймаут отсеяны выше.
      if (_boss != null) _bossesKilled.add(_boss!.id);
      _endFloor();
      return;
    }

    _waveIndex++;
    _beginWave();
  }

  void _endFloor() {
    var floorItems = 0;
    var floorGold = 0.0;

    if (_survived && !_stalled) {
      // «Сапоги нисходящего»: золото под ногами наёмник не подбирает.
      if (_rules.goldEnabled) {
        // «+% к находимому золоту» читается ЗДЕСЬ и больше нигде. Стат
        // писался предметами и деревом, складывался в блок героя — и не
        // доезжал до единственного места, где начисляется золото: восемь
        // узлов «Кошель» и «Чутьё на золото» не делали ничего.
        floorGold = Curves.goldPerFloor(_depth, brandRank: brandRank) *
            (1.0 + hero.stats.goldFind);
        _gold += floorGold;
        haul.gold += floorGold;
      }

      final chestChance = _depth <= Tuning.onboardingFloors
          ? Tuning.onboardingChestItemChance
          : Tuning.chestItemChance;
      if (_lootRng.chance(chestChance)) floorItems++;
      if (_boss != null) {
        floorItems += _depth % 10 == 0 ? Tuning.bigBossItems : Tuning.bossItems;
      }

      // «+40 % лута» — это доля к количеству, а количество целое. Дробная
      // часть разыгрывается, иначе +40 % к одному предмету означали бы ноль.
      final quantity = (_modifier?.value(FloorEffect.lootQuantity) ?? 0.0) +
          hero.stats.lootQuantity +
          outpostLootQuantity;
      if (quantity > 0.0 && floorItems > 0) {
        final extra = floorItems * quantity;
        floorItems += extra.floor();
        if (_lootRng.chance(extra - extra.floor())) floorItems++;
      }

      // Модификатор «Тиски»: боссы этажа дают удвоенное Эхо. Эхо считается от
      // достигнутой глубины, поэтому прибавка берётся как предельный вклад
      // ЭТОГО этажа — иначе множитель было бы не к чему применить.
      final marginalEcho = Curves.echo(_depth, brandRank: brandRank) -
          Curves.echo(_depth - 1, brandRank: brandRank);

      final echoMultiplier =
          _modifier?.value(FloorEffect.bossEchoMultiplier) ?? 0.0;
      if (_boss != null && echoMultiplier > 1.0) {
        _bonusEcho += (echoMultiplier - 1.0) * marginalEcho;
      }

      // Прибавка за каждый этаж, а не только за босса: третьему пути развилки
      // нужна награда, которая приходит всегда.
      final echoBonus = _modifier?.value(FloorEffect.echoBonus) ?? 0.0;
      if (echoBonus > 0.0) _bonusEcho += echoBonus * marginalEcho;

      // «Рог охоты»: боссы отдают больше — и Эха, и добычи. Плата за это
      // ждёт на каждом обычном этаже: враги крепче.
      if (_boss != null && _rules.bossRewardMultiplier > 1.0) {
        _bonusEcho += (_rules.bossRewardMultiplier - 1.0) * marginalEcho;
        floorItems += (_rules.bossRewardMultiplier - 1.0).round();
      }
      var taken = 0;
      for (var i = 0; i < floorItems; i++) {
        // Гарантия: если реликта не было слишком долго, большой босс роняет
        // его принудительно. Шанс в 4 % на длинной дистанции всё равно даёт
        // игроков, не видевших ни одного реликта за сотню этажей.
        final pity = _boss != null &&
            _depth % 10 == 0 &&
            _floorsSinceRelic >= Tuning.relicPityFloors &&
            i == 0;

        final found = ItemFactory.roll(
          ilvl: _depth,
          rng: _lootRng,
          // Оружейная складывается со статами наёмника: и то и другое —
          // «качество добычи», и различать их игроку незачем.
          lootQuality: hero.stats.lootQuality + outpostLootQuality,
          rarityBonus:
              (_modifier?.value(FloorEffect.chestRarityBonus) ?? 0.0).round(),
          forceRelic: pity,
        );
        if (found.isRelic) _floorsSinceRelic = 0;

        // НАЁМНИК НЕ ПЕРЕОДЕВАЕТСЯ. Найденное целиком уходит в рюкзак.
        //
        // Раньше он надевал лучшее по дороге — «профессионал не понесёт
        // лучший меч в мешке», — и это стоило игроку контроля: сборка,
        // отправленная вниз, к середине спуска переставала быть той, которую
        // он собрал. Живой прогон дал приговор: «сам наёмник не должен менять
        // снаряжение ни при одном варианте игры».
        //
        // Цена известна и заплачена сознательно: сила сборки внутри спуска
        // теперь ЗАМОРОЖЕНА. Наёмник уходит вниз ровно с тем, что ему дали, и
        // глубина целиком определяется решением игрока до отправки. Это и
        // есть смысл всей игры — решения принимаются наверху.
        //
        // Реликт «Сапоги нисходящего» заставляет проходить мимо мелочи:
        // предметы ниже порога редкости просто не подбираются.
        final minRarity = _rules.minRarity;
        if (minRarity != null && found.rarity.rank < minRarity.rank) {
          continue;
        }

        taken++;
        haul.addItem(found);
      }

      // Считаем ВЗЯТОЕ, а не выпавшее: «Сапоги нисходящего» заставляют
      // проходить мимо мелочи, и записывать её в добычу — значит врать
      // и журналу, и офлайн-отчёту.
      _floorsSinceRelic++;
      floorItems = taken;
      if (taken > 0) {
        _syncEquipment();
        _items += taken;
      }

      _maxDepth = _depth;
    }

    if (recordFloors) {
      floors.add(FloorRecord(
        depth: _depth,
        seconds: _floorSeconds,
        damageTaken: _floorDamage,
        survived: _survived && !_stalled,
        itemsFound: floorItems,
        gold: floorGold,
        modifierId: _modifier?.id,
        lowestHpFraction: _floorLowestHp,
      ));
    }

    _totalSeconds += _floorSeconds;

    // Счётчики этажа обнуляются здесь, а не в начале следующего: между ними
    // теперь есть время, и всё, что уже учтено в `_totalSeconds`, не должно
    // считаться вторично.
    _floorSeconds = 0.0;
    _runner = null;

    if (!_survived) return _finish(RunEnding.death);
    if (_stalled) return _finish(RunEnding.stalled);
    if (_totalSeconds >= timeCapSeconds) return _finish(RunEnding.timeCap);

    // Отдых между этажами. Лечение начисляется сразу, а время тратится
    // тиками: полоска здоровья, ползущая вверх, — это и есть объяснение
    // паузы, а числа рана от этого не меняются.
    _totalSeconds += Tuning.restSecondsBetweenFloors;
    // Отдых возвращает долю маны — ту же, что и HP. Полный сброс обнулял бы
    // бюджет как понятие: тратить всё к концу этажа было бы бесплатно.
    hero.restoreMana(hero.stats.maxMana * Tuning.restHealFraction +
        hero.stats.manaRegen * Tuning.restSecondsBetweenFloors);

    // «Неутомимые сапоги» и «Кровавый обет» отменяют отдых: первый в обмен
    // на более короткий этаж, второй — на тройной вампиризм.
    if (!_rules.restDisabled && !_rules.healOnlyByLeech) {
      hero.heal(hero.stats.hpRegen * Tuning.restSecondsBetweenFloors +
          hero.stats.maxHp * (Tuning.restHealFraction + restHealBonus));
    }

    _depth++;

    if (_depth - startDepth >= floorCap) {
      _finish(RunEnding.floorCap);
      return;
    }

    _restRemaining = Tuning.restSecondsBetweenFloors;
  }



  /// Пересобирает всё, что зависит от снаряжения.
  ///
  /// Вызывается, когда наёмник надел найденное прямо в спуске. Рантайм
  /// способностей пересоздаётся ТОЛЬКО если сменился сам список способностей
  /// (это делает реликт, выключающий активки): иначе он потерял бы кулдауны и
  /// баффы на ровном месте.
  void _syncEquipment() {
    _rules = profile.relicRules;
    _triggers
      ..rules = _rules
      ..configure(profile.gear.triggerIds);

    final ids = [for (final def in profile.loadout) def.id];
    if (ids.length != _abilities.loadout.length ||
        !_sameIds(ids, _abilities.loadout.map((d) => d.id).toList())) {
      _abilities = AbilityRuntime(profile.loadout,
          modifiers: _mods, rules: _rules);
      _triggers.abilities = _abilities;
    } else {
      _abilities.rules = _rules;
    }

    _refreshHero();
  }

  static bool _sameIds(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _finish(RunEnding ending) {
    _ending = ending;
    _finished = true;
    _runner = null;

    // Секунды последнего этажа уже сложены в общий счёт. Оставить их ещё и
    // в счётчике этажа значит показать наблюдателю время, которого не было.
    _floorSeconds = 0.0;
  }

  List<EnemyInstance> _spawnPack(int wave) {
    final rng = Rng.stream(seed, _depth, wave, RngPurpose.enemyPack);
    final archetype = Bestiary.pick(rng);
    var count = rng.nextIntRange(archetype.packMin, archetype.packMax);

    final packMultiplier = _modifier?.value(FloorEffect.packMultiplier) ?? 0.0;
    if (packMultiplier > 0.0) count = (count * packMultiplier).round();

    return List.generate(
      count,
      (_) => EnemyInstance.spawn(
        archetype,
        _depth,
        brandRank: brandRank,
        hpMultiplier: _mobHpMultiplier,
        dpsMultiplier: _mobDpsMultiplier,
      ),
    );
  }

  /// Катит развилку и применяет выбранный модификатор к этажу.
  ///
  /// Статы героя пересобираются здесь же: сопротивления, перезарядки и урон
  /// по тегу — это прибавки к блоку, а «реген не работает» и «ауры не
  /// действуют» блоком невыразимы и потому живут флагами.
  ///
  /// Возвращает `false`, если спуск ВСТАЛ в ожидании решения игрока.
  bool _rollFork() {
    final index = _forkIndex++;
    final decided = index < forkChoices.length ? forkChoices[index] : null;

    // На стартовом этаже не встаём никогда. Верёвка спускает наёмника сразу
    // на глубину, кратную трём, и развилка выпадала бы в ту же секунду, что
    // и отправка: игрок нажал «Отправить» и тут же получил вопрос, а спуск
    // при этом не записал ни одного этажа — журнал пустой, уведомление
    // мгновенное. Первая остановка обязана быть ПОСЛЕ спуска, а не вместо.
    final atStart =
        _depth <= startDepth + profile.startDepthBonus + _rules.startDepthBonus;

    if (decided == null && pauseAtUnchosenFork && !atStart) {
      // Пути показываются те же, что будут выбраны: развилка детерминирована
      // по сиду и глубине, и предложить одно, а посчитать другое нельзя.
      _pendingFork = ForkChooser.roll(seed, _depth, forkPolicy);
      _finish(RunEnding.atFork);
      return false;
    }

    _fork = ForkChooser.roll(seed, _depth, forkPolicy, chosen: decided);

    // Разлом дня складывается с выбранным путём, а не заменяет его: иначе
    // развилка внутри разлома перестала бы что-либо решать.
    final rift = riftModifier;
    _modifier = rift == null
        ? _fork!.chosen
        : FloorModifierDef.combine(_fork!.chosen, rift);

    final modifier = _modifier!;
    _mods.resetFloor();
    _mods.regenDisabled = modifier.disablesRegen;
    _mods.aurasDisabled = modifier.disablesAuras;
    _mods.autoAttackDamage = modifier.value(FloorEffect.autoAttackDamage);

    // Прибавка «Рога охоты» идёт поверх модификатора этажа: реликт меняет
    // весь спуск, модификатор — только отрезок между развилками.
    _mobHpMultiplier =
        1.0 + modifier.value(FloorEffect.mobHp) + _rules.mobHpBonus;
    _mobDpsMultiplier = 1.0 + modifier.value(FloorEffect.mobDps);

    _refreshHero();

    return true;
  }

  /// Пересобирает статы героя с учётом действующего модификатора.
  ///
  /// Единственная точка: находка предмета в середине пути тоже проходит через
  /// неё, иначе новый меч молча снимал бы штрафы и бонусы модификатора.
  void _refreshHero() {
    final modifier = _modifier;
    if (modifier == null) {
      hero.refresh(profile.aggregate());
      return;
    }
    hero.refresh(profile.aggregate() +
        StatBlock(
          resistFire: modifier.value(FloorEffect.resistFire),
          resistCold: modifier.value(FloorEffect.resistCold),
          resistVoid: modifier.value(FloorEffect.resistVoid),
          cooldownReduction: modifier.value(FloorEffect.cooldownReduction),
          tagDamage: {Tag.fire: modifier.value(FloorEffect.tagDamageFire)},
        ));
  }
}

/// Прогон последовательности ранов с сохранением снаряжения и Эха между ними.
///
/// Это и есть проверка меты: снаряжение переживает смерть, поэтому каждый
/// следующий ран стартует сильнее. Эхо добавляется сверху.
class MetaProgression {
  MetaProgression({required this.seed, this.brandRank = 0});

  final int seed;
  final int brandRank;

  late final HeroProfile profile = HeroProfile(tree: tree);
  final List<RunResult> history = [];

  /// Сундук Заставы. Появился вместе с правилом «наёмник не переодевается»:
  /// раньше снаряжение росло само внутри спуска, и модель меты могла о
  /// сундуке не знать. Теперь единственный способ стать сильнее — вернуться,
  /// сложить найденное и одеться перед следующим спуском. Модель обязана
  /// делать ровно это, иначе она мерит игру, которой нет.
  final List<Item> stash = [];

  RunResult nextRun({
    int floorCap = 100000,
    double timeCapSeconds = double.infinity,
  }) {
    // Одеться перед спуском — тем же правилом, что и в игре.
    profile.equipFrom(stash, depth: 1);

    final result = DescentSimulator(
      profile: profile,
      seed: seed + history.length * 7919,
      brandRank: brandRank,
      startDepth: 1,
    ).run(floorCap: floorCap, timeCapSeconds: timeCapSeconds);

    profile.echoTotal += result.echo;
    profile.gold += result.gold;

    // Вернуться и сложить: снаряжение целиком плюс всё донесённое.
    stash
      ..addAll(profile.gear.unequipAll())
      ..addAll(result.haul.items);

    history.add(result);
    return result;
  }

  final EchoTree tree = EchoTree();

  /// Политика вложения Эха для балансировщика: покупает всё, что по карману.
  /// Сама политика живёт в древе — она же используется автозакупкой профиля.
  void spendEcho() {
    var guard = 0;
    while (++guard < 1000) {
      final node = tree.nextByBalancedPolicy();
      if (node == null) break;

      final left = tree.buy(node, profile.echoTotal);
      if (left == null) break;
      profile.echoTotal = left;
    }
  }

  int get nodesBought => tree.nodesBought;
}
