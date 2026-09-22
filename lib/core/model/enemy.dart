import '../balance/curves.dart';
import '../sim/rng.dart';
import 'grammar.dart';
import 'tags.dart';

/// Врождённая особенность моба. Закрытый список: черта, которую симуляция не
/// читает, — это описание в JSON, а не механика.
enum EnemyTrait {
  /// Замедляет героя. Точка приложения — скорость атаки.
  slowsHero,

  /// Срезает сопротивления героя на время.
  shredResists,

  /// Лечится от нанесённого урона.
  lifesteal,

  /// Разгоняется по ходу боя. Опасен затяжной волной, а не первым ударом.
  rampUp,

  /// Взрывается при смерти. Меняет решение «добивать ли пачку разом»:
  /// выкосить четверых одним ударом по области стоит четырёх взрывов.
  explodesOnDeath,

  /// Снимает ману при ударе. Бьёт по сборкам на активках и не трогает тех,
  /// кто живёт автоатакой, — первая повадка, которая различает сборки.
  drainsMana,

  /// Лечит соседей по волне. Пока он жив, пачка не кончается.
  healsAllies,

  /// Возвращает часть полученного урона. Наказывает частые слабые удары
  /// сильнее, чем редкие тяжёлые.
  reflects,

  /// Броня растёт по ходу боя — зеркало [rampUp] для защиты. Затянуть с ним
  /// значит уже не убить.
  hardens,
}

/// Вид умения стража. Закрытый список по той же причине, что и повадки:
/// умение, которое бой не читает, — это строка в JSON, а не механика.
enum GuardianSkillKind {
  /// Тяжёлый удар после замаха: `power` ударов стража разом.
  slam,

  /// Горение на герое: `power` ударов стража в секунду, `duration` секунд.
  /// Броня его не держит — только сопротивление.
  burn,

  /// Оглушение: `duration` секунд герой не бьёт и не кастует. `power` — удар,
  /// которым оно наносится (ноль — без урона).
  stun,

  /// Немота: `duration` секунд герой не кастует, и `power` доли маны сгорает.
  /// Бьёт сборку на активках и не трогает ту, что живёт оружием.
  silence,

  /// Уязвимость: сопротивления героя ниже на `power` на `duration` секунд.
  expose,

  /// Щит: страж получает на долю `power` меньше урона `duration` секунд.
  shield,

  /// Ярость: один раз, когда здоровье падает до `threshold`, урон и скорость
  /// атаки стража растут на `power`.
  enrage,
}

/// Умение стража — то, чем бой с ним отличается от боя с мешком здоровья.
///
/// Замах ([windup]) — не украшение. Он виден на экране раньше удара, и страж на
/// замахе не бьёт обычными атаками: бой читается как «он готовит удар», а не
/// как случайный всплеск урона.
class GuardianSkill {
  const GuardianSkill({
    required this.id,
    required this.name,
    required this.kind,
    this.every = 0.0,
    this.first = 0.0,
    this.windup = 0.0,
    this.power = 0.0,
    this.duration = 0.0,
    this.threshold = 0.0,
  });

  final String id;
  final String name;
  final GuardianSkillKind kind;

  /// Секунд между применениями. У ярости не используется.
  final double every;

  /// Когда умение применяется впервые. Ноль — через [every].
  final double first;

  final double windup;
  final double power;
  final double duration;

  /// Доля здоровья, на которой срабатывает ярость.
  final double threshold;

  bool get periodic => kind != GuardianSkillKind.enrage;
}

/// Архетип моба (GDD §7). Множители применяются к эталонным кривым [Curves].
class EnemyArchetype {
  const EnemyArchetype({
    required this.id,
    required this.name,
    this.gender = Gender.masculine,
    this.role = '',
    this.hpMult = 1.0,
    this.dpsMult = 1.0,
    this.attackSpeed = 1.0,
    this.armorMult = 0.0,
    this.packMin = 1,
    this.packMax = 1,
    this.damageType = DamageType.physical,
    this.resists = const {},
    this.isBoss = false,
    this.weight = 0.0,
    this.traits = const {},
    this.everyFloors = 0,
    this.phases = const [],
    this.embodies,
    this.skills = const [],
    this.lairMight,
  });

  final String id;
  final String name;

  /// Род названия. По нему согласуется всё, что о мобе говорит: «повержен»
  /// или «повержена». Мужской по умолчанию — так же ведут себя мобы из
  /// тестов, у которых рода нет.
  final Gender gender;

  /// Роль в бою одной строкой — для UI и для чтения контента человеком.
  final String role;

  final double hpMult;
  final double dpsMult;

