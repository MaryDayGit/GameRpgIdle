import '../model/gear.dart';
import '../model/stat_block.dart';

/// Конфигурация геймплейных констант. Значения по умолчанию дублируют
/// `assets/content/balance.json` и нужны только чтобы ядро работало без
/// загруженного контента.
class TuningConfig {
  const TuningConfig({
    this.heroBase = const StatBlock(
      maxHp: 200.0,
      hpRegen: 0.5,
      maxMana: 100.0,
      manaRegen: 5.0,
      armor: 25.0,
      attackDamage: 12.0,
      spellPower: 8.0,
      attackSpeed: 1.2,
      critChance: 0.05,
      critMulti: 0.5,
    ),
    this.spellReferenceRate = 1.2,
    this.chillSeconds = 2.0,
    this.tickSeconds = 0.1,
    this.wavesPerFloor = 3,
    this.wavesPerBossFloor = 1,
    this.restSecondsBetweenFloors = 5.0,
    this.restHealFraction = 0.35,
    this.waveTimeoutSeconds = 3600.0,
    this.stallCheckSeconds = 30.0,
    this.stallProgressThreshold = 0.01,
    this.abilitySlots = 4,
    this.forkEveryFloors = 3,
    this.forkWaitSeconds = 45.0,
    this.boldForkLootBonus = 0.0,
    this.boldForkRarityBonus = 0,
    this.boldForkEchoBonus = 0.35,
    this.sellBonus = 1.6,
    this.chestItemChance = 0.25,
    this.onboardingFloors = 12,
    this.onboardingChestItemChance = 1.0,
    this.bossItems = 1,
    this.bigBossItems = 1,
    this.relicPityFloors = 40,
    this.percentileMin = 0.70,
    this.percentileMax = 1.00,
    this.extractionPercentilePenalty = 0.10,
    this.twoHandedRollBonus = 0.50,
    this.twoHandedChance = 0.25,
    this.maxTriggerAffixesPerItem = 1,
    this.itemPowerScale = 1.0,
    this.rarityWeights = const {
      Rarity.common: 40.0,
      Rarity.uncommon: 38.0,
      Rarity.rare: 18.0,
      Rarity.relic: 4.0,
    },
    this.affixSlotsByRarity = const {
      Rarity.common: 1,
      Rarity.uncommon: 2,
      Rarity.rare: 3,
      Rarity.relic: 4,
    },
    this.slowFraction = 0.20,
    this.shredFraction = 0.30,
    this.lifestealFraction = 0.30,
    this.rampPerSecond = 0.03,
    this.rampCap = 1.00,
    this.explosionFraction = 2.5,
    this.manaDrainPerHit = 8.0,
    this.allyHealPerSecond = 0.012,
    this.reflectFraction = 0.12,
    this.hardenPerSecond = 0.04,
    this.hardenCap = 1.50,
    this.baseHireCost = 250.0,
    this.baseTavernCandidates = 3,
    this.baseSalvageRate = 0.35,
    this.maxBuildingLevel = 8,
    this.depthGatePerLevel = 20,
    this.secondSlotLevel = 4,
    this.upgradeCostFloors = 60.0,
    this.stashSlotsBase = 40,
    this.stashSlotsPerLevel = 6,
    this.lootQualityPerLevel = 0.10,
    this.lootQuantityPerLevel = 0.06,
    this.rerollFloorPerLevel = 0.10,
    this.shardSalvageLevel = 4,
    this.shardSalvageChance = 0.25,
    this.salvageRatePerLevel = 0.15,
    this.forecastFloorsBase = 3,
    this.forecastFloorsPerLevel = 1,
    this.restHealPerLevel = 0.02,
    this.rerollCostBase = 40.0,
    this.rerollCostGrowth = 1.6,
    this.rerollRarityMultiplier = const {
      Rarity.common: 1.0,
      Rarity.uncommon: 1.5,
      Rarity.rare: 2.5,
      Rarity.relic: 4.0,
    },
    this.deepenCostBase = 120.0,
    this.deepenCostGrowth = 1.35,
    this.deepenIlvlStep = 10,
    this.shardCapacityBase = 12,
    this.shardCapacityPerLevel = 4,
  });

