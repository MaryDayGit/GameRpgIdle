import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';

/// Экран, на котором живёт шаг обучения.
///
/// Шаг привязан к экрану, а не к порядковому номеру: игрок уходит в Сборку и
/// возвращается, и подсказка обязана ждать его там, где ей место. Сценарий,
/// который просто считает шаги, при первом же переходе показывает стрелку в
/// пустоту.
enum TutorialScreen { outpost, build, journal, loot }

/// Что игра открывает не сразу.
///
/// Первый экран новой игры показывал пять переходов, восемь построек, Таверну
/// и Клеймо — всё то, чем нечего делать, пока никто не спускался. Разделы
/// появляются тогда, когда у них появляется смысл: сундук — когда в нём есть
/// вещь, древо — когда есть Эхо, постройки — когда есть золото.
enum Feature { tavern, stash, forge, quests, echoTree, passiveTree, buildings, rift }

/// Состояние игры глазами обучения.
///
/// Отдельный объект, потому что шагу на экране Сборки нужен КОНКРЕТНЫЙ
/// наёмник — тот, которого открыли, — а шагу на Заставе хватает профиля.
class TutorialFacts {
  const TutorialFacts({
    required this.profile,
    required this.now,
    this.mercenary,
  });

  final PlayerProfile profile;
  final DateTime now;

  /// Наёмник открытого экрана Сборки. `null` — экран не тот.
  final Mercenary? mercenary;

  /// О ком идёт речь: открытый наёмник или первый в резерве.
  Mercenary? get subject =>
      mercenary ??
      (profile.roster.reserve.isEmpty ? null : profile.roster.reserve.first);

  /// Сколько спусков игрок уже довёл до конца.
  ///
  /// Читается и по счётчику, и по рекорду глубины. Счётчик точнее, но он
  /// появился позже рекорда: в сейве, пережившем обновление, он равен нулю
  /// при живом рекорде — а обучение не должно принимать такого игрока за
  /// новичка и показывать ему стрелку на первого наёмника.
  int get runs {
    final counted = profile.quests.runsCompleted;
    if (counted == 0 && profile.maxDepthEver > 0) return 1;
    return counted;
  }
}

typedef TutorialCheck = bool Function(TutorialFacts);

/// Один шаг сценария.
class Beat {
  const Beat({
    required this.id,
    required this.screen,
    required Phrase title,
    required Phrase text,
    required this.ready,
    required this.stale,
    this.anchor,
    this.byTap = false,
    Phrase? hint,
  })  : _title = title,
        _text = text,
        _hint = hint;

  final String id;
  final TutorialScreen screen;

  /// Метка, на которую указывает стрелка. `null` — шаг без указателя.
  final String? anchor;

  final Phrase _title;
  final Phrase _text;
  final Phrase? _hint;

  /// Показывать ли шаг прямо сейчас.
  final TutorialCheck ready;

  /// Шаг больше не о чем: игрок ушёл дальше, ничего не заметив. Такие шаги
  /// гасятся молча — обучение не догоняет того, кто его обогнал.
  final TutorialCheck stale;

  String get title => _title.text;
  String get text => _text.text;

  /// Что игрок должен сделать. `null` — шаг объясняющий, он закрывается
  /// кнопкой «Дальше».
  String? get hint => _hint?.text;

  /// Шаг-задание: закрывается действием, а не кнопкой.
  bool get isTask => _hint != null;

  /// Задание закрывается самим нажатием на подсвеченное место, а не тем, что
  /// изменилось в игре.
  ///
  /// Нужно там, где след в состоянии отсутствует: «откройте Сборку» не меняет
  /// в профиле ни одного числа. Везде, где след есть, он и используется —
  /// нажатие может промахнуться, а отправленный вниз наёмник не может.
  final bool byTap;
}

/// Что показать сейчас и что пора погасить.
class TutorialPick {
  const TutorialPick(this.beat, this.retire);

  /// Шаг для этого экрана. `null` — показывать нечего.
  final Beat? beat;

  /// Шаги, потерявшие смысл: их надо запомнить пройденными, иначе они
  /// всплывут через десять спусков.
  final List<String> retire;
}

