import '../balance/curves.dart';
import '../balance/tuning.dart';

/// Постройки Заставы (GDD §6.2).
///
/// Застава покупается ЗОЛОТОМ и даёт экономику и удобство.
/// Древо Эха покупается ЭХОМ и даёт силу и правила игры.
/// Пересечений быть не должно: если узел древа и постройка делают одно и то
/// же, одна из валют лишняя.
enum Building {
  tavern('Таверна', 'Кто приходит наниматься: больше людей и опытнее'),
  armory('Оружейная', 'Сколько вещей находит наёмник и насколько хороших'),
  forge('Кузница', 'Насколько выгодно перебрасывать свойства вещей'),
  vault('Хранилище', 'Сколько вещей влезает в сундук'),
  shardBench('Верстак осколков',
      'Сколько осколков хранится и что уцелеет при замене'),
  altar('Алтарь', 'Сколько золота даёт переплавка лишних вещей'),
  cartographer('Картограф', 'На сколько этажей вперёд виден путь'),
  campfire('Костёр', 'Сколько здоровья наёмник восстановит между этажами');

  const Building(this.ru, this.description);

  final String ru;
  final String description;

  static int get maxLevel => Tuning.maxBuildingLevel;

  /// Есть ли у постройки потолок.
  ///
  /// У Хранилища его нет: сундук — единственное, что игрок хочет всегда, и
  /// единственный сток для золота, который не выдумывает нового контента.
  /// Замер кампании: к двенадцатому контракту из двадцати выкуплены и древо
  /// Эха, и вся Застава, а золота накапливается тринадцать миллионов, и деть
  /// его некуда. Награда, которую нечем потратить, перестаёт быть наградой.
  bool get isEndless => this == Building.vault;
}

/// Состояние Заставы и все производные от него модификаторы.
///
/// Ровно одно место, где уровень постройки превращается в число. Разбросать
/// это по подсистемам — верный способ получить два разных ответа на вопрос
/// «какой сейчас офлайн-кап».
class Outpost {
  Outpost([Map<Building, int>? levels])
      : _levels = {
          for (final b in Building.values) b: levels?[b] ?? 0,
        };

  final Map<Building, int> _levels;

  int levelOf(Building b) => _levels[b] ?? 0;

  /// Копия уровней. Нужна заданиям: «доведите Кузницу до третьего уровня» —
  /// цель, которую нельзя проверить, не заглянув во все постройки сразу.
  Map<Building, int> get snapshotLevels => Map.unmodifiable(_levels);

  /// Можно ли улучшить постройку.
  ///
  /// Кроме потолка уровней есть требование по РЕКОРДУ глубины: уровень N
  /// открывается, когда наёмники доходили до `depthGate(N)`. Без него
  /// Застава выкупалась золотом вперёд прогресса — игрок закрывал экономику
  /// раньше, чем видел бездну, и дальше игра шла сама (замер `--campaign`:
  /// восемь ранов давали +64 этажа).
  bool canUpgrade(Building b, {int maxDepthEver = 1 << 30}) =>
      (b.isEndless || levelOf(b) < Building.maxLevel) &&
      maxDepthEver >= depthGate(levelOf(b) + 1);

  /// Что постройка даёт на уровне [level], числом и словами.
  ///
  /// Живёт здесь, а не на экране: «уровень → число» уже посчитано в этом
  /// файле, и второе такое место разошлось бы с первым — игрок увидел бы
  /// одну цифру в описании и другую в бою.
  static String effectAt(Building b, int level) {
    final o = Outpost({b: level});
    String pct(double v) => '${(v * 100).round()} %';

    return switch (b) {
      Building.tavern => 'наёмников на выбор: ${o.tavernCandidates}',
      Building.armory => 'добыча лучше на ${pct(o.lootQuality)}, '
          'её больше на ${pct(o.lootQuantity)}',
      Building.forge => 'переброс не опустит свойство ниже '
          '${pct(o.rerollFloorPercentile)} качества',
      Building.vault => 'мест в сундуке: ${o.stashSlots}',
      Building.shardBench => 'осколков влезает ${o.shardCapacity}, '
          'при замене уцелеет ${pct(o.shardSalvageOnOverwrite)}',
      Building.altar => 'переплавка возвращает ${pct(o.salvageRate)} цены',
      Building.cartographer => 'видно на ${o.forecastFloors} этажей вперёд',
      Building.campfire =>
        'отдых вернёт ещё ${pct(o.restHealBonus)} здоровья',
    };
  }

