import '../balance/curves.dart';
import '../content/ability_def.dart';
import '../content/content_pack.dart';
import '../content/floor_modifier_def.dart';
import '../balance/tuning.dart';
import 'relic_effect.dart';
import '../sim/crafting.dart';
import '../sim/daily_rift.dart';
import '../sim/descent.dart';
import '../sim/fork.dart';
import '../sim/rng.dart';
import 'echo_tree.dart';
import 'build_power.dart';
import 'equipment.dart';
import 'haul.dart';
import 'hero.dart';
import 'gear.dart';
import 'item.dart';
import 'shard.dart';
import 'mercenary.dart';
import 'outpost.dart';
import 'passive_tree.dart';
import '../content/quest_def.dart';
import 'quest_log.dart';
import 'tags.dart';

/// Состояние контракта — что сейчас происходит с наёмником.
enum ContractState {
  /// Наёмник в расселине, спуск идёт.
  descending,

  /// Наёмник встал на развилке и ждёт решения игрока.
  ///
  /// Не пауза «по требованию», а часть цикла: пока игрок думает, время рана
  /// не идёт — наёмник стоит. Ожидание ограничено бюджетом
  /// [Tuning.forkWaitBudgetSeconds] на весь спуск: исчерпав его, наёмник
  /// доходит спуск сам по приказу. Иначе отсутствие игрока останавливало бы
  /// игру, а это idle, а не пошаговая стратегия.
  atFork,

  /// Наёмник погиб (или отозван). Добыча ждёт, пока игрок её заберёт.
  awaitingCollection,

  /// Добыча забрана, контракт закрыт.
  closed,
}

/// Остановка наёмника на развилке.
///
/// [seconds] = `null`, пока он всё ещё стоит: сколько простоит — зависит от
/// того, когда придёт игрок, и знать это заранее нельзя.
class ForkPause {
  ForkPause(this.startUtc, [this.seconds]);

  final DateTime startUtc;
  double? seconds;

  bool get unfinished => seconds == null;
}

/// Вклад Заставы в один спуск.
///
/// Снимок, а не ссылка на Заставу: постройки улучшаются, пока наёмник внизу,
/// и повтор по СЕГОДНЯШНЕЙ Заставе показал бы не тот бой, результат которого
/// уже записан. Та же причина, по которой снимается снаряжение.
class OutpostSnapshot {
  const OutpostSnapshot({
    this.salvageRate = 0.35,
    this.lootQuality = 0.0,
    this.lootQuantity = 0.0,
    this.restHealBonus = 0.0,
  });

  /// Алтарь: доля стоимости, возвращаемая распылением.
  final double salvageRate;

  /// Оружейная: качество и количество добычи.
  final double lootQuality;
  final double lootQuantity;

  /// Костёр: прибавка к восстановлению между этажами.
  final double restHealBonus;
}

/// Один контракт: наёмник ушёл вниз, вернулась добыча.
class Contract {
  Contract({
    required this.mercenary,
    required this.seed,
    required this.brandRank,
    required this.startedAtUtc,
    Equipment? loadout,
    List<String>? abilities,
    this.echoTreeBonus = 0.0,
    Iterable<String>? echoNodes,
    Iterable<String>? passiveNodes,
    this.startDepthBonus = 0,
    this.forkPolicy = ForkPolicy.loot,
    this.outpost = const OutpostSnapshot(),
    this.riftDay,
  })  : loadout = loadout ?? Equipment(),
        echoNodes = List<String>.unmodifiable(echoNodes ?? const <String>[]),
        passiveNodes =
            List<String>.unmodifiable(passiveNodes ?? const <String>[]),
        abilities = List<String>.from(abilities ?? const <String>[]);

  final Mercenary mercenary;
  final int seed;
  final int brandRank;
  final DateTime startedAtUtc;

  /// Снимок того, с чем наёмник ушёл вниз.
  ///
  /// Нужен не для истории, а чтобы ран можно было ВОСПРОИЗВЕСТИ. Снаряжение
  /// самого наёмника меняется прямо в спуске — он надевает найденное, — и
  /// повтор по его текущему состоянию дал бы другой бой, чем тот, результат
  /// которого уже записан. Симуляция детерминирована, поэтому снимка плюс
  /// сида достаточно, чтобы получить ровно тот же спуск тик в тик.
  final Equipment loadout;
  final List<String> abilities;
  /// Скалярный множитель силы от Заставы (и от старого древа — см.
  /// `HeroProfile.echoTreeBonus`).
  final double echoTreeBonus;

  /// Узлы древа, купленные на момент отправки. Часть снимка ровно по той же
  /// причине, что снаряжение: древо между отправкой и гибелью растёт, а повтор
  /// обязан показать тот бой, который уже записан.
  final List<String> echoNodes;

  /// Взятые узлы дерева пассивок на момент отправки. Снимок по той же
  /// причине: дерево растёт, пока наёмник внизу.
  final List<String> passiveNodes;

  /// С какого этажа начался спуск, считая от первого.
  ///
  /// Складывается из «верёвки» (доля рекорда, `Curves.startDepth`) и узлов
  /// ветки «Бездна». Хранится снимком: рекорд может вырасти, пока наёмник
  /// внизу, а повтор обязан начаться там же, где начался посчитанный ран.
  final int startDepthBonus;

  /// Вклад Заставы на момент отправки.
  final OutpostSnapshot outpost;

  /// Разлом дня: спуск по общему для всех сегодняшнему расписанию.
  ///
  /// Часть снимка по той же причине, что и всё остальное: модификатор разлома
  /// меняет каждый этаж, и повтор без него показал бы другой спуск.
  final int? riftDay;

  bool get isRift => riftDay != null;

  /// Модификатор разлома, действующий на каждом этаже этого спуска.
  ///
  /// Считается из дня, а не хранится: разлом — функция от суток, и второе
  /// место, где он записан, рано или поздно разошлось бы с первым.
  FloorModifierDef? get riftModifier => riftDay == null
      ? null
      : DailyRift.on(DateTime.utc(1970).add(Duration(days: riftDay!))).modifier;

  /// Этаж, с которого начался спуск. Нужен, чтобы сосчитать номер развилки:
  /// решения игрока хранятся списком по порядку, а не по этажам.
  int get startDepth {
    final floors = result?.floors;
    return floors == null || floors.isEmpty ? 1 : floors.first.depth;
  }

  /// Приказ на развилку: чем наёмник руководствуется, выбирая путь, пока
  /// игрока нет рядом (GDD §2.6).
  ///
  /// Часть снимка ровно по той же причине, что и снаряжение: политика меняет
  /// выбранные модификаторы, а значит и весь спуск. Повтор с другой политикой
  /// показал бы бой, которого не было.
  final ForkPolicy forkPolicy;

  ContractState state = ContractState.descending;

  /// Посчитанный ОТРЕЗОК спуска: до ближайшей неразрешённой развилки или до
  /// конца, если развилок больше нет.
  RunResult? result;

  /// Решения игрока на развилках, по порядку. Вместе со снимком и сидом
  /// полностью задают спуск: по ним он воспроизводится тик в тик, и хранить
  /// состояние симуляции не нужно ни в памяти, ни в сохранении.
  final List<int> forkChoices = [];

