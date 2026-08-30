import 'dart:math' as math;
import 'dart:typed_data';

import 'curve_config.dart';

/// Все кривые прогрессии игры.
///
/// Единственный источник истины: и боевая симуляция, и офлайн-модель обязаны
/// читать отсюда. Продублированная в двух местах формула — гарантированное
/// расхождение онлайна и офлайна, а это причина №1 смерти проектов жанра
/// (`docs/01-ANALYSIS.md` §3).
class Curves {
  Curves._();

  /// Активная конфигурация. Значения по умолчанию дублируют balance.json,
  /// чтобы ядро работало и без загруженного контента (тесты формул).
  static CurveConfig _config = const CurveConfig();

  static CurveConfig get config => _config;

  /// Применяет конфигурацию из контента и сбрасывает всё производное.
  ///
  /// Производные величины (itemGrowth, таблица d_eff) обязаны пересчитаться
  /// здесь и только здесь: если хоть одна из них останется от прошлого
  /// конфига, симуляция и офлайн-модель начнут расходиться молча.
  static void configure(CurveConfig next) {
    _config = next;
    _table = null;
  }

  // --- Мягкий разгон (GDD §2.2) ---------------------------------------------

  /// Длина мягкого разгона в этажах. Читается буквально: первые `tau` этажей
  /// кривая почти линейна, дальше — чистая экспонента, сдвинутая на `tau`.
  static double get tau => _config.tau;

  // --- Кривые мобов (GDD §2.2) ----------------------------------------------

  static double get mobHpGrowth => _config.mobHpGrowth;
  static double get mobDpsGrowth => _config.mobDpsGrowth;
  static double get mobHpBase => _config.mobHpBase;
  static double get mobDpsBase => _config.mobDpsBase;

  // --- Рост силы предмета (GDD §2.3) ----------------------------------------

  /// Вывод (для проверки руками — ошибка здесь стоит дороже всего):
  ///
  ///   T(d)   = H(d)/P(d)        = (H0/P0·m)·(a/g)^d      время этажа
  ///   D(d)   = M(d)·T(d)        = (M0·H0/P0·m)·(ab/g)^d  урон за этаж
  ///   E(d)   = E0·m·g^d                                   EHP героя
  ///   D/E    ∝ (1/m²)·(ab/g²)^d
  ///
  /// Множитель силы билда `m` входит В КВАДРАТЕ: он поднимает и урон (через
  /// TTK), и EHP. Значит удвоение билда делит риск на 4, а не на 2, и
  ///
  ///   Δd = ln4 / lnK,  откуда  K = 4^(1/Δd)  и  g = sqrt(a·b / 4^(1/Δd)).
  ///
  /// Ранняя версия документа делила на 2 — ошибка ровно вдвое, найденная
  /// прогоном `sim_cli --wall`. Ради этого инструмент и писался первым.
  ///
  /// ## Почему это больше не производная
  ///
  /// Вывод выше держался на `g^d` в силе героя: сила росла ВНУТРИ спуска,
  /// потому что наёмник подбирал найденное. Он перестал (см. §4.4.1 GDD), и
  /// формула сломалась не приблизительно, а качественно: при любом
  /// положительном Δd она даёт
  ///
  ///     g = sqrt(a·b / 4^(1/Δd))  <  sqrt(a·b)
  ///
  /// а условие того, что добыча ДВИГАЕТ прогресс, — ровно обратное.
  /// Снаряжение, найденное на глубине D, даёт следующему спуску глубину
  /// `D · 2·ln(g)/ln(a·b)`; чтобы это было больше D, нужно `g > sqrt(a·b)`.
  /// Старая формула не может этого дать никогда, и цикл «нашёл вещь —
  /// прошёл дальше» переставал быть двигателем игры: замер показывал
  /// множитель 0.86 — снаряжение с сотого этажа хватало на восемьдесят
  /// шестой, а вперёд игру тянули только деревья и Застава.
  ///
  /// Поэтому `g` — ручка, и у неё два ограничения, оба проверяются
  /// валидатором контента:
  ///
  ///     sqrt(a·b) < g        добыча двигает прогресс
  ///     g < b                спуск обрывается смертью, а не таймаутом
  ///
  /// Вместе они выполнимы, только если **a < b**: HP мобов растёт медленнее
  /// их урона. Обратное (a > b) означает, что этажи становятся долгими
  /// быстрее, чем опасными, и любое снаряжение отстаёт по определению.
  static double get itemGrowth => _config.itemGrowth;