/// Сценарий первого запуска.
///
/// ## Почему не линейный список «нажмите сюда»
///
/// Обучение здесь — по-прежнему функция от состояния игры (`tutorial.dart`),
/// просто теперь она умеет показывать пальцем. У каждого шага есть условие
/// [Beat.ready] — когда он к месту — и [Beat.stale] — когда он опоздал.
/// Отсюда свойства, которых у сценария с указателем на шаг не бывает:
///
///  * его нельзя рассинхронизировать. Игра, закрытая посреди спуска и
///    открытая через сутки, покажет тот шаг, который подходит СЕЙЧАС;
///  * его нельзя запереть. Игрок, сделавший действие раньше подсказки,
///    подсказки не увидит вовсе;
///  * его нельзя обойти половиной: шаг-задание закрывается только тем, что
///    игрок и правда сделал дело. Кнопки «Дальше» у него нет.
///
/// ## О языке
///
/// Правило то же, что у подсказок: **в шаге нет ни одного слова, которого
/// игрок не встретил бы на экране**. Термины игры («Эхо», «Клеймо»,
/// «Осколок») остаются — это имена вещей, и каждое объясняется там, где
/// впервые попадается.
class Onboarding {
  Onboarding._();

  /// После скольких забранных спусков обучение отпускает игрока насовсем.
  ///
  /// Два: первый показывает круг целиком — отправил, дождался, забрал,
  /// разобрал. Второй показывает, ради чего этот круг — собрать наёмника
  /// лучше предыдущего. Третий не показал бы ничего нового.
  static const runsTaught = 2;

  /// Показывается ли на первом запуске вступление.
  static bool needsIntro(Set<String> seen) => !seen.contains(introId);

  static const introId = 'intro';