  /// Ударов в секунду. Урон за удар выводится как dps / attackSpeed —
  /// иначе медленные тяжёлые мобы неотличимы от быстрых слабых.
  final double attackSpeed;

  final double armorMult;
  final int packMin;
  final int packMax;
  final DamageType damageType;
  final Map<DamageType, double> resists;
  final bool isBoss;

  /// Вес в подборе обычной пачки. У боссов не используется.
  final double weight;

  final Set<EnemyTrait> traits;

  /// Для боссов: появляется на каждом N-м этаже. У обычных мобов 0.
  final int everyFloors;

  /// Фазы босса — пока текст для UI, механика в Фазе 2.
  final List<String> phases;

  /// Для СТРАЖА: идентификатор босса, чьё это воплощение в собственном
  /// логове.
  ///
  /// Одно существо в двух ролях, и роли разные настолько, что числа у них
  /// свои. В бездне босс — РИТМ: он попадается каждые несколько этажей, мимо
  /// него идут вниз, и сделать его там тяжёлым значит превратить каждый пятый
  /// этаж в стену (замерено: окно первого спуска уезжает за нижнюю границу от
  /// правки, которая стражу проходит даром).
  ///
  /// В области он — ЦЕЛЬ, к которой игрок пришёл нарочно, зная, кто там
  /// стоит. Вот перед ней и положено думать, чем идти.
  ///
  /// Связь нужна не для красоты: уникальная вещь привязана к БОССУ
  /// (`RelicDef.source`), и страж роняет ту же вещь — он и есть тот босс.
  final String? embodies;

  /// Умения стража. У мобов и боссов бездны пусто: там они ритм, а не цель.
  final List<GuardianSkill> skills;

  /// Мощь СТРАЖА в логове — своя, поверх общей `Curves.lairGuardianMight`.
  /// `null` — общая.
  ///
  /// Раунд 40: одна мощь на четырёх стражей держала замысел ровно у одного.
  /// Проба рубежа (`sim_cli --lair-probe`) на общей ×3: Громовой без ответа
  /// не берётся, с Проводником берётся на треть здоровья — как задумано; а
  /// Ледяной без всякого ответа отдаёт круг с половиной здоровья героя.
  /// Правится здесь, а не здоровьем и уроном стража: те проверяет аудит
  /// (`audit_cli --bosses`) против голого снаряжения, и форма боя должна
  /// остаться той, что он выверил.
  final double? lairMight;

  double resistFor(DamageType type) => resists[type] ?? 0.0;

  bool has(EnemyTrait trait) => traits.contains(trait);

  @override
  String toString() => 'EnemyArchetype($id)';
}

/// Живой экземпляр моба в бою.
class EnemyInstance {
  EnemyInstance({
    required this.archetype,
    required this.maxHp,
    required this.damagePerHit,
    required this.armor,
    required this.attackSpeed,
  })  : hp = maxHp,
        attackAccumulator = 0.0;

  final EnemyArchetype archetype;
  final double maxHp;
  final double damagePerHit;
  final double armor;
  final double attackSpeed;

  double hp;
  double attackAccumulator;

  /// Сколько моб прожил в этой волне. Нужен черте [EnemyTrait.rampUp]:
  /// её носитель опасен затяжным боем, а не первым ударом.
  double waveSeconds = 0.0;

  // --- Умения стража ---------------------------------------------------------

  /// До применения каждого умения, в порядке [EnemyArchetype.skills].
  late final List<double> skillTimers = [
    for (final s in archetype.skills) s.first > 0.0 ? s.first : s.every,
  ];

  /// Умение на замахе: индекс в [EnemyArchetype.skills], `-1` — замаха нет.
  int windupSkill = -1;
  double windupRemaining = 0.0;

  /// Ярость: сработала ли и что дала.
  bool enraged = false;
  double enrageDamage = 0.0;
  double enrageHaste = 0.0;

  /// Щит: доля срезаемого урона и сколько он ещё держится.
  double shieldFraction = 0.0;
  double shieldRemaining = 0.0;

  bool get shielded => shieldRemaining > 0.0;

  /// Умение, которое страж сейчас готовит. `null` — не готовит.
  GuardianSkill? get windingUp =>
      windupSkill < 0 ? null : archetype.skills[windupSkill];

  // --- Наложенные эффекты ---------------------------------------------------
  //
  // Плоские поля, а не список объектов: доты тикают на каждом мобе каждый тик,
  // и аллокация под эффект на каждом тике — это сборщик мусора в самом горячем
  // месте симуляции. Одноимённые эффекты не складываются, а обновляются: два
  // источника горения дают одно горение, иначе шесть триггеров превращают
  // любой бой в мгновенное испарение волны.