  /// K = a·b / g². Риск смерти растёт как K^d_eff — при силе сборки,
  /// растущей внутри спуска. Сейчас она не растёт, и величина осталась
  /// только для сравнения со старой моделью.
  static double get wallConstant =>
      mobHpGrowth * mobDpsGrowth / (itemGrowth * itemGrowth);

  /// Удлинение спуска за удвоение силы сборки.
  ///
  /// Сила внутри спуска постоянна, поэтому риск растёт как `(a·b)^d`, а
  /// удвоение сборки делит его на четыре: `Δd = ln4 / ln(a·b)`. Кривая мобов
  /// — единственное, чем это настраивается.
  static double get runExtensionPerDoubling =>
      2.0 * math.ln2 / math.log(mobHpGrowth * mobDpsGrowth);

  /// Во сколько раз глубже уводит снаряжение, добытое на глубине D.
  ///
  /// Больше единицы — цикл «нашёл вещь — прошёл дальше» тянет игру вперёд
  /// сам. Меньше — добыча отстаёт, и вперёд тянут только деревья.
  static double get lootLoopGain =>
      2.0 * math.log(itemGrowth) / math.log(mobHpGrowth * mobDpsGrowth);

  /// Скорость роста времени этажа ВНУТРИ одного спуска.
  ///
  /// Ровно `a`: сила сборки внутри спуска постоянна (наёмник не
  /// переодевается), поэтому время этажа растёт со скоростью HP мобов и
  /// ничем не компенсируется. Прежняя формула `a/g` вычитала рост
  /// снаряжения — того самого, которое наёмник подбирал по дороге, — и после
  /// отмены подмены давала число меньше единицы: выходило, что этажи с
  /// глубиной УСКОРЯЮТСЯ, и предупреждение о стене исчезало.
  static double get floorTimeGrowth => mobHpGrowth;

  /// Что обрывает ран — смерть или «этаж не проходится за разумное время».
  ///
  /// Порог ровно один: g против [mobDpsGrowth].
  ///   g < 1.11 — снаряжение отстаёт от урона мобов, герой ГИБНЕТ.  ✅ тезис
  ///   g > 1.11 — снаряжение обгоняет урон мобов, герой не гибнет, а
  ///              упирается в бесконечно медленные этажи. Прести́ж ломается.
  ///
  /// Это выведенное следствие, а не пожелание: при g > b риск растёт медленнее
  /// времени, и таймаут волны всегда наступает раньше смерти.
  static bool get deathEndsRuns => itemGrowth < mobDpsGrowth;

  /// Во сколько раз вырастает время этажа за последние [floors] этажей рана.
  /// Это и есть предупреждение игроку о приближении стены (GDD §2.4).
  static double slowdownOver(int floors) =>
      math.pow(floorTimeGrowth, floors).toDouble();

  // --- Броня (GDD §3.3) -----------------------------------------------------

  static double get armorConstantBase => _config.armorConstantBase;
  static double get resistCap => _config.resistCap;

  /// Кап снижения урона бронёй.
  ///
  /// Без него формула A/(A+K) даёт ВОЗРАСТАЮЩУЮ отдачу, пока A мало: удвоение
  /// брони почти удваивает эффективный запас прочности. В итоге сила билда
  /// входит в риск не квадратом, а кубом, и удлинение рана перестаёт быть
  /// константой — замер `sim_cli --wall` показал разброс 20…90 этажей за
  /// удвоение вместо ровных 40. Кап возвращает предсказуемость.
  static double get armorDrCap => _config.armorDrCap;

  // --- Эхо (GDD §8.2) -------------------------------------------------------

  static double get echoBase => _config.echoBase;
  static double get echoGrowth => _config.echoGrowth;

  // --- Золото (GDD §6) ------------------------------------------------------

  static double get goldBase => _config.goldBase;

  // --- Клеймо Бездны (GDD §2.5) ---------------------------------------------