  /// Остановки на развилках: когда наёмник встал и сколько простоял.
  ///
  /// Настенное время идёт, а игровое — нет: пока наёмник стоит, он не
  /// спускается. Без этой поправки журнал, полоска и боевой экран разошлись
  /// бы ровно на время раздумий игрока.
  ///
  /// Список, а не одно число. Одним числом простой вычитался бы из ВСЕГО
  /// времени спуска, включая моменты ДО остановки: журнал на пятой минуте
  /// показывал бы этаж, до которого наёмник дойдёт только на шестой. Каждая
  /// пауза обязана знать, когда она была.
  final List<ForkPause> pauses = [];

  /// Перестал ли наёмник ждать игрока на этом спуске.
  ///
  /// Взводится один раз, когда он не дождался: дальше он идёт по приказу и
  /// больше не останавливается. Хранится отдельным фактом, а не выводится из
  /// длительности последней паузы: игрок вполне может ответить ровно на
  /// сорок пятой секунде, и такой вывод оказался бы верным по случайности.
  bool forkWaitingSpent = false;

  /// Когда наёмник дошёл до текущей развилки. `null`, если он не стоит.
  DateTime? get forkArrivedAtUtc =>
      pauses.isNotEmpty && pauses.last.unfinished ? pauses.last.startUtc : null;

  /// Сколько всего простояно за спуск. Для сохранения и замеров.
  double get waitedSeconds =>
      pauses.fold(0.0, (sum, p) => sum + (p.seconds ?? 0.0));

  /// Момент, когда кончится ТЕКУЩИЙ ОТРЕЗОК спуска.
  ///
  /// Раньше это была дата гибели, и поле называлось `segmentEndsAtUtc`. С живыми
  /// развилками конца спуска не существует, пока игрок не принял все решения:
  /// спуск считается отрезками до ближайшей развилки. Поэтому здесь либо
  /// момент, когда наёмник дойдёт до развилки и встанет, либо — для
  /// последнего отрезка — момент гибели.
  ///
  /// Имя изменилось намеренно. Поле, у которого поменялся смысл, обязано
  /// поменять и название: иначе каждый следующий читатель прочитает его
  /// по-старому и будет прав по-своему.
  ///
  /// Уведомление ставится на него в обоих случаях: игроку одинаково нужно
  /// знать и «он на развилке», и «он погиб» (`docs/02-TECH.md` §3).
  DateTime? segmentEndsAtUtc;

  Haul? get haul => result?.haul;

  /// Профиль для повтора спуска. Собирается заново из снимка, а не берётся
  /// у наёмника: у того снаряжение уже другое.
  HeroProfile replayProfile() => HeroProfile(
        gear: loadout.copy(),
        abilities: abilities,
        echoTreeBonus: echoTreeBonus,
        tree: EchoTree(bought: echoNodes),
        passives: PassiveTree(allocated: passiveNodes),
        startDepthBonus: startDepthBonus,
        powerMultiplier: mercenary.rank.statMultiplier,
        traitStats: mercenary.trait.apply,
      );

  bool get awaitingCollection => state == ContractState.awaitingCollection;
  bool get descending => state == ContractState.descending;

  /// Сколько спуск длится по игровым часам.
  Duration get duration => segmentEndsAtUtc == null
      ? Duration.zero
      : segmentEndsAtUtc!.difference(startedAtUtc);

  /// Ждёт ли наёмник решения на развилке прямо сейчас.
  bool get atFork => state == ContractState.atFork;

  /// Развилка, на которой он стоит.
  Fork? get pendingFork => atFork ? result?.pendingFork : null;

  /// Кончился ли спуск совсем — или это только конец отрезка.
  bool get runFinished => result != null && !result!.awaitingFork;

  /// Сколько секунд простояно К МОМЕНТУ [now].
  ///
  /// Именно к моменту, а не всего: пауза, которая случится позже, не должна
  /// влиять на то, где наёмник был раньше.
  double waitedAt(DateTime now) {
    final utc = now.toUtc();
    var total = 0.0;
    for (final pause in pauses) {
      if (!utc.isAfter(pause.startUtc)) break;
      final elapsed = utc.difference(pause.startUtc).inMilliseconds / 1000.0;
      final full = pause.seconds;
      total += full == null || elapsed < full ? elapsed : full;
    }
    return total;
  }

  /// ИГРОВОЕ время спуска к моменту [now]: настенное минус простой.
  ///
  /// Всё, что читает журнал и полоску, обязано спрашивать это, а не разницу
  /// дат: наёмник, стоящий на развилке, не проходит этажи.
  double simSecondsAt(DateTime now) {
    final wall =
        now.toUtc().difference(startedAtUtc).inMilliseconds / 1000.0;
    final value = wall - waitedAt(now);
    return value < 0.0 ? 0.0 : value;
  }

  /// Доля пройденного пути к моменту [now]. Это и есть полоска ожидания.
  double progressAt(DateTime now) {
    final total = result?.totalSeconds ?? 0.0;
    if (total <= 0) return 1.0;
    return (simSecondsAt(now) / total).clamp(0.0, 1.0);
  }

  /// Сколько наёмник уже внизу.
  ///
  /// Это единственное время, которое можно показывать игроку: ран посчитан
  /// целиком при отправке, и «сколько осталось» — не оценка, а дата гибели.
  Duration elapsedAt(DateTime now) {
    final passed = now.toUtc().difference(startedAtUtc);
    return passed.isNegative ? Duration.zero : passed;
  }

  Duration remainingAt(DateTime now) {
    final endsAt = segmentEndsAtUtc;
    if (endsAt == null) return Duration.zero;
    final left = endsAt.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Этаж, на котором наёмник находится СЕЙЧАС.
  ///
  /// Отличается от [depthAt] на единицу и именно поэтому существует: пройдено
  /// ноль этажей, а стоит герой на первом, и «Этаж 0» на экране выглядит
  /// ошибкой, а не состоянием.
  int currentFloorAt(DateTime now) {
    final run = result;
    if (run == null) return 0;
    final cleared = depthAt(now);
    return cleared >= run.maxDepth ? run.maxDepth : cleared + 1;
  }

  /// Глубина, до которой наёмник дошёл к моменту [now]. Журнал спуска
  /// открывается по мере того, как время идёт, а не весь сразу.
  int depthAt(DateTime now) {
    final run = result;
    if (run == null) return 0;

    final seconds = simSecondsAt(now);
    var elapsed = 0.0;
    var depth = 0;
    for (final floor in run.floors) {
      // Отдых между этажами тоже занимает время рана — без него журнал,
      // полоска ожидания и боевая сцена показывали бы три разных этажа.
      elapsed += floor.seconds + Tuning.restSecondsBetweenFloors;
      // Допуск в миллисекунду. Конец отрезка хранится датой, округлённой до
      // миллисекунд, и без допуска ровно на нём последний этаж оказывался
      // «ещё не пройденным»: наёмник, стоящий перед третьим этажом,
      // показывался стоящим перед вторым.
      if (elapsed > seconds + 0.001) break;
      if (floor.survived) depth = floor.depth;
    }
    return depth;
  }
}

/// Аккаунт игрока — всё, что переживает гибель наёмника.
class PlayerProfile {
  PlayerProfile({
    Outpost? outpost,
    Roster? roster,
    EchoTree? tree,
    PassiveTree? passives,
    this.gold = 0.0,
    this.echo = 0,
    int maxDepthEver = 0,
    int brandRank = 0,
    Map<int, int>? bestDepthByBrand,
    QuestLog? quests,
  })  : _maxDepthEver = maxDepthEver,
        bestDepthByBrand = {...?bestDepthByBrand},
        quests = quests ?? QuestLog(),
        _brandRank = brandRank,
        outpost = outpost ?? Outpost(),
        roster = roster ?? Roster(),
        tree = tree ?? EchoTree(),
        passives = passives ?? PassiveTree();