  /// Урон в секунду от дота и остаток его длительности.
  double dotDps = 0.0;
  double dotRemaining = 0.0;
  DamageType dotType = DamageType.physical;

  /// Теги источника, повесившего дот.
  ///
  /// Хранятся у эффекта, а не берутся у героя в момент тика: горение от
  /// «Погребального костра» — это Огонь, Область и Длительность, и «+% к
  /// урону Огнём» обязано его усиливать. Пока тик наносил дот без тегов,
  /// длительный урон не усиливался НИЧЕМ, кроме общего «+% к урону», —
  /// и сборка вокруг дотов была невозможна.
  List<Tag> dotTags = const [];

  /// Сколько стаков горения висит. Обычно один: стаки открывает реликт.
  int dotStacks = 0;

  /// Итоговый урон дота в секунду.
  double get dotDamagePerSecond => dotDps * dotStacks;

  /// Проклятие: доля к получаемому урону.
  double curseIncrease = 0.0;
  double curseRemaining = 0.0;

  /// Замедление: доля к скорости атаки.
  double slowFraction = 0.0;
  double slowRemaining = 0.0;

  bool get cursed => curseRemaining > 0.0;
  bool get slowed => slowRemaining > 0.0;

  /// Накладывает дот. Более сильный источник вытесняет более слабый,
  /// одинаковые — обновляют длительность.
  void applyDot(double dps, double duration, DamageType type,
      {int maxStacks = 1, List<Tag> tags = const []}) {
    if (dotRemaining <= 0.0) {
      dotStacks = 0;
    }
    if (dps >= dotDps || dotRemaining <= 0.0) {
      dotDps = dps;
      dotType = type;
      dotTags = tags;
    }
    if (dotStacks < maxStacks) dotStacks++;
    if (duration > dotRemaining) dotRemaining = duration;
  }

  void applyCurse(double increase, double duration) {
    if (increase >= curseIncrease || curseRemaining <= 0.0) {
      curseIncrease = increase;
    }
    if (duration > curseRemaining) curseRemaining = duration;
  }

  void applySlow(double fraction, double duration) {
    if (fraction >= slowFraction || slowRemaining <= 0.0) {
      slowFraction = fraction;
    }
    if (duration > slowRemaining) slowRemaining = duration;
  }

  /// Стачивает длительности. Урон дота считает бой: доты не критуют и не
  /// порождают событий (`docs/02-TECH.md` §2.3) — иначе горение, накладываемое
  /// критом, замыкает шину саму на себя.
  void tickEffects(double dt) {
    if (dotRemaining > 0.0) {
      dotRemaining -= dt;
      if (dotRemaining <= 0.0) dotStacks = 0;
    }
    if (curseRemaining > 0.0) curseRemaining -= dt;
    if (slowRemaining > 0.0) slowRemaining -= dt;
    if (shieldRemaining > 0.0) shieldRemaining -= dt;
  }

  bool get alive => hp > 0.0;

  void heal(double amount) {
    hp += amount;
    if (hp > maxHp) hp = maxHp;
  }

  /// Наносит урон мобу. Возвращает true, если этот удар его добил.
  bool takeDamage(double amount) {
    if (!alive) return false;
    hp -= amount;
    return hp <= 0.0;
  }

  static EnemyInstance spawn(
    EnemyArchetype a,
    int depth, {
    int brandRank = 0,
    double hpMultiplier = 1.0,
    double dpsMultiplier = 1.0,
  }) {
    final brand = Curves.brandMobMultiplier(brandRank);
    // Здоровье — своей ручкой (раунд 41). Пока враг гибнул с одного удара,
    // множитель Клейма к здоровью ничего не значил; как только здоровье
    // начинает решать (боссы — проверка урона), он бьёт вдвое: бой длиннее
    // И удар сильнее.
    final hp = Curves.mobHp(depth) *
        a.hpMult *
        Curves.brandMobHpMultiplier(brandRank) *
        hpMultiplier;
    final dps = Curves.mobDps(depth) * a.dpsMult * brand * dpsMultiplier;
    return EnemyInstance(
      archetype: a,
      maxHp: hp,
      damagePerHit: dps / a.attackSpeed,
      armor: Curves.armorConstant(depth) * a.armorMult,
      attackSpeed: a.attackSpeed,
    );
  }
}

/// Реестр мобов.
///
/// Источник истины — `assets/content/enemies.json`; значения по умолчанию
/// дублируют бестиарий Фазы 1 и нужны только чтобы ядро работало без
/// загруженного контента (юнит-тесты формул, `sim_cli`).
///
/// Числа значений по умолчанию обязаны совпадать с JSON. Расхождение здесь —
/// это тесты, проверяющие не тот баланс, который увидит игрок.
class Bestiary {
  Bestiary._();