  static double get brandMobStatsPerRank => _config.brandMobStatsPerRank;

  /// Цена узла древа Эха.
  static double get echoNodeBaseCost => _config.echoNodeBaseCost;
  static double get echoNodeCostGrowth => _config.echoNodeCostGrowth;

  /// Очки дерева пассивок за достигнутую глубину.
  ///
  /// Считается от РЕКОРДА: очко подтверждает, что игрок там был. Считать от
  /// суммы спусков значило бы платить за повторение уже пройденного, а это
  /// ровно то, чего idle-игре надо избегать.
  static int passivePoints(int maxDepthEver) {
    if (maxDepthEver <= 0) return 0;
    final per = _config.passivePointPerFloors;
    if (per <= 0) return 0;

    final earned = maxDepthEver ~/ per;
    return earned > _config.passivePointCap ? _config.passivePointCap : earned;
  }

  /// Потолок очков дерева пассивок.
  static int get passivePointCap => _config.passivePointCap;

  /// Сколько этажей рекорда стоит одно очко.
  static int get passivePointPerFloors => _config.passivePointPerFloors;

  /// Наибольший ранг Клейма, открытый рекордом [maxDepthEver] (GDD §2.5).
  ///
  /// Клеймо — добровольная сложность, и открывается она достижением, а не
  /// покупкой: ранг подтверждает, что игрок там уже был. Это правило работает
  /// до конца списка глубин; дальше открывает не рекорд, а доказательство —
  /// см. `PlayerProfile.brandRankUnlocked`.
  static int brandRankUnlocked(int maxDepthEver) {
    final depths = _config.brandUnlockDepths;
    var rank = 0;
    for (var i = 0; i < depths.length && i < _config.brandMaxRank; i++) {
      if (maxDepthEver >= depths[i]) rank = i + 1;
    }
    return rank;
  }

  /// Глубины, на которых открываются ранги «за рекорд».
  ///
  /// Наружу — тестам и экрану: список живёт в контенте и двигается вместе с
  /// остальными кривыми, и повторять его числами где-то ещё значит завести
  /// второй источник истины.
  static List<int> get brandUnlockDepths =>
      List.unmodifiable(_config.brandUnlockDepths);

  /// Ранги, которые открываются глубиной. Дальше начинается лестница.
  static int get brandRanksByDepth {
    final byList = _config.brandUnlockDepths.length;
    return byList < _config.brandMaxRank ? byList : _config.brandMaxRank;
  }

  /// Какую глубину надо взять НА РАНГЕ, чтобы открыть следующий.
  static int get brandProofDepth => _config.brandProofDepth;
  static int get hireScaleFromDepth => _config.hireScaleFromDepth;
  static double get startDepthShare => _config.startDepthShare;

  /// С какого этажа начинается спуск при рекорде [maxDepthEver].
  ///
  /// Верёвка спущена до доли рекорда: пройденное однажды не надо проходить
  /// заново — там нечего искать и некому сопротивляться. Дальше первого
  /// этажа верёвка появляется не сразу: пока рекорда нет, спускаются пешком.
  static int startDepth(int maxDepthEver) {
    final start = (maxDepthEver * startDepthShare).floor();
    return start < 1 ? 1 : start;
  }

  /// Глубина, на которой откроется следующий ранг. `null` — открыто всё.
  static int? brandNextUnlockDepth(int maxDepthEver) {
    final depths = _config.brandUnlockDepths;
    for (var i = 0; i < depths.length && i < _config.brandMaxRank; i++) {
      if (maxDepthEver < depths[i]) return depths[i];
    }
    return null;
  }
  static double get brandLootPerRank => _config.brandLootPerRank;
  static double get brandEchoPerRank => _config.brandEchoPerRank;
  static int get brandMaxRank => _config.brandMaxRank;

  // --- Таблица эффективной глубины ------------------------------------------

  static const int _tableSize = 2001;
  static Float64List? _table;

  static Float64List _buildTable() {
    final t = Float64List(_tableSize);
    for (var d = 0; d < _tableSize; d++) {
      t[d] = _dEffExact(d.toDouble());
    }
    return t;
  }

  static double _dEffExact(double d) => d - tau * (1.0 - math.exp(-d / tau));