  /// Новый аккаунт.
  ///
  /// Первый наёмник выдаётся, а не покупается: золота у игрока ещё нет,
  /// и первое действие в игре не должно упираться в «не хватает 250».
  /// Первый ран показывает прести́ж-петлю целиком — ради этого он и нужен
  /// (GDD §10), а всё остальное игрок уже покупает сам.
  factory PlayerProfile.newGame({int seed = 0}) {
    final profile = PlayerProfile();
    final rng = Rng.stream(seed, 0, 0, RngPurpose.tavern);

    profile.roster.reserve
        .add(MercFactory.roll(rng, tavernLevel: 0, idPrefix: 'first'));
    profile.refreshTavern(rng);
    return profile;
  }

  final Outpost outpost;
  final Roster roster;
  final EchoTree tree;

  /// Дерево пассивок: общая прокачка игрока за достигнутую глубину.
  final PassiveTree passives;

  double gold;
  int echo;

  /// Покупает узел древа. Возвращает `false`, если узел закрыт предыдущим,
  /// уже куплен или не по карману.
  ///
  /// Пачкой больше не покупается: узлы разные, и «вложить всё» отняло бы у
  /// игрока единственный выбор, который древо и есть.
  bool buyEchoNode(String nodeId) {
    final left = tree.buy(nodeId, echo);
    if (left == null) return false;
    echo = left;
    return true;
  }

  /// Вкладывает всё доступное Эхо по политике «поровну по веткам».
  ///
  /// Игроку не предлагается: древо — это выбор, и кнопка «вложить всё» его
  /// отменяет. Нужна балансировщику и тестам, которым важен средний игрок.
  int autoSpendEcho() {
    var bought = 0;
    while (true) {
      final node = tree.nextByBalancedPolicy();
      if (node == null || !buyEchoNode(node)) return bought;
      bought++;
    }
  }

  /// Очки дерева пассивок: даёт достигнутая глубина, тратит дерево.
  int get passivePoints =>
      PassiveTree.pointsFor(maxDepthEver) + provenBrandRanks;
  int get passivePointsLeft => passivePoints - passives.spent;

  /// В какой день игрок последний раз спускался в разлом. `null` — ни разу.
  ///
  /// День, а не «сегодня/нет»: сутки меняются, пока игра закрыта, и
  /// логическое поле пришлось бы кому-то сбрасывать. Число сбрасывать не
  /// нужно — достаточно сравнить его с сегодняшним.
  int? riftDoneOn;

  /// Лучшая глубина, взятая в разломах. Своя запись: разлом идёт под
  /// модификатором на каждом этаже, и сравнивать его с обычным рекордом
  /// значило бы сравнивать разные игры.
  int riftBestDepth = 0;

  /// Доступен ли разлом в момент [now].
  bool riftAvailable(DateTime now) => riftDoneOn != DailyRift.dayOf(now);

  /// Добыча, ждущая разбора: игрок ещё не решил, что с ней делать.
  ///
  /// Существует потому, что рюкзак стал бесконечным, а сундук — нет. Раньше
  /// решение принимал наёмник («худшее за борт») и сундук («что не влезло —
  /// в золото»), то есть главный выбор цикла делали два автомата. Теперь его
  /// делает игрок, и добыче нужно место, где она ждёт этого решения.
  ///
  /// Переживает перезапуск: спуск может кончиться ночью, а разобрать его
  /// игрок придёт утром.
  final List<Item> pendingLoot = [];

  /// Есть ли что разбирать.
  bool get hasPendingLoot => pendingLoot.isNotEmpty;

  /// Сколько ещё влезет в сундук.
  int get stashRoom {
    final left = outpost.stashSlots - stash.length;
    return left < 0 ? 0 : left;
  }

  /// Глубина, на которой дадут следующее очко. `null` — потолок достигнут.
  int? get nextPassivePointDepth {
    if (passivePoints >= Curves.passivePointCap) return null;
    return (passivePoints + 1) * Curves.passivePointPerFloors;
  }

  /// Берёт узел дерева пассивок.
  bool allocatePassive(String nodeId) =>
      passives.allocate(nodeId, passivePoints);

  /// Снимает узел, если дерево останется связным.
  bool refundPassive(String nodeId) => passives.refund(nodeId);

  /// Боевой профиль наёмника — ровно тот, с которым он уйдёт вниз.
  ///
  /// Единственная точка сборки. Экран сборки билда считал свои числа сам, и
  /// считал их БЕЗ обоих деревьев: игрок видел «силу билда», которая не
  /// совпадала с той, что уходит в бездну, и сравнивал предметы по заниженной
  /// базе. Две сборки одного профиля расходятся молча — поэтому она одна.
  HeroProfile heroProfileFor(Mercenary m) => m.toProfile(
        outpostBonus: outpost.descentPowerBonus,
        tree: tree,
        passives: passives,
        startDepthBonus: startDepthBonus,
      );

  /// Что Застава даёт спуску прямо сейчас. Уходит в контракт снимком.
  OutpostSnapshot get outpostSnapshot => OutpostSnapshot(
        salvageRate: outpost.salvageRate,
        lootQuality: outpost.lootQuality,
        lootQuantity: outpost.lootQuantity,
        restHealBonus: outpost.restHealBonus,
      );

  /// Сколько наёмников может быть в бездне одновременно.
  ///
  /// Спрашивается у Заставы: второй слот открывает Таверна. Ростер про это
  /// не знает — он список людей, а не правило игры.
  int get deploySlots => outpost.deploySlots;

  /// Есть ли свободный слот спуска.
  bool get canDeploy => roster.canDeployWithin(deploySlots);

  /// С какого этажа начинается спуск.
  ///
  /// Верёвка спущена до доли рекорда (`Curves.startDepth`), узлы ветки
  /// «Бездна» добавляются сверху. Считается здесь, а не в симуляции: это
  /// свойство ИГРОКА, а не боя, и в снимок контракта оно уходит числом.
  int get startDepth => Curves.startDepth(maxDepthEver);

  /// Прибавка к стартовой глубине: узлы ветки «Бездна».
  int get startDepthBonus => tree.startDepthBonus;

  /// Слотов способностей у наёмника: базовые плюс узел «Пятый слот».
  int get abilitySlots => Tuning.abilitySlots + tree.abilitySlotBonus;

  /// Слоты умений КОНКРЕТНОГО наёмника — с учётом надетых реликтов.
  ///
  /// «Оберег молчания» обещает, что каждый слот вмещает две пассивные
  /// способности. Обещание разбиралось из контента, доезжало до правил и не
  /// читалось ни одной строкой: слотов оставалось четыре, и реликт был
  /// чистым проклятием без своей награды.
  int abilitySlotsFor(Mercenary m) =>
      abilitySlots * m.gear.relicRules.passivesPerSlot;