  static const _defaultScavenger = EnemyArchetype(
    id: 'scavenger',
    name: 'Падальщик',
    role: 'Мясо',
    hpMult: 0.6,
    dpsMult: 0.25,
    attackSpeed: 1.4,
    packMin: 3,
    packMax: 5,
    weight: 30.0,
  );

  // Бюджет босса задан относительно обычной волны, а не абсолютным числом.
  // Волна — 4 Падальщика: 2.4 hp-юнита и 1.0 dps-юнита. Босс должен стоить
  // 2–3 волны по суммарному урону, иначе он в одиночку определяет всю кривую
  // сложности вместо кривых из §2.2.
  static const _defaultAshLord = EnemyArchetype(
    id: 'ash_lord',
    name: 'Владыка Пепла',
    hpMult: 4.0,
    dpsMult: 0.8,
    attackSpeed: 0.7,
    armorMult: 0.2,
    damageType: DamageType.fire,
    resists: {DamageType.fire: 40.0},
    isBoss: true,
    everyFloors: 5,
  );

  static const _defaultVoidDevourer = EnemyArchetype(
    id: 'void_devourer',
    name: 'Пустотный Пожиратель',
    hpMult: 6.5,
    dpsMult: 1.0,
    attackSpeed: 0.6,
    armorMult: 0.3,
    damageType: DamageType.voidType,
    resists: {DamageType.voidType: 40.0},
    isBoss: true,
    everyFloors: 10,
  );

  static List<EnemyArchetype> _enemies = const [_defaultScavenger];
  static List<EnemyArchetype> _guardians = const [];
  static List<EnemyArchetype> _bosses = const [
    _defaultAshLord,
    _defaultVoidDevourer,
  ];

  /// Применяет загруженный контент. Списки сортируются по id: порядок в JSON
  /// не должен влиять на подбор пачки, иначе перестановка строк в файле меняет
  /// результат при том же сиде и ломает детерминизм.
  static void configure({
    required List<EnemyArchetype> enemies,
    required List<EnemyArchetype> bosses,
    List<EnemyArchetype> guardians = const [],
  }) {
    _enemies = List.unmodifiable(
      [...enemies]..sort((a, b) => a.id.compareTo(b.id)),
    );
    _bosses = List.unmodifiable(
      [...bosses]..sort((a, b) => a.id.compareTo(b.id)),
    );
    _guardians = List.unmodifiable(
      [...guardians]..sort((a, b) => a.id.compareTo(b.id)),
    );
  }

  /// Страж, воплощающий босса [bossId]. `null` — у этого босса своей области
  /// нет.
  static EnemyArchetype? guardianOf(String bossId) =>
      _guardians.where((g) => g.embodies == bossId).firstOrNull;

  static List<EnemyArchetype> get guardians => _guardians;

  /// Возврат к бестиарию Фазы 1. Нужен тестам, которые проверяют сами
  /// значения по умолчанию: порядок тестов внутри файла не должен решать,
  /// сравниваются они с кодом или уже с загруженным JSON.
  static void reset() {
    _enemies = const [_defaultScavenger];
    _bosses = const [_defaultAshLord, _defaultVoidDevourer];
  }

  static List<EnemyArchetype> get enemies => _enemies;
  static List<EnemyArchetype> get bosses => _bosses;

  /// Кого встретит герой в очередной волне. Один архетип на волну: бюджет
  /// пачки (packMin..packMax × множители) задан для однородной пачки, и
  /// смешивать их без общего бюджета — значит потерять контроль над кривой.
  static EnemyArchetype pick(Rng rng) {
    if (_enemies.length == 1) return _enemies.first;
    return _enemies[rng.weightedIndex([for (final e in _enemies) e.weight])];
  }

  static EnemyArchetype byId(String id) {
    for (final e in _enemies) {
      if (e.id == id) return e;
    }
    for (final e in _bosses) {
      if (e.id == id) return e;
    }
    throw StateError('В бестиарии нет моба «$id»');
  }

  /// Босс этажа: тот, у кого наибольшая периодичность делит глубину.
  /// «Каждый 10-й» перекрывает «каждый 5-й» — большой босс вместо обычного.
  static EnemyArchetype? bossFor(int depth) {
    EnemyArchetype? best;
    for (final b in _bosses) {
      if (b.everyFloors <= 0) continue;
      if (depth % b.everyFloors != 0) continue;
      if (best == null || b.everyFloors > best.everyFloors) best = b;
    }
    return best;
  }
}