  final StatBlock heroBase;

  /// Эталонная частота чар: с ней сила чар превращается в урон в секунду,
  /// как урон оружия превращается в него скоростью атаки.
  ///
  /// Нужна дотам от чар. Настоящей «скорости чар» в игре нет и не планируется:
  /// частота способности задана её перезарядкой, а горению нужна одна опорная
  /// величина, иначе оно считалось бы по скорости замаха оружия — и посох с
  /// быстрым кинжалом в другой руке горел бы жарче.
  final double spellReferenceRate;

  /// Сколько держится замедление от узла «Стылая хватка».
  ///
  /// Короче типичной перезарядки способности намеренно: правило должно
  /// вознаграждать частые удары, а не превращаться в постоянный дебаф.
  final double chillSeconds;

  final double tickSeconds;
  final int wavesPerFloor;
  final int wavesPerBossFloor;
  final double restSecondsBetweenFloors;
  final double restHealFraction;
  final double waveTimeoutSeconds;
  final double stallCheckSeconds;
  final double stallProgressThreshold;

  /// Слотов способностей. Активные и пассивные конкурируют за один пул —
  /// в этом и состоит выбор (GDD §3.8).
  final int abilitySlots;

  /// Развилка на входе на каждый N-й этаж: два пути, у каждого свой
  /// модификатор (GDD §2.6). Между развилками этажи чистые.
  final int forkEveryFloors;

  /// Сколько секунд наёмник ждёт решения на развилке, прежде чем решить сам.
  ///
  /// Ждёт ОДИН раз за спуск: не дождавшись, он перестаёт останавливаться
  /// вовсе и доходит остаток по приказу. Правило выбрано из двух других,
  /// каждое из которых оказалось хуже:
  ///
  /// * таймаут на КАЖДОЙ развилке — на глубине сто их тридцать шесть, и
  ///   восьмиминутный спуск растянулся бы до получаса у любого, кто просто
  ///   закрыл приложение;
  /// * общий бюджет на весь спуск — замер показал 1 ч 40 мин простоя за
  ///   двадцать спусков, и при этом вовлечённый игрок, думающий по десять
  ///   секунд, исчерпывал бы его раньше отсутствующего.
  ///
  /// «Ждёт один раз» стоит отсутствующему игроку 45 секунд за спуск и не
  /// стоит ничего тому, кто отвечает: присутствие вознаграждается, отсутствие
  /// не наказывается.
  final double forkWaitSeconds;

  /// Прибавка к КОЛИЧЕСТВУ добычи на третьем пути. По умолчанию ноль.
  ///
  /// Ноль потому, что количество упирается в сундук: замер кампании показал
  /// его полным уже к середине, и лишние вещи уходят в переплавку, не доехав
  /// до сборки. Ручка оставлена на случай, если Хранилище перестанет быть
  /// узким местом.
  final double boldForkLootBonus;

  /// Прибавка к рангу редкости сундука на третьем пути. По умолчанию ноль.
  ///
  /// Ноль не по осторожности, а по замеру: с прибавкой в два ранга третий
  /// путь становился ВРЕДНЫМ. Редкие вещи — это реликты, а автосборка их не
  /// надевает (они меняют правила боя, это решение игрока). Сундук
  /// ограничен, и поток реликтов вытеснял из него обычные вещи, которыми
  /// наёмник и одевается: 135 этажей за двадцать контрактов против 180 без
  /// прибавки.
  ///
  /// Награда, которую некуда надеть, — это не награда.
  final int boldForkRarityBonus;