  /// Можно ли поставить это умение в сборку наёмника. `null` — можно;
  /// иначе строка с причиной, которую показывает экран.
  ///
  /// Причина возвращается словами, а не флагом: запрет без объяснения игрок
  /// читает как поломку игры, и именно так и прочитал.
  /// [loadout] — сборка, ОТНОСИТЕЛЬНО которой проверяем; по умолчанию текущая.
  /// Экран передаёт сюда сборку без заменяемого слота, иначе замена одного
  /// активного умения на другое упиралась бы сама в себя.
  String? abilityBlockedReason(
    Mercenary m,
    AbilityDef def, {
    List<String>? loadout,
  }) {
    final rules = m.gear.relicRules;
    final current = loadout ?? m.abilities;

    if (rules.passivesOnly && def.isActive) {
      final relic = _relicName(m, RelicEffect.passivesOnly) ?? 'Реликт';
      return '$relic: активные умения недоступны';
    }
    if (rules.singleActive && def.isActive) {
      final hasOther = current.any((id) =>
          id != def.id && (ContentPack.current.ability(id)?.isActive ?? false));
      if (hasOther) {
        final relic = _relicName(m, RelicEffect.singleActive) ?? 'Реликт';
        return '$relic: активное умение может быть только одно';
      }
    }
    return null;
  }

  /// Строка про правило реликта для шапки списка умений, или `null`.
  String? abilityRuleNote(Mercenary m) {
    final rules = m.gear.relicRules;
    if (rules.passivesOnly) {
      final n = rules.passivesPerSlot;
      return '${_relicName(m, RelicEffect.passivesOnly) ?? "Реликт"}: '
          'только пассивные умения, зато слотов $n на каждый обычный.';
    }
    if (rules.singleActive) {
      return '${_relicName(m, RelicEffect.singleActive) ?? "Реликт"}: '
          'активное умение может быть только одно.';
    }
    return null;
  }

  /// Имя надетого реликта с таким эффектом — чтобы запрет назывался тем, что
  /// его наложило, а не безличным «нельзя».
  String? _relicName(Mercenary m, RelicEffect effect) {
    for (final item in m.gear.slots) {
      final id = item?.relicId;
      if (id == null) continue;
      final def = ContentPack.current.relic(id);
      if (def != null && def.effect == effect) return def.name;
    }
    return null;
  }

  /// Лишний слот аффикса на всех предметах — узел «Печать мастера».
  int get affixSlotBonus => tree.affixSlotBonus;

  /// Журнал заданий. Единственный источник новых способностей.
  final QuestLog quests;

  /// Задания, закрытые последним получением добычи.
  ///
  /// Живёт до следующего `collect`: экран показывает по нему «Задание
  /// выполнено — открыто умение …». Награда, о которой не сказали, — это
  /// награда, которой не было.
  List<QuestDef> lastClosedQuests = const [];

  /// Способности, доступные для сборки: стартовые плюс открытые заданиями.
  ///
  /// Раньше их открывало древо Эха — по одиннадцать штук одним узлом, — и
  /// живой прогон дал приговор: «умений мало, и они все сразу открыты».
  /// Открытие, случающееся одиннадцать раз одновременно, перестаёт быть
  /// событием; ради этого события новое умение и нужно.
  List<AbilityDef> get availableAbilities {
    final unlocked = quests.unlockedAbilities;
    return [
      for (final def in ContentPack.current.abilities)
        if (def.isStarter || unlocked.contains(def.id)) def,
    ];
  }

  /// Факты о себе — то, из чего задания строят цели.
  ///
  /// [result] и [loadout] описывают ПОСЛЕДНИЙ спуск: цель про билд («нанесите
  /// половину урона Молнией») обязана спрашивать про один конкретный спуск, а
  /// не про сумму за всю игру.
  QuestFacts questFacts({RunResult? result, List<String>? loadout}) {
    final tags = <Tag, int>{};
    for (final id in loadout ?? const <String>[]) {
      final def = ContentPack.current.ability(id);
      if (def == null) continue;
      for (final tag in def.tags) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }
    }

    return QuestFacts(
      maxDepthEver: maxDepthEver,
      runsCompleted: quests.runsCompleted,
      relicsFound: quests.relicsFound,
      echoNodes: tree.nodesBought,
      passivePoints: passives.spent,
      shardsHeld: shards.length,
      bestDepthByBrand: bestDepthByBrand,
      outpost: outpost.snapshotLevels,
      bossesKilled: result?.bossesKilled ?? const {},
      damageShare: {
        if (result != null)
          for (final type in DamageType.values)
            if (result.shareOf(type) > 0.0) type: result.shareOf(type),
      },
      loadoutTags: tags,
    );
  }

  /// Проверяет задания и выдаёт награды. Возвращает закрытое за этот вызов.
  ///
  /// Награда — способность, и выдавать её нечем: список доступных считается
  /// из журнала. Эхо — единственное, что реально начисляется.
  List<QuestDef> checkQuests({RunResult? result, List<String>? loadout}) {
    final closed = quests
        .check(questFacts(result: result, loadout: loadout));
    for (final quest in closed) {
      echo += quest.rewardEcho;
    }
    return closed;
  }

  int _brandRank = 0;

  /// Клеймо Бездны — добровольная сложность, выставленная на следующий спуск
  /// (GDD §2.5): мобы крепче, добычи и Эха больше.
  ///
  /// Хранится у игрока, а не у наёмника: это его решение перед каждым
  /// спуском, а не свойство конкретного бойца. В контракт уходит снимок.
  int get brandRank => _brandRank.clamp(0, brandRankUnlocked);

  /// Наибольший открытый ранг: Клеймо открывается достижением глубины, а не
  /// покупкой. Рекорд подтверждает, что игрок там уже был.
  /// Лучшая глубина, взятая на каждом ранге Клейма.
  ///
  /// Нужна затем же, зачем рекорд: ранг открывается достижением. Но глубина
  /// выходит на плато (замер `--campaign 50`), и после пятого ранга привязать
  /// лестницу к рекорду уже нельзя — дальше открывает ДЕЛО на самом ранге.
  final Map<int, int> bestDepthByBrand;

  /// Наибольший открытый ранг.
  ///
  /// До конца списка глубин — по рекорду. Дальше: ранг N + 1 открыт, если на
  /// ранге N наёмник дошёл до `brandProofDepth`. Так плато превращается в
  /// лестницу: глубже уже не станет, а сложнее — станет.
  int get brandRankUnlocked {
    final byDepth = Curves.brandRankUnlocked(maxDepthEver);
    var rank = byDepth;

    while (rank < Curves.brandMaxRank &&
        rank >= Curves.brandRanksByDepth &&
        (bestDepthByBrand[rank] ?? 0) >= Curves.brandProofDepth) {
      rank++;
    }
    return rank;
  }