  /// Глубина, с которой откроется следующий уровень. `null` — потолок.
  int? nextGate(Building b) =>
      b.isEndless || levelOf(b) < Building.maxLevel
          ? depthGate(levelOf(b) + 1)
          : null;

  /// Глубина, к которой привязан уровень постройки.
  ///
  /// Застава развивается вместе со спуском, а не отдельно от него.
  static int depthGate(int level) => Tuning.depthGatePerLevel * level;

  /// Цена следующего уровня, выраженная через доход на «своей» глубине.
  ///
  /// Фиксированные цены здесь не работают: доход растёт экспоненциально
  /// вместе с глубиной, и вся Застава выкупалась за 8 контрактов, после чего
  /// золото становилось бессмысленным (замер `sim_cli --campaign`). Привязка
  /// к [Curves.goldPerFloor] делает цену читаемой для игрока: «уровень стоит
  /// примерно столько, сколько приносит спуск на такую-то глубину».
  double upgradeCost(Building b) {
    final next = levelOf(b) + 1;
    return Tuning.upgradeCostFloors * Curves.goldPerFloor(depthGate(next));
  }

  bool upgrade(Building b, {int maxDepthEver = 1 << 30}) {
    if (!canUpgrade(b, maxDepthEver: maxDepthEver)) return false;
    _levels[b] = levelOf(b) + 1;
    return true;
  }

  // --- Производные модификаторы ---------------------------------------------

  /// Сколько наёмников может быть в бездне одновременно.
  ///
  /// Второй слот открывает Таверна. Это не удобство, а удвоение числа
  /// решений: игрок собирает два разных билда и выбирает, кого куда послать.
  /// Слот стоит уровня постройки, а не золота за раз, — иначе он был бы
  /// покупкой, а не целью.
  int get deploySlots => levelOf(Building.tavern) >= Tuning.secondSlotLevel
      ? 2
      : 1;

  /// Таверна: сколько кандидатов показывать.
  int get tavernCandidates =>
      Tuning.baseTavernCandidates + levelOf(Building.tavern);

  /// Оружейная: качество лута. Влияет на распределение редкостей.
  double get lootQuality =>
      Tuning.lootQualityPerLevel * levelOf(Building.armory);

  /// Оружейная: количество лута.
  double get lootQuantity =>
      Tuning.lootQuantityPerLevel * levelOf(Building.armory);

  /// Хранилище: слоты сундука Заставы (не рюкзака наёмника).
  int get stashSlots =>
      Tuning.stashSlotsBase +
      Tuning.stashSlotsPerLevel * levelOf(Building.vault);

  /// Кузница: нижняя граница перцентиля при рероллe.
  double get rerollFloorPercentile =>
      Tuning.rerollFloorPerLevel * levelOf(Building.forge);

  /// Верстак: сколько осколков помещается на хранение.
  int get shardCapacity =>
      Tuning.shardCapacityBase +
      Tuning.shardCapacityPerLevel * levelOf(Building.shardBench);

  /// Верстак: шанс сохранить стираемый аффикс как осколок.
  double get shardSalvageOnOverwrite =>
      levelOf(Building.shardBench) >= Tuning.shardSalvageLevel
          ? Tuning.shardSalvageChance
          : 0.0;

  /// Алтарь: доля стоимости, возвращаемая при распылении.
  double get salvageRate =>
      Tuning.baseSalvageRate *
      (1.0 + Tuning.salvageRatePerLevel * levelOf(Building.altar));

  /// Картограф: на сколько этажей вперёд виден прогноз.
  ///
  /// По этажу за уровень, а не «плюс три на первом»: раньше уровни со второго
  /// по восьмой не давали ничего, и постройка брала золото за воздух.
  int get forecastFloors =>
      Tuning.forecastFloorsBase +
      Tuning.forecastFloorsPerLevel * levelOf(Building.cartographer);

  /// Костёр: прибавка к доле HP, восстанавливаемой между этажами.
  double get restHealBonus =>
      Tuning.restHealPerLevel * levelOf(Building.campfire);

  /// Суммарный вклад Заставы в силу спуска.
  ///
  /// Намеренно МАЛЕНЬКИЙ и только косвенный: Застава — это экономика, а не
  /// сила. Прямой силовой бонус здесь превратил бы золото во вторую валюту
  /// силы и обесценил Эхо.
  double get descentPowerBonus => 0.0;

  Map<String, int> toJson() =>
      {for (final e in _levels.entries) e.key.name: e.value};

  static Outpost fromJson(Map<String, dynamic> json) => Outpost({
        for (final b in Building.values) b: (json[b.name] as int?) ?? 0,
      });
}
