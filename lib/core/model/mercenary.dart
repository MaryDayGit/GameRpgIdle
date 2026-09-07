import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../sim/abilities.dart';
import '../sim/fork.dart';
import '../sim/loot.dart';
import '../sim/rng.dart';
import 'echo_tree.dart';
import 'equipment.dart';
import 'grammar.dart';
import 'hero.dart';
import 'lang.dart';
import 'passive_tree.dart';
import 'stat_block.dart';
import 'tags.dart';

/// Ранг наёмника. Определяет базовые статы и вместимость рюкзака.
///
/// Наёмник — это ран. Контракт → спуск → гибель → добыча и Эхо.
/// Поэтому ранг не «уровень персонажа», а качество конкретной попытки.
enum MercRank {
  // Женская форма нужна только Оборванцу: «Ветеран», «Клинок» и «Легенда»
  // в русском одинаковы для обоих родов.
  ragged(Phrase('Оборванец', 'Ragged'), 1.00, 8, feminine: 'Оборванка'),
  veteran(Phrase('Ветеран', 'Veteran'), 1.35, 10),
  blade(Phrase('Клинок', 'Blade'), 1.80, 12),
  legend(Phrase('Легенда', 'Legend'), 2.40, 16);

  const MercRank(this._title, this.statMultiplier, this.backpackSlots,
      {String? feminine})
      : _feminine = feminine;

  final Phrase _title;

  /// Женская форма — только русская. Английскому ранг по роду не согласуется,
  /// и заводить там второе поле значило бы просить переводчика дважды
  /// написать одно слово.
  final String? _feminine;

  /// Словарная форма — для мест, где рядом нет наёмника.
  String get title => _title.text;

  /// Ранг, согласованный с наёмником.
  String forGender(Gender gender) => switch (Lang.current) {
        Lang.ru => gender == Gender.feminine
            ? (_feminine ?? _title.of(Lang.ru))
            : _title.of(Lang.ru),
        Lang.en => _title.of(Lang.en),
      };

  /// Множитель к базовому StatBlock.
  final double statMultiplier;

  /// Сколько предметов наёмник донесёт обратно. Всё сверх — распыляется
  /// в золото и осколки. Это и есть диегетическое объяснение «правила витрины»:
  /// не игра прячет лут, а у наёмника кончается место в рюкзаке.
  final int backpackSlots;
}

/// Врождённая черта наёмника — один перк, привязанный к тегу или стату.
///
/// Черта не даёт «просто цифру»: она определяет, под какой билд наёмник
/// выгоден. Собранный игроком лоадаут и черта наёмника должны совпасть —
/// это и есть решение перед отправкой.
enum MercTrait {
  emberborn(Phrase('Погорелец', 'Emberborn'), 'Погорелица',
      Phrase('Урон с тегом Огонь +25 %', 'Fire-tagged damage +25%')),
  coldblooded(Phrase('Хладнокровный', 'Coldblooded'), 'Хладнокровная',
      Phrase('Урон с тегом Холод +25 %', 'Cold-tagged damage +25%')),
  voidmarked(Phrase('Меченый бездной', 'Void-marked'), 'Меченная бездной',
      Phrase('Урон с тегом Пустота +25 %', 'Void-tagged damage +25%')),
  bonebreaker(
      Phrase('Костолом', 'Bonebreaker'),
      'Костоломка',
      Phrase('Урон с тегом Удар +20 %, броня +10 %',
          'Strike-tagged damage +20%, armor +10%')),
  bloodsupper(Phrase('Кровопийца', 'Bloodsupper'), 'Кровопийца',
      Phrase('Вампиризм +4 %', 'Life leech +4%')),
  hardy(Phrase('Живучий', 'Hardy'), 'Живучая',
      Phrase('Максимальное HP +20 %', 'Maximum HP +20%')),
  swift(Phrase('Скорый', 'Swift'), 'Скорая',
      Phrase('Скорость атаки +12 %', 'Attack speed +12%')),
  lucky(Phrase('Удачливый', 'Lucky'), 'Удачливая',
      Phrase('Качество добычи +15 %', 'Loot quality +15%'));

  const MercTrait(this._title, this._feminine, this._description);

  final Phrase _title;

  /// Женская форма — только русская, по той же причине, что у [MercRank].
  final String _feminine;