  /// Что нужно сделать для следующего ранга. `null` — открыто всё.
  ///
  /// Две разные причины, и игрок обязан видеть, какая из них его держит:
  /// либо не хватает рекорда, либо не доказан текущий ранг.
  ({int depth, int? atBrand})? get nextBrandRequirement {
    final unlocked = brandRankUnlocked;
    if (unlocked >= Curves.brandMaxRank) return null;

    if (unlocked < Curves.brandRanksByDepth) {
      final depth = Curves.brandNextUnlockDepth(maxDepthEver);
      if (depth != null) return (depth: depth, atBrand: null);
    }
    return (depth: Curves.brandProofDepth, atBrand: unlocked);
  }

  /// Ранги, доказанные делом. Каждый даёт очко дерева пассивок — то, ради
  /// чего лестница вообще существует: на плато расти больше нечему.
  int get provenBrandRanks {
    var proven = 0;
    for (final entry in bestDepthByBrand.entries) {
      if (entry.key > 0 && entry.value >= Curves.brandProofDepth) proven++;
    }
    return proven;
  }

  /// Глубина, на которой откроется следующий ранг. `null` — открыто всё.
  int? get brandNextUnlockDepth => Curves.brandNextUnlockDepth(maxDepthEver);

  /// Ставит Клеймо. Ранг выше открытого не ставится — молча обрезать его
  /// значило бы соврать игроку о том, на чём он пошёл вниз.
  bool setBrandRank(int rank) {
    if (rank < 0 || rank > brandRankUnlocked) return false;
    _brandRank = rank;
    return true;
  }

  /// Сундук Заставы.
  final List<Item> stash = [];

  /// Осколки аффиксов. То, что игрок несёт через все раны (GDD §5.3).
  final List<Shard> shards = [];

  /// Контракты, чья добыча ещё не забрана.
  final List<Contract> contracts = [];

  /// Рекорд глубины. Меняется только собственным ходом игры — снаружи его
  /// можно лишь восстановить из сейва через конструктор.
  int get maxDepthEver => _maxDepthEver;
  int _maxDepthEver;

  bool get hasUncollectedHaul =>
      contracts.any((c) => c.state == ContractState.awaitingCollection);

  /// Есть ли наёмник, который прямо сейчас в бездне.
  /// Есть ли наёмник, который прямо сейчас в бездне — идёт или стоит на
  /// развилке. Стоящий тоже занят: слот отправки он не освобождает.
  bool get hasActiveDescent => contracts.any((c) =>
      c.state == ContractState.descending || c.state == ContractState.atFork);

  /// Переводит контракты, чьё время вышло, в «ждёт получения».
  ///
  /// Вызывается при каждом возвращении в игру и по таймеру на экране.
  /// Возвращает те, что закончились именно сейчас, — по ним UI показывает
  /// «наёмник погиб», а не молча меняет кнопку.
  List<Contract> refreshContracts(DateTime now) {
    final finished = <Contract>[];
    final utc = now.toUtc();

    for (final contract in contracts) {
      // Догоняем всё, что случилось, пока приложение было закрыто. Циклом, а
      // не одним шагом: за ночь наёмник успевает дойти до развилки, простоять
      // весь бюджет и доспуститься по приказу — три перехода подряд, и любой
      // пропущенный оставил бы контракт в состоянии, которого не было.
      var guard = 0;
      while (guard++ < 64) {
        if (contract.state == ContractState.atFork) {
          if (!_expireFork(contract, utc)) break;
          continue;
        }
        if (contract.state != ContractState.descending) break;

        final endsAt = contract.segmentEndsAtUtc;
        if (endsAt == null || utc.isBefore(endsAt)) break;

        if (contract.result!.awaitingFork) {
          // Наёмник дошёл до развилки и встал. Игровое время замирает
          // ровно здесь, а не в момент, когда игрок откроет приложение.
          contract
            ..state = ContractState.atFork
            ..pauses.add(ForkPause(endsAt));
          continue;
        }

        contract.state = ContractState.awaitingCollection;
        finished.add(contract);
        break;
      }
    }
    return finished;
  }

  /// Дождался ли наёмник. Если нет — он перестаёт ждать НАСОВСЕМ и доходит
  /// остаток спуска сам, по приказу.
  ///
  /// Насовсем — потому что не дождаться можно только в отсутствие игрока, а
  /// вставать на каждой следующей развилке ради отсутствующего значит
  /// растягивать восьмиминутный спуск до получаса. Замер общего бюджета на
  /// весь спуск дал 1 ч 40 мин простоя за двадцать спусков — и при этом
  /// вовлечённый игрок исчерпывал бы его раньше отсутствующего.
  ///
  /// Так отсутствие стоит ровно 45 секунд за спуск, а присутствие не стоит
  /// ничего: наказывать за отсутствие в idle-игре нельзя, можно только
  /// вознаграждать присутствие.
  bool _expireFork(Contract contract, DateTime utc) {
    final arrived = contract.forkArrivedAtUtc;
    if (arrived == null) return false;

    final waiting = utc.difference(arrived).inMilliseconds / 1000.0;
    if (waiting < Tuning.forkWaitSeconds) return false;

    contract
      ..pauses.last.seconds = Tuning.forkWaitSeconds
      ..forkWaitingSpent = true
      ..state = ContractState.descending;

    _simulateSegment(contract, pause: false);
    return true;
  }

  // --- Таверна --------------------------------------------------------------

  void refreshTavern(Rng rng) {
    roster.refreshCandidates(
      rng,
      tavernLevel: outpost.levelOf(Building.tavern),
      count: outpost.tavernCandidates,
    );
  }

  /// Задаток за наёмника с учётом рекорда. Единственное место, где эта цена
  /// считается: экран найма и проверка кошелька обязаны читать одно число.
  double hireCostOf(Mercenary m) =>
      m.id == _volunteer?.id
          ? 0.0
          : Roster.hireCost(m.rank, maxDepthEver: maxDepthEver);

  // --- Доброволец -----------------------------------------------------------

  /// Игрок не может сделать ход: наёмников нет, добыча не ждёт, и на самого
  /// дешёвого не хватает.
  ///
  /// Это состояние достижимо честной игрой — новая игра начинается с нулём
  /// золота, и отозванный на втором этаже наёмник приносит меньше задатка.
  /// Заработать без наёмника нельзя, значит игра кончилась, не сказав об этом.
  ///
  /// Наёмник, ушедший вниз, из [Roster.deployed] не уходит до получения
  /// добычи — поэтому «ждёт добыча» отдельной проверки не требует: пока
  /// контракт не закрыт, ход у игрока есть.
  bool get isStranded =>
      roster.reserve.isEmpty &&
      roster.deployed.isEmpty &&
      gold < Roster.hireCost(MercRank.ragged);

  Mercenary? _volunteer;

  /// Доброволец — Оборванец, которого Таверна отдаёт даром.
  ///
  /// Появляется, только пока [isStranded]: в расселину всегда есть кому пойти
  /// от отчаяния, и это единственный ход, который игрок не может потерять.
  /// Даром — а не за полцены: скидка от состояния кошелька превратила бы цену
  /// найма в фикцию.
  ///
  /// Считается от числа павших, а не от случайного зерна: тот же доброволец
  /// после перезапуска, и в сейве его хранить не нужно.
  Mercenary? get volunteer {
    if (!isStranded) return _volunteer = null;
    return _volunteer ??= MercFactory.roll(
      Rng.stream(roster.fallen.length, 0, 0, RngPurpose.tavern),
      idPrefix: 'volunteer',
      rank: MercRank.ragged,
    );
  }