  /// Во сколько раз продажа выгоднее переплавки.
  ///
  /// Разбор добычи предлагает три исхода, и два из них должны различаться не
  /// только словом. Переплавка даёт золото И осколок — материал для кузницы;
  /// продажа осколка не даёт, зато платит больше. Без этой разницы «продать»
  /// было бы переплавкой без осколка, то есть строго худшим вариантом, а
  /// строго худший вариант — это не выбор, а лишняя кнопка.
  final double sellBonus;

  /// Доля к Эху за каждый этаж на третьем пути.
  ///
  /// Единственная прибавка сверх «наград обоих путей». Эхо выбрано потому,
  /// что оно идёт в древо и остаётся навсегда: добыча упирается в сундук,
  /// редкость — в реликты, а Эхо не упирается ни во что.
  ///
  /// Размер невелик намеренно: основную часть выигрыша даёт сама форма пути
  /// (две награды, ноль платы) — 180 этажей против 137 у приказа. Ручка
  /// добавляет к этому ещё около десяти.
  final double boldForkEchoBonus;

  final double chestItemChance;
  final int onboardingFloors;
  final double onboardingChestItemChance;
  final int bossItems;
  final int bigBossItems;
  final int relicPityFloors;
  final double percentileMin;
  final double percentileMax;
  final double extractionPercentilePenalty;
  final double twoHandedRollBonus;

  /// Доля оружия, выпадающего двуручным. Двуручник занимает оба слота рук,
  /// но получает +1 аффикс и прибавку к роллам: два слота под аффиксы против
  /// концентрированной мощи (GDD §4.1).
  final double twoHandedChance;
  final int maxTriggerAffixesPerItem;

  /// Калибровочный множитель бюджета предмета: и аффиксов, и имплицитов.
  ///
  /// Ручка, а не костыль. Значения `base` в контенте задают ОТНОШЕНИЯ между
  /// статами — сколько HP стоит столько же, сколько столько-то урона. Во
  /// сколько раз девять слотов должны быть сильнее голого героя — вопрос
  /// другой, и ответ на него измеряется балансировщиком, а не выводится.
  /// Одно число вместо правки двух десятков `base` сохраняет отношения
  /// нетронутыми при каждой перекалибровке.
  final double itemPowerScale;

  /// Веса редкости при ролле предмета.
  final Map<Rarity, double> rarityWeights;

  /// Сколько аффиксов несёт предмет каждой редкости. Редкость определяет
  /// ЧИСЛО аффиксов, а не множитель силы: иначе она входила бы в баланс
  /// вторым множителем поверх ilvl и ломала формулу стены (GDD §4.2).
  final Map<Rarity, int> affixSlotsByRarity;

  /// Черты мобов. Ни одна не стакается: три Ледяных стража в пачке дают
  /// то же замедление, что один. Иначе пачка из трёх снимает у героя 60 %
  /// скорости атаки, и один архетип определяет исход этажа.
  final double slowFraction;
  final double shredFraction;
  final double lifestealFraction;

  /// Прирост урона в секунду и его потолок для черты `rampUp`.
  final double rampPerSecond;
  final double rampCap;

  /// Во сколько УДАРОВ погибшего обходится его взрыв.
  ///
  /// От удара, а не от максимума HP: иначе толстый взрывался бы сильнее
  /// злого, и повадка читалась бы как «толстые опаснее», а не как «за
  /// площадной удар по пачке придётся заплатить».
  ///
  /// Больше единицы намеренно. Первая версия ставила 0.3 — треть одного
  /// удара, — и замер показал ровный ноль: две смерти за двухминутный бой
  /// давали меньше, чем шум. Взрыв обязан быть событием, а не поправкой:
  /// пачка из пяти «Головней», выкошенная одним ударом по области, стоит
  /// двенадцати ударов сразу.
  final double explosionFraction;

  /// Сколько маны снимает удар «разрядника». Плоско, как и сама мана.
  final double manaDrainPerHit;