  final Phrase _description;

  /// Словарная форма названия.
  String get title => _title.text;

  String get description => _description.text;

  /// Черта, согласованная с наёмником: «Живучий» или «Живучая».
  ///
  /// Половина имён в пуле женские, и «Нира · Живучий» — ровно то «странное
  /// слово», на которое пожаловался живой прогон. Английский согласования не
  /// требует и берёт одну форму.
  String forGender(Gender gender) => switch (Lang.current) {
        Lang.ru =>
          gender == Gender.feminine ? _feminine : _title.of(Lang.ru),
        Lang.en => _title.of(Lang.en),
      };

  /// Вклад черты в агрегированный StatBlock.
  /// Величины долевые — складываются в аддитивную корзину.
  StatBlock apply(StatBlock base) => switch (this) {
        MercTrait.emberborn => base + const StatBlock(tagDamage: {Tag.fire: 0.25}),
        MercTrait.coldblooded =>
          base + const StatBlock(tagDamage: {Tag.cold: 0.25}),
        MercTrait.voidmarked =>
          base + const StatBlock(tagDamage: {Tag.voidTag: 0.25}),
        MercTrait.bonebreaker => base +
            StatBlock(
              tagDamage: const {Tag.strike: 0.20},
              armor: base.armor * 0.10,
            ),
        MercTrait.bloodsupper => base + const StatBlock(leech: 0.04),
        MercTrait.hardy => base + StatBlock(maxHp: base.maxHp * 0.20),
        MercTrait.swift => base + const StatBlock(increasedAttackSpeed: 0.12),
        MercTrait.lucky => base + const StatBlock(lootQuality: 0.15),
      };
}

/// Наёмник — носитель одного спуска.
///
/// Гибнет насовсем. Снаряжение и добыча возвращаются на Заставу, глубина
/// обнуляется, Эхо начисляется по максимуму. Это ровно тот же цикл, что был
/// в §8 GDD, просто у рана появилось лицо.
class Mercenary {
  Mercenary({
    required this.id,
    required this.name,
    required this.rank,
    required this.trait,
    Equipment? gear,
    List<String>? abilities,
    this.forkPolicy = ForkPolicy.loot,
  })  : gear = gear ?? ItemFactory.starterKit(),
        // Копия, а не ссылка: переданный снаружи `const []` сделал бы лоадаут
        // неизменяемым, и первая же попытка сменить способность падала бы
        // там, где её никто не ждёт.
        abilities = List<String>.from(abilities ?? starterAbilityIds());

  final String id;
  final String name;
  final MercRank rank;

  /// Род наёмника — по имени. Нужен всему, что о нём говорит: черте,
  /// исходу рана, уведомлению о гибели.
  Gender get gender => MercFactory.genderOf(name);
  final MercTrait trait;

  /// Лоадаут, который игрок собрал перед отправкой.
  ///
  /// В спуске наёмник сам надевает найденное, если оно лучше: он профессионал
  /// и не понесёт лучший меч в мешке. Игрок задаёт стартовый набор и политику
  /// приоритетов, наёмник исполняет. Без этого сила билда в ране была бы
  /// заморожена, и удвоение прокачки давало бы +6 этажей вместо +40
  /// (см. `docs/03-DECISIONS.md`, раунд 3).
  final Equipment gear;

  /// Слоты способностей. Как и снаряжение, собираются игроком до отправки
  /// и заперты до конца контракта.
  final List<String> abilities;

  /// Приказ на развилку: чем наёмник руководствуется, выбирая путь, когда
  /// игрока нет рядом (GDD §2.6).
  ///
  /// Стоит у наёмника, а не у игрока: осторожный ветеран и жадный оборванец
  /// — разные попытки, и приказ им нужен разный. Как и лоадаут, он заперт
  /// с момента отправки: в контракт уходит снимок.
  ForkPolicy forkPolicy;

  int get backpackSlots => rank.backpackSlots;

  /// Полностью собранный боевой профиль.
  HeroProfile toProfile({
    double outpostBonus = 0.0,
    EchoTree? tree,
    PassiveTree? passives,
    int startDepthBonus = 0,
    double powerMultiplier = 1.0,
  }) =>
      HeroProfile(
        gear: gear,
        abilities: abilities,
        echoTreeBonus: outpostBonus,
        tree: tree,
        passives: passives,
        startDepthBonus: startDepthBonus,
        powerMultiplier: powerMultiplier * rank.statMultiplier,
        traitStats: trait.apply,
      );