  /// Кандидаты Таверны вместе с добровольцем. Экран найма обязан читать
  /// именно этот список: `roster.candidates` не знает про добровольца.
  List<Mercenary> get tavernCandidates {
    final free = volunteer;
    return [if (free != null) free, ...roster.candidates];
  }

  bool hire(Mercenary m) {
    final cost = hireCostOf(m);
    if (gold < cost) return false;
    gold -= cost;
    roster.hire(m);
    if (m.id == _volunteer?.id) _volunteer = null;
    return true;
  }

  bool upgradeBuilding(Building b) {
    if (!outpost.canUpgrade(b, maxDepthEver: maxDepthEver)) return false;
    final cost = outpost.upgradeCost(b);
    if (gold < cost) return false;
    gold -= cost;
    outpost.upgrade(b, maxDepthEver: maxDepthEver);
    return true;
  }

  /// Открыт ли следующий уровень постройки достигнутой глубиной.
  bool canUpgradeBuilding(Building b) =>
      outpost.canUpgrade(b, maxDepthEver: maxDepthEver);

  // --- Контракт -------------------------------------------------------------

  /// Отправляет наёмника вниз и сразу считает весь спуск.
  ///
  /// Симуляция детерминирована и дешёвая (сотни ранов в доли секунды), поэтому
  /// результат известен целиком в момент отправки. Игроку он раскрывается по
  /// мере «прохождения» — журнал отматывается по времени. Это же даёт точное
  /// время гибели для локального уведомления и делает офлайн-догонялку
  /// тривиальной: не досимулировать, а просто отмотать дальше.
  Contract deploy(
    Mercenary m, {
    required int seed,
    int? brandRank,
    DateTime? now,
    ForkPolicy forkPolicy = ForkPolicy.loot,
    bool rift = false,
  }) {
    // Клеймо по умолчанию — то, что выставил игрок. Явный аргумент оставлен
    // для балансировщика: ему нужно гонять ранги, не трогая профиль.
    final brand = brandRank ?? this.brandRank;

    roster.deploy(m, limit: deploySlots);

    // СБОРКА ИГРОКА УХОДИТ ВНИЗ КАК ЕСТЬ.
    //
    // Раньше отправка пересобирала снаряжение заново — «наёмник берёт лучшее
    // из сундука», — и надетое игроком заменялось тем, что выше по оценке.
    // Живой прогон дал это прямо: «билд, который ты собрал на наёмника,
    // должен оставаться». И он прав: оценка не знает, зачем игрок надел
    // именно это кольцо, а игрок знает.
    //
    // Досбор остался, но только в ПУСТЫЕ слоты: новичок, ни разу не
    // открывавший сборку, всё равно уходит вниз одетым, а тот, кто собирал
    // руками, получает ровно то, что собрал.
    //
    // Реликты не берутся вовсе: они меняют правила боя, и это решение игрока.
    m.gear.equipFrom(stash,
        base: Tuning.heroBase,
        depth: 1,
        loadout: BuildPower.loadoutOf(m.abilities),
        onlyEmpty: true,
        skipRelics: true);

    // Разлом дня: сид общий для всех и на все сутки, значит перекатить его,
    // закрыв приложение, нельзя.
    final today = rift ? DailyRift.on(now ?? DateTime.now()) : null;

    final contract = Contract(
      mercenary: m,
      seed: today?.seed ?? seed,
      brandRank: brand,
      startedAtUtc: (now ?? DateTime.now()).toUtc(),
      loadout: m.gear.copy(),
      abilities: m.abilities,
      echoTreeBonus: outpost.descentPowerBonus,
      echoNodes: tree.bought,
      passiveNodes: passives.allocated,
      // Верёвка плюс узлы «Бездны», одним числом и снимком: рекорд может
      // вырасти, пока наёмник внизу, а повтор обязан начаться там же, где
      // начался посчитанный ран.
      startDepthBonus: startDepthBonus + startDepth - 1,
      forkPolicy: forkPolicy,
      outpost: outpostSnapshot,
      riftDay: today?.day,
    );

    // Сутки засчитываются в момент ОТПРАВКИ, а не забора добычи. Иначе игрок,
    // не забравший вчерашний разлом, сегодня попал бы в него второй раз.
    if (today != null) riftDoneOn = today.day;

    // Профиль спуска собирается ИЗ СНИМКА контракта — тем же
    // `replayProfile()`, которым его собирает повтор и каждый следующий
    // отрезок. Один источник: отрезки считаются много раз за спуск, и любая
    // вторая сборка профиля рано или поздно разошлась бы с первой.
    _simulateSegment(contract);

    // Отрезок посчитан целиком прямо сейчас, но игроку он открывается не
    // раньше, чем наёмник до его конца дошёл бы. Контракт остаётся в спуске:
    // ожидание — это и есть idle-часть цикла, без неё «забрать добычу»
    // перестаёт быть отдельным действием и поводом вернуться.
    contract.state = ContractState.descending;

    contracts.add(contract);
    return contract;
  }

  /// Пересчитывает незаконченные спуски после загрузки сохранения.
  ///
  /// Сохранение хранит решения на развилках, но не результат симуляции: спуск
  /// есть функция от снимка, сида и списка решений, и держать в файле ещё и
  /// вычисленный из них отрезок значило бы держать второй источник правды —
  /// тот, который расходится первым.
  ///
  /// Без этого шага наёмник, застигнутый сохранением на развилке, после
  /// загрузки стоял бы неизвестно на какой: в контракте есть состояние
  /// «ждёт», но нет самих путей.
  void restoreContracts() {
    for (final contract in contracts) {
      if (contract.state != ContractState.descending &&
          contract.state != ContractState.atFork) {
        continue;
      }
      _simulateSegment(contract, pause: !contract.forkWaitingSpent);
    }
  }

  /// Считает спуск от начала до ближайшей неразрешённой развилки.
  ///
  /// Именно от начала, а не «с текущего места»: спуск есть функция от снимка,
  /// сида и списка решений, и полный пересчёт даёт тот же результат тик в тик
  /// за три-шесть миллисекунд. Хранить и восстанавливать состояние симуляции
  /// пришлось бы в памяти, в сохранении и в повторе — три места, каждое из
  /// которых рано или поздно разошлось бы с остальными.
  ///
  /// [pause] = `false` доводит спуск до конца по приказу: так добирается ран,
  /// у которого кончился бюджет ожидания.
  void _simulateSegment(Contract contract, {bool pause = true}) {
    final profile = contract.replayProfile();

    contract.result = DescentSimulator(
      profile: profile,
      seed: contract.seed,
      brandRank: contract.brandRank,
      backpackCapacityOverride: contract.mercenary.backpackSlots,
      salvageRate: contract.outpost.salvageRate,
      outpostLootQuality: contract.outpost.lootQuality,
      outpostLootQuantity: contract.outpost.lootQuantity,
      restHealBonus: contract.outpost.restHealBonus,
      forkPolicy: contract.forkPolicy,
      forkChoices: List.of(contract.forkChoices),
      pauseAtUnchosenFork: pause,
      riftModifier: contract.riftModifier,
    ).run();

    // Конец отрезка по настенным часам. Для отрезка, упёршегося в развилку,
    // это момент, когда наёмник до неё дойдёт; для последнего — момент
    // гибели. Уведомление ставится на него в обоих случаях: игроку одинаково
    // нужно знать и «он на развилке», и «он погиб».
    contract.segmentEndsAtUtc = contract.startedAtUtc.add(Duration(
      milliseconds:
          ((contract.result!.totalSeconds + contract.waitedSeconds) * 1000)
              .round(),
    ));
  }