  /// d_eff(d) = d − τ(1 − e^(−d/τ))
  ///
  /// Читается из предпосчитанной таблицы — не ради скорости, а чтобы симуляция
  /// и офлайн-модель гарантированно получали побитово одно и то же число.
  static double dEff(int depth) {
    if (depth <= 0) return 0.0;
    if (depth < _tableSize) return (_table ??= _buildTable())[depth];
    // За таблицей экспонента вырождается: d_eff ≈ d − τ.
    return _dEffExact(depth.toDouble());
  }

  // --- Производные величины -------------------------------------------------

  /// HP одного «эталонного» моба на глубине [depth], без учёта архетипа.
  static double mobHp(int depth) =>
      mobHpBase * math.pow(mobHpGrowth, dEff(depth)).toDouble();

  /// DPS одного «эталонного» моба на глубине [depth], без учёта архетипа.
  static double mobDps(int depth) =>
      mobDpsBase * math.pow(mobDpsGrowth, dEff(depth)).toDouble();

  /// Множитель силы предмета уровня [ilvl].
  ///
  /// Масштабируется по d_eff, а не по сырой глубине — иначе в зоне мягкого
  /// разгона снаряжение обгоняло бы мобов и формула стены (§2.3) не сходилась.
  static double itemScale(int ilvl) =>
      math.pow(itemGrowth, dEff(ilvl)).toDouble();

  /// Знаменатель формулы брони.
  ///
  /// Растёт со скоростью снаряжения, а не урона мобов: тогда доля снижаемого
  /// урона зависит только от того, сколько брони игрок вложил в билд, и не
  /// плывёт сама по себе с глубиной. Привязка к mobDpsGrowth делала героя
  /// медленно, но неуклонно танковее — на длинной дистанции это ломало стену.
  static double armorConstant(int depth) =>
      armorConstantBase * math.pow(itemGrowth, dEff(depth)).toDouble();

  /// Доля урона, снимаемая бронёй [armor] на глубине [depth].
  static double armorMitigation(double armor, int depth) {
    if (armor <= 0.0) return 0.0;
    final raw = armor / (armor + armorConstant(depth));
    return raw > armorDrCap ? armorDrCap : raw;
  }

  /// Множитель статов мобов от ранга Клейма Бездны.
  static double brandMobMultiplier(int rank) =>
      1.0 + brandMobStatsPerRank * rank.clamp(0, brandMaxRank);

  /// эхо = floor(5 × 1.055^maxDepth) × (1 + 0.12 × ранг) × (1 + бонусы древа)
  static int echo(int maxDepth, {int brandRank = 0, double treeBonus = 0.0}) {
    if (maxDepth <= 0) return 0;
    final raw = echoBase * math.pow(echoGrowth, maxDepth).toDouble();
    final withBrand = raw * (1.0 + brandEchoPerRank * brandRank);
    return (withBrand * (1.0 + treeBonus)).floor();
  }

  /// Во сколько раз дороже стал задаток наёмника на рекорде [maxDepthEver].
  ///
  /// Доход за ран растёт как [itemScale] — экспоненциально по глубине, — а все
  /// стоки конечны: Застава достраивается, древо Эха выкупается, реролл
  /// упирается в потолок ilvl. Замер на 60 ранов показал итог: 935 миллионов
  /// золота, которые некуда деть. Задаток — сток, который растёт вместе с
  /// доходом по построению, а не ещё один потолок.
  ///
  /// Ниже [hireScaleFromDepth] множитель равен единице: ранняя цена
  /// измерена и не двигается. Оборванец не дорожает никогда — иначе игрок,
  /// у которого не осталось ни наёмника, ни золота, не мог бы сделать ход.
  static double hireCostScale(int maxDepthEver) => math.max(
        1.0,
        itemScale(maxDepthEver) / itemScale(hireScaleFromDepth),
      );

  /// Золото за этаж. Масштабируется как сила предмета, чтобы цены Заставы
  /// и рероллов оставались соизмеримыми с доходом на любой глубине.
  static double goldPerFloor(int depth, {int brandRank = 0}) =>
      goldBase * itemScale(depth) * (1.0 + brandLootPerRank * brandRank);
}