  /// Долю максимума HP в секунду лечит соседям «ревун».
  final double allyHealPerSecond;

  /// Доля полученного урона, которую возвращает «отражатель».
  final double reflectFraction;

  /// На сколько за секунду растёт броня «затвердевающего» и где потолок.
  final double hardenPerSecond;
  final double hardenCap;

  final double baseHireCost;
  final int baseTavernCandidates;
  final double baseSalvageRate;
  final int maxBuildingLevel;
  final int depthGatePerLevel;

  /// Уровень Таверны, открывающий второй слот спуска.
  final int secondSlotLevel;
  final double upgradeCostFloors;

  // --- Что даёт уровень постройки -------------------------------------------
  //
  // Раньше эти числа стояли прямо в `outpost.dart`. Правка вместимости сундука
  // требовала пересборки APK, а балансировать так нельзя (`docs/02-TECH.md` §1).

  final int stashSlotsBase;
  final int stashSlotsPerLevel;
  final double lootQualityPerLevel;
  final double lootQuantityPerLevel;
  final double rerollFloorPerLevel;
  final int shardSalvageLevel;
  final double shardSalvageChance;
  final double salvageRatePerLevel;
  final int forecastFloorsBase;
  final int forecastFloorsPerLevel;
  final double restHealPerLevel;

  // --- Крафт (GDD §5.3, §6.3) -----------------------------------------------

  /// Цена реролла: `base × itemScale(ilvl) × редкость × growth^повторов`.
  ///
  /// Масштаб взят от [Curves.itemScale], а не от отдельной степени глубины,
  /// как в GDD §6.3. Дублировать показатель роста нельзя: свой множитель
  /// разошёлся бы с доходом (`goldPerFloor` тоже считается от `itemScale`),
  /// и на глубине 150 реролл стоил бы семьдесят спусков вместо одного.
  final double rerollCostBase;
  final double rerollCostGrowth;
  final Map<Rarity, double> rerollRarityMultiplier;

  /// Углубление реликта: поднимает ilvl, но не выше достигнутой глубины.
  final double deepenCostBase;
  final double deepenCostGrowth;
  final int deepenIlvlStep;

  /// Вместимость хранилища осколков.
  final int shardCapacityBase;
  final int shardCapacityPerLevel;