  /// Решение игрока на развилке: [option] — индекс пути в `Fork.options`.
  ///
  /// Возвращает `false`, если наёмник не стоит на развилке или путь такой
  /// не предлагался.
  bool chooseFork(Contract contract, int option, DateTime now) {
    if (!contract.atFork) return false;
    final fork = contract.pendingFork;
    // Третий путь тоже принимается — он и существует только здесь. Приказ его
    // выбрать не может: у него в руках лишь `fork.options`, а смелый путь
    // лежит отдельным полем.
    if (fork == null || option < 0 || option >= fork.allOptions.length) {
      return false;
    }

    // Простой засчитывается в момент решения: до этой секунды наёмник стоял,
    // и игровое время спуска не шло.
    // Пауза закрывается моментом решения: до этой секунды наёмник стоял, и
    // игровое время спуска не шло.
    contract.pauses.last.seconds =
        now.toUtc().difference(contract.pauses.last.startUtc).inMilliseconds /
            1000.0;
    contract
      ..state = ContractState.descending
      ..forkChoices.add(option);

    _simulateSegment(contract);
    return true;
  }

  /// Закрывает контракт по воле игрока: наёмник разворачивается и идёт наверх.
  ///
  /// GDD §8: «контракт можно закрыть вручную в любой момент; Эхо начисляется
  /// полностью, добыча возвращается — наказывать не за что, а застревание в
  /// неудачном ране бесит». Штрафа нет и здесь: спуск обрывается там, где
  /// наёмник сейчас.
  ///
  /// Ран пересчитывается тем же сидом и тем же снимком до текущего момента —
  /// это тот же повтор, что показывает боевой экран, и он совпадает с ним тик
  /// в тик. Брать «первые N этажей» из уже посчитанного результата было бы
  /// вторым источником правды: добыча лежит в рюкзаке одним списком, и какие
  /// предметы наёмник нашёл до этой секунды, из него не восстановить.
  ///
  /// Если наёмник к этому моменту уже погиб — отзывать некого: контракт
  /// закрывается его смертью, как и должен.
  bool recall(Contract contract, DateTime now) {
    // Стоящего на развилке отозвать МОЖНО. Иначе игрок, которому спуск уже
    // не нравится, обязан сперва выбрать путь и только потом разворачивать
    // наёмника — то есть сделать ход, которого он делать не хотел.
    if (!contract.descending && !contract.atFork) return false;

    // Игровое время, а не настенное: стоя на развилке, наёмник не проходит
    // этажи, и разница дат отматывала бы спуск дальше, чем он ушёл.
    final elapsed = contract.simSecondsAt(now);

    final driver = DescentDriver(
      profile: contract.replayProfile(),
      seed: contract.seed,
      brandRank: contract.brandRank,
      backpackCapacityOverride: contract.mercenary.backpackSlots,
      salvageRate: contract.outpost.salvageRate,
      outpostLootQuality: contract.outpost.lootQuality,
      outpostLootQuantity: contract.outpost.lootQuantity,
      restHealBonus: contract.outpost.restHealBonus,
      forkPolicy: contract.forkPolicy,
      // Отзыв — это тот же повтор, что показывает боевой экран, и он обязан
      // быть тем же спуском: снимок, сид, решения на развилках и разлом дня.
      // Без двух последних наёмник возвращался бы из другого спуска — с
      // добычей, которой игрок не видел.
      forkChoices: List.of(contract.forkChoices),
      riftModifier: contract.riftModifier,
    );

    var guard = 0;
    while (!driver.finished &&
        driver.elapsedSeconds < elapsed &&
        ++guard <= 2000000) {
      driver.tick();
    }
    driver.recall();

    contract
      ..result = driver.result
      ..state = ContractState.awaitingCollection
      ..segmentEndsAtUtc = now.toUtc();
    return true;
  }

  /// Забрать добычу. До этого момента игрок не получает НИЧЕГО из рана —
  /// ни золота, ни предметов. Это и есть обязательный повод вернуться в игру.
  ///
  /// Эхо начисляется здесь же: контракт закрывается целиком, одним действием.
  Haul collect(Contract contract) {
    if (contract.state != ContractState.awaitingCollection) {
      throw StateError('Контракт не ждёт получения: ${contract.state}');
    }
    final result = contract.result!;
    final haul = result.haul;
    lastStashOverflow = 0;

    gold += haul.gold;
    echo += result.echo;
    // Снаряжение возвращается В СУНДУК СРАЗУ и целиком: наёмник его не
    // снимал и не менял, а слоты под него в сундуке освободились в тот
    // момент, когда игрок его надел. Класть его в разбор значило бы
    // заставлять игрока заново решать про собственную сборку.
    stash.addAll(contract.mercenary.gear.unequipAll());

    // Находки — в разбор. Это и есть выбор, ради которого рюкзак стал
    // бесконечным: что из принесённого достойно места в сундуке.
    pendingLoot.addAll(haul.items);

    // Осколки с распылённого. Верстак ограничен, и не влезшее теряется —
    // это и есть повод его улучшать. Молча терять нельзя: счётчик уходит
    // в отчёт по контракту.
    //
    // Узел древа «Осколок памяти» вмещает один сверх любого потолка. В GDD
    // §8.3 он звучал как «сохранить осколок при смерти», но у нас осколки
    // и так лежат на Заставе и смерть их не трогает — терять их может только
    // полный Верстак. Узел спасает ровно от этого.
    final spare = tree.keepsShard ? 1 : 0;
    for (final shard in haul.shards) {
      if (shards.length < outpost.shardCapacity + spare) {
        shards.add(shard);
      } else {
        haul.shardsLost++;
      }
    }
    _trimStash();

    // Разлом платит Эхом вдвое и ведёт свою запись глубины.
    //
    // Эхом, а не золотом: оно идёт в древо и остаётся навсегда, а «зайти
    // завтра» должно окупаться тем, что не упирается ни в сундук, ни в
    // выкупленную Заставу.
    if (contract.isRift) {
      echo += result.echo;
      if (result.maxDepth > riftBestDepth) riftBestDepth = result.maxDepth;
    }

    if (result.maxDepth > _maxDepthEver) _maxDepthEver = result.maxDepth;

    // Рекорд ранга — то, чем открывается следующая ступень лестницы.
    final atBrand = contract.brandRank;
    if (result.maxDepth > (bestDepthByBrand[atBrand] ?? 0)) {
      bestDepthByBrand[atBrand] = result.maxDepth;
    }

    haul.collected = true;
    contract.state = ContractState.closed;
    roster.bury(contract.mercenary);
    contracts.remove(contract);

    // Счётчики истории. Профиль хранит текущее состояние, а не прошлое:
    // «закройте десять контрактов» по нему не проверить, и считать это
    // приходится в единственном месте, где контракт закрывается.
    quests.runsCompleted++;
    quests.relicsFound += haul.relics;

    // Задания проверяются здесь же, а не при отправке: спуск считается
    // заранее, но игроку он ещё не принадлежит. Награда за то, чего игрок
    // не забрал, пришла бы раньше самой добычи.
    lastClosedQuests = checkQuests(
      result: result,
      loadout: contract.abilities,
    );

    return haul;
  }