  /// Все шаги по порядку. Порядок — это и есть сценарий.
  static final List<Beat> beats = [
    Beat(
      id: 'roster',
      screen: TutorialScreen.outpost,
      anchor: anchorMerc,
      title: const Phrase('Это ваш наёмник', 'This is your mercenary'),
      text: const Phrase(
        'Он достался даром — дальше за них платят золотом. Ранг, черта и '
            'рюкзак у каждого свои, и больше про него знать нечего: всё '
            'остальное вы дадите ему сами.',
        'This one came free; the rest cost gold. Rank, trait and pack size '
            'are all that separate one from another — everything else, you '
            'hand them yourself.',
      ),
      ready: (f) => f.profile.roster.reserve.isNotEmpty && f.runs == 0,
      stale: (f) => f.runs > 0,
    ),
    Beat(
      id: 'deploy',
      screen: TutorialScreen.outpost,
      anchor: anchorSend,
      title: const Phrase('Отправьте наёмника вниз', 'Send the mercenary down'),
      // Не «снаряжения нет»: наёмник приходит из Таверны в чём-то, и строка
      // над кнопкой честно пишет «Снаряжение 2/9». Пусто не у него, а в
      // сундуке — добавить к тому, что при нём, пока нечего.
      text: const Phrase(
        'Сундук пока пуст, и добавить ему нечего — первый спуск он идёт с '
            'тем, что при нём. Внизу вмешаться уже нельзя: всё решается '
            'здесь, до отправки.',
        'Your stash is empty, so there is nothing to add — the first one '
            'goes down with what they already carry. Once they are below you '
            'cannot step in. It is all decided up here.',
      ),
      hint: const Phrase('Нажмите «Отправить»', 'Tap “Send”'),
      ready: (f) =>
          f.runs == 0 &&
          f.profile.roster.reserve.isNotEmpty &&
          !f.profile.hasActiveDescent &&
          !f.profile.hasUncollectedHaul,
      stale: (f) => f.runs > 0,
    ),
    Beat(
      id: 'descent',
      screen: TutorialScreen.outpost,
      anchor: anchorDescent,
      title: const Phrase('Дальше — без вас', 'From here, without you'),
      text: const Phrase(
        'Спуск идёт по часам, а не по экрану: игру можно закрыть, свернуть, '
            'выключить телефон — он всё равно спускается. Здесь видно, на '
            'каком он этаже, а «Смотреть бой» покажет, что с ним происходит.',
        'The descent runs on the clock, not on the screen. Close the game, '
            'put the phone away — they keep going down. This card says which '
            'floor they are on, and “Watch the fight” shows you how it is '
            'going.',
      ),
      ready: (f) => f.profile.contracts.any((c) => c.descending),
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'fork',
      screen: TutorialScreen.outpost,
      anchor: anchorFork,
      title: const Phrase('Расселина разошлась надвое', 'The rift has split in two'),
      text: const Phrase(
        'Каждые пять этажей расселина расходится надвое. У каждого пути своя '
            'плата и своя награда — плата написана первой. Третий путь даёт '
            'награды обоих и не берёт ничего, кроме того, что вы сейчас '
            'здесь. Не дождётся ответа — пойдёт сам.',
        'Every five floors the rift splits in two. Each path has a price '
            'and a reward, and the price is always written first. The third '
            'path gives both rewards and asks for nothing except that you '
            'are here to take it. Get no answer, and they walk on alone.',
      ),
      hint: const Phrase('Выберите путь', 'Choose a path'),
      ready: (f) => f.profile.contracts.any((c) => c.atFork),
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'collect',
      screen: TutorialScreen.outpost,
      anchor: anchorCollect,
      title: const Phrase('Гибель — это не проигрыш',
          'A death is not a loss'),
      text: const Phrase(
        'Так кончается каждый спуск. Всё, что он успел найти, поднялось '
            'наверх вместе с вестью о смерти, но лежит и ждёт: пока не '
            'заберёте, у вас ничего нет.',
        'Every descent ends this way. Everything they found came up with '
            'the news, and there it sits: until you collect it, none of it '
            'is yours.',
      ),
      hint: const Phrase('Откройте журнал', 'Open the journal'),
      ready: (f) => f.profile.hasUncollectedHaul,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'journal',
      screen: TutorialScreen.journal,
      anchor: anchorJournalCollect,
      title: const Phrase('Чем всё кончилось', 'How it ended'),
      text: const Phrase(
        'Журнал говорит, до какого этажа он дошёл и что его остановило. '
            'Внизу — золото, вещи и Эхо. Эхо приходит только со смертью '
            'наёмника и остаётся с вами навсегда.',
        'The journal says how far down they got and what put them there. '
            'Below that: gold, items, Echo. Echo only ever comes from a '
            'mercenary’s death, and it stays with you for good.',
      ),
      ready: (f) => f.profile.hasUncollectedHaul,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'loot',
      screen: TutorialScreen.loot,
      anchor: anchorLootRow,
      title: const Phrase('Что из этого оставить', 'What to keep'),
      text: const Phrase(
        'Место в сундуке кончается быстрее, чем находки. «Оставить» — в '
            'сундук, «Переплавить» — в золото, «Продать» — тоже в золото, но '
            'дороже и без осколка. Осколок помнит, насколько удачно выпало '
            'свойство, и его можно вставить в вещь получше.',
        'Stash room runs out long before the finds do. “Keep” sends it to '
            'the stash, “Melt” turns it into gold and a shard, “Sell” pays '
            'more gold and no shard. A shard remembers how well a property '
            'rolled — set it into a better item later and it pays out more.',
      ),
      ready: (f) => f.profile.hasPendingLoot,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'stash',
      screen: TutorialScreen.outpost,
      anchor: anchorStash,
      title: const Phrase('Сундук открыт', 'The chest is open'),
      text: const Phrase(
        'Всё оставленное лежит здесь и никуда не денется: гибнет наёмник, а '
            'не Застава. Отсюда вещи попадают на следующего.',
        'Everything you kept is here, and here it stays: mercenaries die, '
            'the Outpost does not. This is where the next one gets dressed.',
      ),
      ready: (f) => f.runs > 0 && f.profile.stash.isNotEmpty,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'echo',
      screen: TutorialScreen.outpost,
      anchor: anchorEcho,
      title: const Phrase('Эхо открыто', 'Echo unlocked'),
      text: const Phrase(
        'Эхо копится между спусками и тратится в древе. Купленное в древе '
            'остаётся навсегда и работает у каждого следующего наёмника — '
            'это и есть то, ради чего предыдущий погиб.',
        'Echo piles up between descents and is spent in the tree. What you '
            'buy there is permanent and works for everyone who comes after — '
            'which is what the last one died for.',
      ),
      ready: (f) => f.profile.echo > 0,
      stale: (f) => f.profile.tree.nodesBought > 0 || f.runs > runsTaught,
    ),
    Beat(
      id: 'quests',
      screen: TutorialScreen.outpost,
      anchor: anchorQuests,
      title: const Phrase('Задания открыты', 'Quests unlocked'),
      text: const Phrase(
        'Новые умения не покупаются — их дают за дела: дойти глубже, одолеть '
            'чудовище, собрать наёмника вокруг одной стихии. Здесь видно, '
            'какое задание ближе всего к закрытию.',
        'New abilities are not for sale — they are earned: get deeper, put '
            'down a monster, build the whole thing around one element. This '
            'screen shows which goal you are closest to.',
      ),
      ready: (f) => f.runs > 0,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'hire',
      screen: TutorialScreen.outpost,
      anchor: anchorTavern,
      title: const Phrase('Наймите следующего', 'Hire the next one'),
      text: const Phrase(
        'Прежний не вернётся — вниз ходят по одному разу. Задаток растёт '
            'вместе с вашим рекордом, поэтому золото стоит тратить, а не '
            'копить: оно дешевеет.',
        'The last one is not coming back — nobody goes down twice. And the '
            'fee climbs with your record, so gold is worth spending rather '
            'than saving: it only gets cheaper.',
      ),
      hint: const Phrase('Наймите наёмника', 'Hire a mercenary'),
      ready: (f) =>
          f.runs > 0 &&
          f.profile.roster.reserve.isEmpty &&
          !f.profile.hasActiveDescent,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'build',
      screen: TutorialScreen.outpost,
      anchor: anchorBuild,
      title: const Phrase('Теперь есть чем снарядить',
          'Now there is something to equip with'),
      text: const Phrase(
        'За «Сборкой» всё, чем вы управляете: девять слотов под вещи, четыре '
            'под умения и приказ на случай, если вас не будет рядом.',
        'Behind “Build” sits everything you control: nine slots for items, '
            'four for abilities, and a standing order for when you are not '
            'around.',
      ),
      hint: const Phrase('Откройте «Сборку»', 'Open “Build”'),
      // Единственный шаг, который закрывается нажатием: открытый экран не
      // оставляет в профиле ни одного числа, по которому его можно узнать.
      byTap: true,
      ready: (f) =>
          f.runs > 0 && f.profile.stash.isNotEmpty && f.subject != null,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'gear',
      screen: TutorialScreen.build,
      anchor: anchorGearGrid,
      title: const Phrase('Оденьте наёмника', 'Equip the mercenary'),
      text: const Phrase(
        'Нажмите на пустой слот — игра покажет, что из сундука в него '
            'годится, и насколько каждая вещь прибавит. Числа наверху меняются '
            'сразу: с ними наёмник и уйдёт вниз.',
        'Tap an empty slot and the game shows what in the stash fits it, '
            'and how much each item adds. The numbers up top move as you go — '
            'those are the numbers they go down with.',
      ),
      // Объясняющий, а не задание, и это решение, а не упрощение. Наёмник
      // приходит из Таверны уже в чём-то — «поставьте вещь в пустой слот»
      // по состоянию не отличить от «он и так одет», и задание либо не
      // закрылось бы никогда, либо закрылось бы само.
      ready: (f) => f.subject != null && f.profile.stash.isNotEmpty,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'abilities',
      screen: TutorialScreen.build,
      anchor: anchorAbilities,
      title: const Phrase('И выберите умения', 'And choose the abilities'),
      text: const Phrase(
        'Умения решают бой сильнее вещей. Активные бьют, пассивные работают '
            'сами, ауры держат ману занятой. Полоса маны над слотами говорит, '
            'потянет ли наёмник выбранное.',
        'Abilities settle a fight more than items do. Active ones strike, '
            'passive ones simply work, auras hold mana in reserve. The mana '
            'line above the slots tells you whether they can carry what you '
            'picked.',
      ),
      ready: (f) =>
          f.subject != null && f.profile.availableAbilities.isNotEmpty,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'forkOrder',
      screen: TutorialScreen.build,
      anchor: anchorForkOrder,
      title: const Phrase(
          'Если вас не будет рядом', 'If you are not around'),
      text: const Phrase(
        'Если вас нет рядом, наёмник простоит на развилке недолго и пойдёт '
            'по этому приказу. Приказ не умеет брать третий путь — он '
            'достаётся только тому, кто пришёл и выбрал сам.',
        'With you away, a mercenary waits at a fork only so long, then '
            'follows this order. An order can never take the third path — '
            'that one is for people who show up and choose.',
      ),
      ready: (f) => f.subject != null,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'buildings',
      screen: TutorialScreen.outpost,
      anchor: anchorBuildings,
      title: const Phrase('Застава открыта', 'The Outpost is open'),
      text: const Phrase(
        'Постройки — единственное, куда идёт золото, и они работают на всех '
            'наёмников сразу: больше места в сундуке, лучше добыча, второй '
            'слот спуска. Уровни выше открываются глубиной, а не деньгами.',
        'Buildings are the only place gold goes, and they pay off for '
            'every mercenary at once: more stash room, better loot, a second '
            'descent slot. Higher levels are opened by depth, not by money.',
      ),
      ready: (f) => f.runs > 0 && f.profile.gold > 0,
      stale: (f) => f.runs > runsTaught,
    ),
    Beat(
      id: 'deployAgain',
      screen: TutorialScreen.outpost,
      anchor: anchorSend,
      title: const Phrase('Отправьте второго', 'Send the second one'),
      text: const Phrase(
        'Этот уйдёт не с первого этажа: верёвка спущена до части вашего '
            'рекорда. Так и растёт глубина — не за один спуск, а за все.',
        'This one does not start from floor one: the rope reaches down to '
            'a share of your record. That is how depth grows — not in a '
            'single descent, but across all of them.',
      ),
      hint: const Phrase('Отправьте наёмника вниз', 'Send the mercenary down'),
      ready: (f) =>
          f.runs == 1 &&
          f.profile.roster.reserve.isNotEmpty &&
          !f.profile.hasActiveDescent &&
          !f.profile.hasUncollectedHaul,
      stale: (f) => f.runs > 1,
    ),
    Beat(
      id: 'passives',
      screen: TutorialScreen.outpost,
      anchor: anchorPassives,
      title: const Phrase('Очки пассивок', 'Passive points'),
      text: const Phrase(
        'Их даёт достигнутая глубина, а не смерть. Дерево большое, и вложить '
            'всё в одно — правильнее, чем размазать: сборка вокруг одной '
            'стихии сильнее ровной.',
        'These come from depth reached, not from dying. The tree is large, '
            'and pouring it all into one branch beats spreading thin — a '
            'build around a single element will always outdo an even one.',
      ),
      ready: (f) => f.profile.passivePointsLeft > 0,
      stale: (f) => f.runs > runsTaught + 1,
    ),
    Beat(
      id: 'forge',
      screen: TutorialScreen.outpost,
      anchor: anchorForge,
      title: const Phrase('В Кузнице лежат осколки', 'Shards wait in the Forge'),
      text: const Phrase(
        'Осколок помнит, насколько удачно выпало свойство. Вставьте его в '
            'вещь получше — и он даст больше. Крафт — единственное, что не '
            'устаревает вместе с вещами.',
        'A shard remembers how well a property rolled. Set it into a '
            'better item and it pays out more. Crafting is the one thing that '
            'does not go stale along with your gear.',
      ),
      ready: (f) => f.profile.shards.isNotEmpty,
      stale: (f) => f.runs > runsTaught + 1,
    ),
    Beat(
      id: 'rift',
      screen: TutorialScreen.outpost,
      anchor: anchorRift,
      title: const Phrase('Разлом дня', 'The daily rift'),
      text: const Phrase(
        'Раз в сутки — спуск по общему для всех расписанию: один модификатор '
            'на каждом этаже и двойное Эхо за него. Это единственное в игре, '
            'чем завтра отличается от сегодня.',
        'Once a day, a descent everyone runs on the same schedule: one '
            'modifier on every floor, and double Echo for putting up with '
            'it. It is the one thing in this game that makes tomorrow differ '
            'from today.',
      ),
      ready: (f) =>
          f.runs >= runsTaught &&
          f.profile.roster.reserve.isNotEmpty &&
          f.profile.riftAvailable(f.now),
      stale: (f) => f.runs > runsTaught + 1,
    ),
    Beat(
      id: 'finale',
      screen: TutorialScreen.outpost,
      title: const Phrase('Дальше вы сами', 'The rest is yours'),
      text: const Phrase(
        'Круг вы прошли целиком: нанять, собрать, отправить, забрать, '
            'вложить. Дальше он повторяется, и каждый раз наёмник уходит '
            'глубже предыдущего. Подсказка о следующем шаге остаётся наверху '
            'Заставы, а «Справка» в углу отвечает на «почему».',
        'That is the whole circle: hire, build, send, collect, invest. From '
            'here it just repeats, and each time someone gets further than '
            'the last. A note about your next step stays at the top of the '
            'Outpost, and “Help” in the corner answers the “why”.',
      ),
      ready: (f) => f.runs >= runsTaught && !f.profile.hasUncollectedHaul,
      stale: (f) => false,
    ),
  ];