  factory TuningConfig.fromJson(Map<String, dynamic> root) {
    final hero = (root['hero'] as Map?)?.cast<String, dynamic>() ?? const {};
    final combat = (root['combat'] as Map?)?.cast<String, dynamic>() ?? const {};
    final loot = (root['loot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final outpost =
        (root['outpost'] as Map?)?.cast<String, dynamic>() ?? const {};
    final traits = (root['traits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final crafting =
        (root['crafting'] as Map?)?.cast<String, dynamic>() ?? const {};
    const d = TuningConfig();

    return TuningConfig(
      heroBase: StatBlock(
        maxHp: _d(hero, 'maxHp', d.heroBase.maxHp),
        hpRegen: _d(hero, 'hpRegen', d.heroBase.hpRegen),
        maxMana: _d(hero, 'maxMana', d.heroBase.maxMana),
        manaRegen: _d(hero, 'manaRegen', d.heroBase.manaRegen),
        armor: _d(hero, 'armor', d.heroBase.armor),
        attackDamage: _d(hero, 'attackDamage', d.heroBase.attackDamage),
        spellPower: _d(hero, 'spellPower', d.heroBase.spellPower),
        attackSpeed: _d(hero, 'attackSpeed', d.heroBase.attackSpeed),
        critChance: _d(hero, 'critChance', d.heroBase.critChance),
        critMulti: _d(hero, 'critMulti', d.heroBase.critMulti),
      ),
      spellReferenceRate:
          _d(combat, 'spellReferenceRate', d.spellReferenceRate),
      chillSeconds: _d(combat, 'chillSeconds', d.chillSeconds),
      tickSeconds: _d(combat, 'tickSeconds', d.tickSeconds),
      wavesPerFloor: _i(combat, 'wavesPerFloor', d.wavesPerFloor),
      wavesPerBossFloor: _i(combat, 'wavesPerBossFloor', d.wavesPerBossFloor),
      restSecondsBetweenFloors:
          _d(combat, 'restSecondsBetweenFloors', d.restSecondsBetweenFloors),
      restHealFraction: _d(combat, 'restHealFraction', d.restHealFraction),
      waveTimeoutSeconds: _d(combat, 'waveTimeoutSeconds', d.waveTimeoutSeconds),
      stallCheckSeconds: _d(combat, 'stallCheckSeconds', d.stallCheckSeconds),
      stallProgressThreshold:
          _d(combat, 'stallProgressThreshold', d.stallProgressThreshold),
      abilitySlots: _i(combat, 'abilitySlots', d.abilitySlots),
      forkEveryFloors: _i(combat, 'forkEveryFloors', d.forkEveryFloors),
      forkWaitSeconds: _d(combat, 'forkWaitSeconds', d.forkWaitSeconds),
      boldForkLootBonus:
          _d(combat, 'boldForkLootBonus', d.boldForkLootBonus),
      boldForkRarityBonus:
          _i(combat, 'boldForkRarityBonus', d.boldForkRarityBonus),
      boldForkEchoBonus:
          _d(combat, 'boldForkEchoBonus', d.boldForkEchoBonus),
      sellBonus: _d(combat, 'sellBonus', d.sellBonus),
      chestItemChance: _d(loot, 'chestItemChance', d.chestItemChance),
      onboardingFloors: _i(loot, 'onboardingFloors', d.onboardingFloors),
      onboardingChestItemChance:
          _d(loot, 'onboardingChestItemChance', d.onboardingChestItemChance),
      bossItems: _i(loot, 'bossItems', d.bossItems),
      bigBossItems: _i(loot, 'bigBossItems', d.bigBossItems),
      relicPityFloors: _i(loot, 'relicPityFloors', d.relicPityFloors),
      percentileMin: _d(loot, 'percentileMin', d.percentileMin),
      percentileMax: _d(loot, 'percentileMax', d.percentileMax),
      extractionPercentilePenalty: _d(
          loot, 'extractionPercentilePenalty', d.extractionPercentilePenalty),
      twoHandedRollBonus: _d(loot, 'twoHandedRollBonus', d.twoHandedRollBonus),
      twoHandedChance: _d(loot, 'twoHandedChance', d.twoHandedChance),
      maxTriggerAffixesPerItem:
          _i(loot, 'maxTriggerAffixesPerItem', d.maxTriggerAffixesPerItem),
      itemPowerScale: _d(loot, 'itemPowerScale', d.itemPowerScale),
      rarityWeights: _rarityMap(loot['rarityWeights'], d.rarityWeights),
      affixSlotsByRarity: _rarityIntMap(
          loot['affixSlotsByRarity'], d.affixSlotsByRarity),
      slowFraction: _d(traits, 'slowFraction', d.slowFraction),
      shredFraction: _d(traits, 'shredFraction', d.shredFraction),
      lifestealFraction: _d(traits, 'lifestealFraction', d.lifestealFraction),
      rampPerSecond: _d(traits, 'rampPerSecond', d.rampPerSecond),
      explosionFraction:
          _d(traits, 'explosionFraction', d.explosionFraction),
      manaDrainPerHit: _d(traits, 'manaDrainPerHit', d.manaDrainPerHit),
      allyHealPerSecond:
          _d(traits, 'allyHealPerSecond', d.allyHealPerSecond),
      reflectFraction: _d(traits, 'reflectFraction', d.reflectFraction),
      hardenPerSecond: _d(traits, 'hardenPerSecond', d.hardenPerSecond),
      hardenCap: _d(traits, 'hardenCap', d.hardenCap),
      rampCap: _d(traits, 'rampCap', d.rampCap),
      baseHireCost: _d(outpost, 'baseHireCost', d.baseHireCost),
      baseTavernCandidates:
          _i(outpost, 'baseTavernCandidates', d.baseTavernCandidates),
      baseSalvageRate: _d(outpost, 'baseSalvageRate', d.baseSalvageRate),
      maxBuildingLevel: _i(outpost, 'maxBuildingLevel', d.maxBuildingLevel),
      depthGatePerLevel: _i(outpost, 'depthGatePerLevel', d.depthGatePerLevel),
      secondSlotLevel: _i(outpost, 'secondSlotLevel', d.secondSlotLevel),
      upgradeCostFloors: _d(outpost, 'upgradeCostFloors', d.upgradeCostFloors),
      stashSlotsBase: _i(outpost, 'stashSlotsBase', d.stashSlotsBase),
      stashSlotsPerLevel:
          _i(outpost, 'stashSlotsPerLevel', d.stashSlotsPerLevel),
      lootQualityPerLevel:
          _d(outpost, 'lootQualityPerLevel', d.lootQualityPerLevel),
      lootQuantityPerLevel:
          _d(outpost, 'lootQuantityPerLevel', d.lootQuantityPerLevel),
      rerollFloorPerLevel:
          _d(outpost, 'rerollFloorPerLevel', d.rerollFloorPerLevel),
      shardSalvageLevel: _i(outpost, 'shardSalvageLevel', d.shardSalvageLevel),
      shardSalvageChance:
          _d(outpost, 'shardSalvageChance', d.shardSalvageChance),
      salvageRatePerLevel:
          _d(outpost, 'salvageRatePerLevel', d.salvageRatePerLevel),
      forecastFloorsBase:
          _i(outpost, 'forecastFloorsBase', d.forecastFloorsBase),
      forecastFloorsPerLevel:
          _i(outpost, 'forecastFloorsPerLevel', d.forecastFloorsPerLevel),
      restHealPerLevel: _d(outpost, 'restHealPerLevel', d.restHealPerLevel),
      rerollCostBase: _d(crafting, 'rerollCostBase', d.rerollCostBase),
      rerollCostGrowth: _d(crafting, 'rerollCostGrowth', d.rerollCostGrowth),
      rerollRarityMultiplier: _rarityMap(
          crafting['rerollRarityMultiplier'], d.rerollRarityMultiplier),
      deepenCostBase: _d(crafting, 'deepenCostBase', d.deepenCostBase),
      deepenCostGrowth: _d(crafting, 'deepenCostGrowth', d.deepenCostGrowth),
      deepenIlvlStep: _i(crafting, 'deepenIlvlStep', d.deepenIlvlStep),
      shardCapacityBase: _i(crafting, 'shardCapacityBase', d.shardCapacityBase),
      shardCapacityPerLevel:
          _i(crafting, 'shardCapacityPerLevel', d.shardCapacityPerLevel),
    );
  }

  static double _d(Map<String, dynamic> j, String k, double fallback) =>
      (j[k] as num?)?.toDouble() ?? fallback;

  static int _i(Map<String, dynamic> j, String k, int fallback) =>
      (j[k] as num?)?.toInt() ?? fallback;

  static Map<Rarity, double> _rarityMap(
      Object? raw, Map<Rarity, double> fallback) {
    if (raw is! Map) return fallback;
    final out = <Rarity, double>{};
    for (final r in Rarity.values) {
      final v = raw[r.name];
      if (v is num) out[r] = v.toDouble();
    }
    return out.isEmpty ? fallback : out;
  }

  static Map<Rarity, int> _rarityIntMap(
      Object? raw, Map<Rarity, int> fallback) {
    if (raw is! Map) return fallback;
    final out = <Rarity, int>{};
    for (final r in Rarity.values) {
      final v = raw[r.name];
      if (v is num) out[r] = v.toInt();
    }
    return out.isEmpty ? fallback : out;
  }
}

/// Геймплейные константы.
///
/// Источник истины — `assets/content/balance.json`. Ни одного числа баланса
/// не должно быть зашито в `.dart`: иначе каждая правка коэффициента требует
/// пересборки APK и балансировка встаёт (`docs/02-TECH.md` §1).
class Tuning {
  Tuning._();

  static TuningConfig _config = const TuningConfig();

  static TuningConfig get config => _config;

  static void configure(TuningConfig next) => _config = next;

  /// «Голый» наёмник ранга Оборванец без снаряжения и без древа Эха.
  ///
  /// Броня ненулевая намеренно: при armor = 0 формула митигации вырождается.
  ///
  /// hpRegen намеренно МАЛЕНЬКИЙ. Лечение реген-статом равно `реген × время
  /// боя`, а время боя растёт почти с той же скоростью, что и урон мобов —
  /// поэтому большой реген почти идеально гасит кривую сложности. Замер: при
  /// hpRegen = 2.0 удлинение рана уезжало с 20 до 95 этажей за удвоение вместо
  /// ровных 40. Основное восстановление вынесено в отдых между этажами.
  static StatBlock get heroBase => _config.heroBase;

  /// Шаг симуляции. 10 Гц достаточно для кулдаунов от 3 с и дотов.
  static double get tickSeconds => _config.tickSeconds;

  static int get wavesPerFloor => _config.wavesPerFloor;
  static int get wavesPerBossFloor => _config.wavesPerBossFloor;
  static double get restSecondsBetweenFloors => _config.restSecondsBetweenFloors;

  /// Доля максимального HP, восстанавливаемая на отдыхе.
  ///
  /// Не производная от hpRegen намеренно: так этажи становятся почти
  /// независимыми испытаниями, а смерть наступает от того, что конкретный
  /// этаж непроходим. Это ровно та модель, которую предполагает
  /// аналитический офлайн-расчёт (GDD §9.1).
  static double get restHealFraction => _config.restHealFraction;

  /// Предохранитель, а НЕ механика: абсолютная константа против
  /// экспоненциальных кривых всегда рано или поздно становится тем, что
  /// обрывает ран вместо смерти. Реальная граница — по отсутствию прогресса.
  static double get waveTimeoutSeconds => _config.waveTimeoutSeconds;
  static double get stallCheckSeconds => _config.stallCheckSeconds;
  static double get stallProgressThreshold => _config.stallProgressThreshold;
  static double get spellReferenceRate => _config.spellReferenceRate;
  static double get chillSeconds => _config.chillSeconds;
  static int get abilitySlots => _config.abilitySlots;
  static int get forkEveryFloors => _config.forkEveryFloors;
  static double get forkWaitSeconds => _config.forkWaitSeconds;
  static double get boldForkLootBonus => _config.boldForkLootBonus;
  static int get boldForkRarityBonus => _config.boldForkRarityBonus;
  static double get boldForkEchoBonus => _config.boldForkEchoBonus;
  static double get sellBonus => _config.sellBonus;

  // --- Снаряжение -----------------------------------------------------------

  /// 2 руки, шлем, доспех, перчатки, ботинки, 2 кольца, амулет (GDD §4.1).
  static const int gearSlots = 9;

  /// Сколько слотов заполнено на старте нового аккаунта (оружие + доспех).
  static const int starterGearSlots = 2;

  /// Вклад синтетического снаряжения Фазы 1 в силу героя.
  /// Используется только там, где настоящих предметов ещё нет.
  static const double gearWeight = 1.0;

  // --- Дроп (GDD §4.4) ------------------------------------------------------

  static double get chestItemChance => _config.chestItemChance;
  static int get onboardingFloors => _config.onboardingFloors;
  static double get onboardingChestItemChance =>
      _config.onboardingChestItemChance;
  static int get bossItems => _config.bossItems;
  static int get bigBossItems => _config.bigBossItems;
  static int get relicPityFloors => _config.relicPityFloors;

  /// Диапазон перцентиля ролла. Осколок хранит перцентиль, а не значение —
  /// поэтому 96-й перцентиль остаётся ценным на любой глубине (GDD §5.3).
  static double get percentileMin => _config.percentileMin;
  static double get percentileMax => _config.percentileMax;

  /// Плата за извлечение осколка, в пунктах перцентиля. Гарантирует, что
  /// охота за новыми роллами не прекращается.
  static double get extractionPercentilePenalty =>
      _config.extractionPercentilePenalty;

  static double get twoHandedRollBonus => _config.twoHandedRollBonus;
  static double get twoHandedChance => _config.twoHandedChance;

  /// Потолок триггеров на предмет. Девять слотов без него дали бы
  /// до 18 активных триггеров и комбинаторный хаос.
  static int get maxTriggerAffixesPerItem => _config.maxTriggerAffixesPerItem;

  // --- Черты мобов ----------------------------------------------------------

  static double get slowFraction => _config.slowFraction;
  static double get shredFraction => _config.shredFraction;
  static double get lifestealFraction => _config.lifestealFraction;
  static double get rampPerSecond => _config.rampPerSecond;
  static double get explosionFraction => _config.explosionFraction;
  static double get manaDrainPerHit => _config.manaDrainPerHit;
  static double get allyHealPerSecond => _config.allyHealPerSecond;
  static double get reflectFraction => _config.reflectFraction;
  static double get hardenPerSecond => _config.hardenPerSecond;
  static double get hardenCap => _config.hardenCap;
  static double get rampCap => _config.rampCap;

  static double get itemPowerScale => _config.itemPowerScale;

  static Map<Rarity, double> get rarityWeights => _config.rarityWeights;
  static Map<Rarity, int> get affixSlotsByRarity => _config.affixSlotsByRarity;

  // --- Наёмники и Застава ---------------------------------------------------

  static double get baseHireCost => _config.baseHireCost;
  static int get baseTavernCandidates => _config.baseTavernCandidates;
  static double get baseSalvageRate => _config.baseSalvageRate;
  static int get maxBuildingLevel => _config.maxBuildingLevel;
  static int get depthGatePerLevel => _config.depthGatePerLevel;
  static int get secondSlotLevel => _config.secondSlotLevel;
  static double get upgradeCostFloors => _config.upgradeCostFloors;

  static int get stashSlotsBase => _config.stashSlotsBase;
  static int get stashSlotsPerLevel => _config.stashSlotsPerLevel;
  static double get lootQualityPerLevel => _config.lootQualityPerLevel;
  static double get lootQuantityPerLevel => _config.lootQuantityPerLevel;
  static double get rerollFloorPerLevel => _config.rerollFloorPerLevel;
  static int get shardSalvageLevel => _config.shardSalvageLevel;
  static double get shardSalvageChance => _config.shardSalvageChance;
  static double get salvageRatePerLevel => _config.salvageRatePerLevel;
  static int get forecastFloorsBase => _config.forecastFloorsBase;
  static int get forecastFloorsPerLevel => _config.forecastFloorsPerLevel;
  static double get restHealPerLevel => _config.restHealPerLevel;

  static double get rerollCostBase => _config.rerollCostBase;
  static double get rerollCostGrowth => _config.rerollCostGrowth;
  static Map<Rarity, double> get rerollRarityMultiplier =>
      _config.rerollRarityMultiplier;
  static double get deepenCostBase => _config.deepenCostBase;
  static double get deepenCostGrowth => _config.deepenCostGrowth;
  static int get deepenIlvlStep => _config.deepenIlvlStep;
  static int get shardCapacityBase => _config.shardCapacityBase;
  static int get shardCapacityPerLevel => _config.shardCapacityPerLevel;
}