  // --- Крафт ----------------------------------------------------------------

  /// Разбирает предмет: выбранный аффикс становится осколком, предмет исчезает.
  ///
  /// Возвращает `null`, если хранилище осколков забито: молча потерять и
  /// предмет, и осколок — худший из возможных исходов операции.
  Shard? extractShard(Item item, int affixIndex) {
    if (!stash.contains(item)) return null;
    if (shards.length >= outpost.shardCapacity) return null;

    final shard = Crafting.extract(item, affixIndex);
    stash.remove(item);
    shards.add(shard);
    return shard;
  }

  /// Впечатывает осколок в предмет из сундука.
  ///
  /// `slotIndex` = null — в свободный слот; иначе перезапись указанного.
  /// Осколок тратится в любом случае: это и есть риск перезаписи.
  Item? imprintShard(
    Item item,
    Shard shard, {
    int? slotIndex,
    Rng? rng,
  }) {
    final index = stash.indexOf(item);
    if (index < 0 || !shards.contains(shard)) return null;
    if (!Crafting.canImprint(item, shard)) return null;
    if (slotIndex == null &&
        !Crafting.hasFreeSlot(item, treeBonus: affixSlotBonus)) {
      return null;
    }

    final result = Crafting.imprint(
      item,
      shard,
      slotIndex: slotIndex,
      salvageChance: outpost.shardSalvageOnOverwrite,
      treeBonus: affixSlotBonus,
      rng: rng,
    );

    shards.remove(shard);
    stash[index] = result.item;

    final displaced = result.displaced;
    if (displaced != null && shards.length < outpost.shardCapacity) {
      shards.add(displaced);
    }
    return result.item;
  }

  /// Перекатывает значение аффикса за золото.
  Item? rerollAffix(Item item, int affixIndex, Rng rng) {
    final index = stash.indexOf(item);
    if (index < 0) return null;
    if (affixIndex < 0 || affixIndex >= item.affixes.length) return null;

    final cost = Crafting.rerollCost(item, affixIndex);
    if (gold < cost) return null;

    gold -= cost;
    final next = Crafting.reroll(item, affixIndex, rng,
        floorPercentile: outpost.rerollFloorPercentile);
    stash[index] = next;
    return next;
  }

  /// Углубляет реликт за золото. Выше достигнутой глубины — нельзя.
  Item? deepenRelic(Item item) {
    final index = stash.indexOf(item);
    if (index < 0) return null;
    if (!Crafting.canDeepen(item, _maxDepthEver)) return null;

    final cost = Crafting.deepenCost(item);
    if (gold < cost) return null;

    gold -= cost;
    final next = Crafting.deepen(item, _maxDepthEver);
    stash[index] = next;
    return next;
  }

  /// Во сколько золота обратится предмет, если его распылить.
  ///
  /// Тем же курсом, что и вытесненный из полного сундука: два способа
  /// избавиться от вещи, дающие разные деньги, — это две разные игры.
  double salvageValue(Item item) =>
      Curves.goldBase * Curves.itemScale(item.ilvl) * outpost.salvageRate;

  /// Распыляет предмет из сундука в золото. Возвращает полученное или `null`,
  /// если предмета в сундуке нет.
  ///
  /// Нужно не ради денег: без этого игрок не может освободить место сам —
  /// сундук чистится только переполнением, то есть за него решает игра.
  double? salvage(Item item) {
    if (!stash.remove(item)) return null;
    final value = salvageValue(item);
    gold += value;
    return value;
  }

  /// Сундук Заставы конечен: излишек уходит в золото по курсу Алтаря.
  /// Переполнение не наказывает — игрок теряет возможность, а не прогресс.
  /// Сколько вещей ушло в переплавку из-за нехватки места при последнем
  /// получении добычи.
  ///
  /// Молча продавать возвращённое нельзя: игрок отправлял наёмника с этими
  /// вещами и ждёт их обратно. Если места не хватило — об этом надо сказать,
  /// а не оставить его пересчитывать сундук.
  int lastStashOverflow = 0;

  /// Предохранитель на случай, когда сундук УМЕНЬШИЛСЯ.
  ///
  /// Штатного переполнения больше нет: находки ждут в разборе, и сверх
  /// вместимости в сундук ничего не кладётся. Но снаряжение возвращается в
  /// него безусловно, и если игрок успел разобрать добычу под завязку, пока
  /// наёмник был внизу, места может не хватить. Тогда лишнее уходит в
  /// золото — как и раньше, но теперь это редкий край, а не правило.
  void _trimStash() {
    stash.sort((a, b) => b.ilvl.compareTo(a.ilvl));
    while (stash.length > outpost.stashSlots) {
      gold += salvageValue(stash.removeLast());
      lastStashOverflow++;
    }
  }

  // --- Разбор добычи ---------------------------------------------------------

  /// Оставить вещь: она едет в сундук. `false` — сундук полон.
  bool keepLoot(Item item) {
    if (!pendingLoot.contains(item)) return false;
    if (stashRoom <= 0) return false;

    pendingLoot.remove(item);
    stash.add(item);
    return true;
  }

  /// Переплавить: золото и, с редкого, осколок.
  ///
  /// Осколок кладётся по тем же правилам, что и при получении добычи:
  /// Верстак ограничен, и не влезшее теряется.
  bool meltLoot(Item item) {
    if (!pendingLoot.remove(item)) return false;

    gold += salvageValue(item);

    if (item.rarity.rank < Rarity.rare.rank || item.affixes.isEmpty) {
      return true;
    }
    var best = 0;
    for (var i = 1; i < item.affixes.length; i++) {
      if (item.affixes[i].percentile > item.affixes[best].percentile) best = i;
    }
    final spare = tree.keepsShard ? 1 : 0;
    if (shards.length < outpost.shardCapacity + spare) {
      shards.add(Crafting.extract(item, best));
    }
    return true;
  }

  /// Продать за золото. Отличается от переплавки тем, что осколка не даёт,
  /// зато платит больше: осколок — это материал, и он чего-то стоит.
  bool sellLoot(Item item) {
    if (!pendingLoot.remove(item)) return false;
    gold += salvageValue(item) * Tuning.sellBonus;
    return true;
  }

  /// Разобрать всё за игрока: лучшее — в сундук, остальное — в золото.
  ///
  /// Игроку предлагается кнопкой «разобрать остальное», а балансировщику
  /// нужна как модель среднего игрока: он-то разбирает, а замер должен
  /// мерить игру, в которую играют.
  void autoSortLoot() {
    pendingLoot.sort((a, b) => b.ilvl.compareTo(a.ilvl));
    while (pendingLoot.isNotEmpty) {
      final item = pendingLoot.first;
      if (stashRoom > 0) {
        keepLoot(item);
      } else {
        sellLoot(item);
      }
    }
  }
}