  /// Что показать на этом экране и что пора погасить.
  static TutorialPick pick({
    required TutorialFacts facts,
    required Set<String> seen,
    required TutorialScreen screen,
  }) {
    final retire = <String>[];
    Beat? found;

    for (final beat in beats) {
      if (seen.contains(beat.id)) continue;
      if (beat.stale(facts)) {
        retire.add(beat.id);
        continue;
      }
      if (found == null && beat.screen == screen && beat.ready(facts)) {
        found = beat;
      }
    }
    return TutorialPick(found, retire);
  }

  /// Готов ли шаг прямо сейчас. По нему видно, что задание выполнено: шаг,
  /// который перестал быть к месту, — это шаг, который игрок только что
  /// сделал.
  static bool isReady(String id, TutorialFacts facts) {
    for (final beat in beats) {
      if (beat.id == id) return beat.ready(facts);
    }
    return false;
  }

  /// Номер шага в сценарии, с единицы. Ноль — шага нет.
  static int numberOf(String id) {
    for (var i = 0; i < beats.length; i++) {
      if (beats[i].id == id) return i + 1;
    }
    return 0;
  }

  static int get total => beats.length;

  /// Открыт ли раздел игры.
  ///
  /// Ответ считается по состоянию профиля, а не по номеру шага обучения: у
  /// игрока, пропустившего обучение или пришедшего со старым сейвом, открыто
  /// всё сразу, и ни один экран не пропадает из-под пальца.
  static bool shows(
    Feature feature, {
    required PlayerProfile p,
    required bool tutorialDone,
  }) {
    if (tutorialDone) return true;

    return switch (feature) {
      // Таверна прячется только на самом первом спуске — когда золота нет и
      // нанимать всё равно не на что.
      //
      // Пустой резерв открывает её обратно, но лишь когда внизу тоже никого:
      // иначе она вылезала ровно в тот момент, когда игрок отправил своего
      // единственного наёмника, — списком по 250 при нуле золота. Приглашение,
      // которое нельзя принять, хуже отсутствующего.
      Feature.tavern => p.gold > 0 ||
          p.maxDepthEver > 0 ||
          (p.roster.reserve.isEmpty && !p.hasActiveDescent),
      Feature.stash => p.stash.isNotEmpty,
      Feature.quests => p.maxDepthEver > 0,
      Feature.echoTree => p.echo > 0 || p.tree.nodesBought > 0,
      Feature.passiveTree => p.passivePoints > 0,
      Feature.forge => p.shards.isNotEmpty ||
          p.maxDepthEver > 0 ||
          p.outpost.levelOf(Building.forge) > 0,
      Feature.buildings => p.maxDepthEver > 0,
      Feature.rift => p.maxDepthEver > 0,
    };
  }

  // --- Метки на экранах ------------------------------------------------------
  //
  // Строками, а не enum: метку ставит экран, а читает сценарий, и между ними
  // нет общего типа, который стоило бы заводить ради двадцати констант.

  static const anchorMerc = 'outpost.merc';
  static const anchorBuild = 'outpost.build';
  static const anchorSend = 'outpost.send';
  static const anchorDescent = 'outpost.descent';
  static const anchorFork = 'outpost.fork';
  static const anchorCollect = 'outpost.collect';
  static const anchorTavern = 'outpost.tavern';
  static const anchorStash = 'outpost.stash';
  static const anchorForge = 'outpost.forge';
  static const anchorQuests = 'outpost.quests';
  static const anchorEcho = 'outpost.echo';
  static const anchorPassives = 'outpost.passives';
  static const anchorBuildings = 'outpost.buildings';
  static const anchorRift = 'outpost.rift';

  static const anchorGearGrid = 'build.gear';
  static const anchorAbilities = 'build.abilities';
  static const anchorForkOrder = 'build.forkOrder';

  static const anchorJournalCollect = 'journal.collect';
  static const anchorLootRow = 'loot.row';
}