  @override
  String toString() => '$name (${rank.title}, ${trait.title})';
}

/// Генератор кандидатов для Таверны.
class MercFactory {
  MercFactory._();

  /// Имена и род. Половина пула женские: род нужен всему, что о наёмнике
  /// говорит, — рангу, черте, исходу спуска, уведомлению о гибели.
  ///
  /// ## Почему имена английские на обоих языках
  ///
  /// Имя не переводится вместе с интерфейсом, потому что оно **лежит в
  /// сейве**, а не собирается при показе. Переводимый пул означал бы, что
  /// наёмник, нанятый по-английски, останется «Corwin the Blind» и после
  /// переключения на русский: строку в сейве переключение языка не трогает.
  /// Одно имя на все языки — это не упущение, а единственный способ не
  /// получить в одном отряде половину имён на одном языке и половину на
  /// другом.
  static const _firstNames = [
    ('Corwin', Gender.masculine),
    ('Tala', Gender.feminine),
    ('Jorn', Gender.masculine),
    ('Mirena', Gender.feminine),
    ('Gask', Gender.masculine),
    ('Ulva', Gender.feminine),
    ('Deren', Gender.masculine),
    ('Solveig', Gender.feminine),
    ('Kramm', Gender.masculine),
    ('Asta', Gender.feminine),
    ('Bjorn', Gender.masculine),
    ('Nira', Gender.feminine),
  ];

  /// Русские имена прежних сборок.
  ///
  /// Нужны ровно одному: [genderOf] на СТАРОМ сейве. Имя там записано
  /// по-русски, и без этого списка все нанятые до перевода наёмницы стали бы
  /// мужского рода — «Мирена Слепая погиб» в первом же уведомлении.
  ///
  /// Новых наёмников отсюда не выдают: список нужен для чтения, а не для
  /// генерации, и в [roll] он не участвует.
  static const _legacyNames = [
    ('Корвин', Gender.masculine),
    ('Тала', Gender.feminine),
    ('Йорн', Gender.masculine),
    ('Мирена', Gender.feminine),
    ('Гаск', Gender.masculine),
    ('Ульва', Gender.feminine),
    ('Дерен', Gender.masculine),
    ('Сольвейг', Gender.feminine),
    ('Крамм', Gender.masculine),
    ('Аста', Gender.feminine),
    ('Бьорн', Gender.masculine),
    ('Нира', Gender.feminine),
  ];

  /// Прозвища. По одной форме на каждое: английское прилагательное по роду
  /// не согласуется, и второй формы у него не бывает.
  ///
  /// Длина списка та же, что была у русского: `roll` берёт из него по
  /// индексу, и другое число вариантов сдвинуло бы всех наёмников на одном
  /// и том же сиде — то есть сломало бы воспроизводимость спуска.
  static const _epithets = [
    'the Lame',
    'the Quiet',
    'the Marked',
    'the One-Armed',
    'the Ashen',
    'the Blind',
    'the Lanky',
    'the Silent',
    'the Rusted',
    'the Last',
  ];

  /// Род наёмника по его имени.
  ///
  /// Считается по строке, а не хранится полем: имя уже лежит в сейве, и
  /// добавлять к нему второе поле значило бы менять формат ради того, что
  /// и так однозначно выводится. Незнакомое имя — мужской род: так себя
  /// ведут и старые сейвы, и наёмники из тестов.
  static Gender genderOf(String fullName) {
    final first = fullName.split(' ').first;
    for (final (name, gender) in _firstNames) {
      if (name == first) return gender;
    }
    // Сейв, сделанный до перевода имён. Проверяется вторым, а не первым:
    // новых имён в игре больше, и они должны находиться за один проход.
    for (final (name, gender) in _legacyNames) {
      if (name == first) return gender;
    }
    return Gender.masculine;
  }

  /// Веса рангов в зависимости от уровня Таверны.
  ///
  /// Улучшение Заставы делает не «сильнее того же наёмника», а
  /// «вероятнее хорошего наёмника» — прокачивается пул, а не персонаж.
  static List<double> rankWeights(int tavernLevel) {
    final l = tavernLevel.clamp(0, 6);
    return [
      (60 - 9 * l).toDouble().clamp(4.0, 60.0),
      (30 + 2 * l).toDouble(),
      (8 + 4 * l).toDouble(),
      (2 + 3 * l).toDouble(),
    ];
  }

