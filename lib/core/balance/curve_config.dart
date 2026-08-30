/// Константы кривых. Значения по умолчанию совпадают с `assets/content/balance.json`
/// и существуют только чтобы ядро оставалось работоспособным без загруженного
/// контента (тесты формул, ранний старт приложения).
///
/// Источник истины — JSON. Правка коэффициента не должна требовать пересборки.
class CurveConfig {
  const CurveConfig({
    this.tau = 30.0,
    this.mobHpGrowth = 1.06,
    this.mobDpsGrowth = 1.08,
    this.mobHpBase = 30.0,
    this.mobDpsBase = 4.0,
    this.itemGrowth = 1.075,
    this.armorConstantBase = 60.0,
    this.armorDrCap = 0.75,
    this.resistCap = 75.0,
    this.echoBase = 5.0,
    this.echoGrowth = 1.055,
    this.goldBase = 10.0,
    this.brandMobStatsPerRank = 0.25,
    this.brandLootPerRank = 0.12,
    this.brandEchoPerRank = 0.12,
    this.brandMaxRank = 5,
    this.brandUnlockDepths = const [40, 60, 80, 100, 125],
    this.brandProofDepth = 120,
    this.hireScaleFromDepth = 85,
    this.startDepthShare = 0.30,
    this.echoNodeBaseCost = 30.0,
    this.echoNodeCostGrowth = 2.6,
    this.passivePointPerFloors = 5,
    this.passivePointCap = 60,
  });

  final double tau;
  final double mobHpGrowth;
  final double mobDpsGrowth;
  final double mobHpBase;
  final double mobDpsBase;

  /// Во сколько раз сильнее предмет на этаж глубже.
  ///
  /// РУЧКА, а не производная. Раньше выводилась из
  /// [targetRunExtensionFloors]; вывод опирался на то, что наёмник подбирает
  /// снаряжение прямо в спуске, и после отмены подмены перестал работать —
  /// см. `Curves.itemGrowth`.
  final double itemGrowth;

  final double armorConstantBase;
  final double armorDrCap;
  final double resistCap;
  final double echoBase;
  final double echoGrowth;
  final double goldBase;
  final double brandMobStatsPerRank;
  final double brandLootPerRank;
  final double brandEchoPerRank;
  final int brandMaxRank;

  /// Глубины, на которых открываются ранги Клейма (GDD §2.5). Ранг N
  /// доступен, когда рекорд достиг `brandUnlockDepths[N - 1]`.
  final List<int> brandUnlockDepths;

  /// Глубина, которую надо взять НА РАНГЕ, чтобы открыть следующий.
  ///
  /// Ранги выше списка глубин открываются делом, а не рекордом: глубина
  /// выходит на плато, и привязать к ней лестницу эндгейма нельзя.
  final int brandProofDepth;

  /// Глубина, с которой задаток наёмника растёт вместе с доходом.
  /// Ниже неё цена найма ровно та, что измерена для первых ранов.
  final int hireScaleFromDepth;

  /// Какую долю рекорда наёмник проходит без боя — «спуск по верёвке».
  ///
  /// Первые этажи каждого рана бесплатны по построению: снаряжение собрано
  /// под сороковой этаж, а бьётся оно на пятом. Замер `--hp` показал, что
  /// на 64 % этажей здоровье не опускалось ниже 90 % — то есть две трети
  /// рана полоска стояла. Начинать глубже дешевле, чем ослаблять героя:
  /// глубина почти не меняется, а формальная часть исчезает.
  final double startDepthShare;

  /// Цена узла древа Эха: `base * growth^(куплено / 4)`.
  final double echoNodeBaseCost;
  final double echoNodeCostGrowth;

  /// Дерево пассивок: сколько этажей рекорда стоит одно очко и где потолок.
  ///
  /// Очки даёт РЕКОРД, а не сумма спусков: прокачка подтверждает, что игрок
  /// там был, и не копится от повторов уже пройденного.
  final int passivePointPerFloors;
  final int passivePointCap;

  factory CurveConfig.fromJson(Map<String, dynamic> j) => CurveConfig(
        tau: _d(j, 'tau', 30.0),
        mobHpGrowth: _d(j, 'mobHpGrowth', 1.06),
        mobDpsGrowth: _d(j, 'mobDpsGrowth', 1.08),
        mobHpBase: _d(j, 'mobHpBase', 30.0),
        mobDpsBase: _d(j, 'mobDpsBase', 4.0),
        itemGrowth: _d(j, 'itemGrowth', 1.075),
        armorConstantBase: _d(j, 'armorConstantBase', 60.0),
        armorDrCap: _d(j, 'armorDrCap', 0.75),
        resistCap: _d(j, 'resistCap', 75.0),
        echoBase: _d(j, 'echoBase', 5.0),
        echoGrowth: _d(j, 'echoGrowth', 1.055),
        goldBase: _d(j, 'goldBase', 10.0),
        brandMobStatsPerRank: _d(j, 'brandMobStatsPerRank', 0.25),
        brandLootPerRank: _d(j, 'brandLootPerRank', 0.12),
        brandEchoPerRank: _d(j, 'brandEchoPerRank', 0.12),
        brandMaxRank: _i(j, 'brandMaxRank', 5),
        brandUnlockDepths: _ints(j, 'brandUnlockDepths',
            const [40, 60, 80, 100, 125]),
        brandProofDepth: _i(j, 'brandProofDepth', 120),
        hireScaleFromDepth: _i(j, 'hireScaleFromDepth', 85),
        startDepthShare: _d(j, 'startDepthShare', 0.30),
        echoNodeBaseCost: _d(j, 'echoNodeBaseCost', 30.0),
        echoNodeCostGrowth: _d(j, 'echoNodeCostGrowth', 2.6),
        passivePointPerFloors: _i(j, 'passivePointPerFloors', 5),
        passivePointCap: _i(j, 'passivePointCap', 60),
      );

  static List<int> _ints(
      Map<String, dynamic> j, String k, List<int> fallback) {
    final raw = j[k];
    if (raw is! List || raw.isEmpty) return fallback;
    return [
      for (final v in raw)
        if (v is num) v.round(),
    ];
  }

  static double _d(Map<String, dynamic> j, String k, double fallback) =>
      (j[k] as num?)?.toDouble() ?? fallback;

  static int _i(Map<String, dynamic> j, String k, int fallback) =>
      (j[k] as num?)?.toInt() ?? fallback;
}