  /// [rank] задаётся только там, где ранг — не случайность: доброволец
  /// Таверны обязан быть Оборванцем, иначе на восьмом уровне Таверны даром
  /// доставалась бы Легенда.
  static Mercenary roll(
    Rng rng, {
    int tavernLevel = 0,
    String idPrefix = 'm',
    MercRank? rank,
  }) {
    final weights = rankWeights(tavernLevel);
    final total = weights.reduce((a, b) => a + b);
    var roll = rng.nextDouble() * total;
    var rankIndex = 0;
    for (var i = 0; i < weights.length; i++) {
      if (roll < weights[i]) {
        rankIndex = i;
        break;
      }
      roll -= weights[i];
    }

    final (first, _) = _firstNames[rng.nextInt(_firstNames.length)];
    final epithet = _epithets[rng.nextInt(_epithets.length)];
    final name = '$first $epithet';

    return Mercenary(
      id: '$idPrefix${rng.nextRaw().abs() % 1000000}',
      name: name,
      rank: rank ?? MercRank.values[rankIndex],
      trait: MercTrait.values[rng.nextInt(MercTrait.values.length)],
    );
  }
}

/// Ростер Заставы.
///
/// В MVP в спуске одновременно один наёмник, но структура рассчитана на
/// несколько: [activeSlots] поднимается постройкой Таверны, у каждого
/// наёмника свой лоадаут, своя добыча и своя глубина. Ничего в симуляции
/// не завязано на единственность — [DescentSimulator] уже принимает
/// профиль, а не глобальное состояние.
class Roster {
  Roster({this.activeSlots = 1});

  /// Сколько наёмников может быть в спуске одновременно. MVP: 1.
  int activeSlots;

  /// Кандидаты в Таверне, ждут найма.
  final List<Mercenary> candidates = [];

  /// Наняты, но не отправлены.
  final List<Mercenary> reserve = [];

  /// Сейчас в расселине.
  final List<Mercenary> deployed = [];

  /// Погибшие — для мемориала и статистики.
  final List<Mercenary> fallen = [];

  /// Есть ли свободный слот. [limit] приходит от Заставы: сколько наёмников
  /// уходит вниз одновременно — свойство Заставы, а не списка людей.
  bool canDeployWithin(int limit) => deployed.length < limit;

  bool get canDeploy => canDeployWithin(activeSlots);

  void refreshCandidates(Rng rng, {required int tavernLevel, required int count}) {
    candidates
      ..clear()
      ..addAll(List.generate(
        count,
        (i) => MercFactory.roll(rng, tavernLevel: tavernLevel, idPrefix: 'c$i'),
      ));
  }

  void hire(Mercenary m) {
    candidates.remove(m);
    reserve.add(m);
  }

  void deploy(Mercenary m, {int? limit}) {
    final slots = limit ?? activeSlots;
    if (!canDeployWithin(slots)) {
      throw StateError(
          'Нет свободных слотов спуска (${deployed.length}/$slots)');
    }
    reserve.remove(m);
    deployed.add(m);
  }

  void bury(Mercenary m) {
    deployed.remove(m);
    fallen.add(m);
  }

  /// Стоимость найма растёт с рангом: Таверна повышает шансы, но не делает
  /// «Легенду» бесплатной.
  ///
  /// И растёт с [maxDepthEver] — тем же темпом, что доход (см.
  /// [Curves.hireCostScale]). Кто идёт глубже, тот и требует больше вперёд.
  /// Оборванец вне этого счёта: он всегда стоит своих 250, и это единственный
  /// ход, который нельзя потерять.
  static double hireCost(MercRank rank, {int maxDepthEver = 0}) {
    final byRank = switch (rank) {
      MercRank.ragged => 1.0,
      MercRank.veteran => 3.0,
      MercRank.blade => 9.0,
      MercRank.legend => 27.0,
    };
    final scale =
        rank == MercRank.ragged ? 1.0 : Curves.hireCostScale(maxDepthEver);
    return Tuning.baseHireCost * byRank * scale;
  }
}
