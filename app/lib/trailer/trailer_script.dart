import '../ui/echo_tree_screen.dart';
import '../ui/forge_screen.dart';
import '../ui/journal_screen.dart';
import '../ui/loot_sort_screen.dart';
import '../ui/mercenary_screen.dart';
import '../ui/onboarding.dart';
import '../ui/passive_tree_screen.dart';
import '../ui/quests_screen.dart';
import '../ui/stash_screen.dart';
import '../ui/strings.dart';
import 'trailer_camera.dart';
import 'trailer_caption.dart';
import 'trailer_director.dart';

/// Сценарий трейлера: круг по всей игре примерно за минуту.
///
/// Порядок не случайный и не «по экранам». Это тот же порядок, которым игра
/// объясняет себя новичку: сначала ЧЕЙ это выбор (нанимаете вы, идёт не вы),
/// потом из чего он состоит, потом чем кончается, и только в конце — сколько
/// в игре содержимого. Ролик, начатый с перечисления двадцати пяти реликтов,
/// отвечает на вопрос, которого зритель ещё не задал.
///
/// Материала здесь больше, чем нужно рилсу: держать кадр дешевле, чем
/// доснимать. Монтаж режет, а не добирает.
///
/// Подписи двуязычные через [Phrase] — снимается тот дубль, на язык которого
/// поставлена игра (`main_trailer.dart`). Кадры при этом не меняются.
List<TrailerBeat> buildTrailerScript() {
  return [
    // --- Крючок. Три секунды на то, чтобы отличиться от всех idle-игр ---
    TrailerBeat(
      shot: const TrailerShot(zoom: 1.06, push: 0.14),
      line: TrailerLine(
        const Phrase(
          'Вы не спускаетесь в бездну сами',
          'You never go down yourself',
        ).text,
      ),
      hold: const Duration(seconds: 3),
      move: const Duration(milliseconds: 400),
    ),
    TrailerBeat(
      shot: const TrailerShot(anchor: Onboarding.anchorMerc, fill: 0.34),
      line: TrailerLine(
        const Phrase(
          'Вы нанимаете тех, кто спускается',
          'You hire the ones who do',
        ).text,
        text: const Phrase(
          'И собираете их так, чтобы они вернулись',
          'And you build them so they come back',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),

    // --- Сборка: из чего состоит решение игрока ---
    TrailerBeat(
      act: (s) async {
        final merc = s.profile.roster.reserve.firstOrNull;
        if (merc == null) return;
        await s
            .open(MercenaryScreen(controller: s.controller, mercenary: merc));
      },
      shot: const TrailerShot(anchor: Onboarding.anchorGearGrid, fill: 0.52),
      line: TrailerLine(
        const Phrase('Девять слотов', 'Nine slots').text,
        text: const Phrase(
          'Вещи падают редко, и каждую есть смысл рассмотреть',
          'Items drop rarely. Every one is worth reading.',
        ).text,
      ),
      hold: const Duration(milliseconds: 2800),
    ),
    TrailerBeat(
      shot: const TrailerShot(anchor: Onboarding.anchorAbilities, fill: 0.46),
      line: TrailerLine(
        const Phrase(
          'Умения решают, как он дерётся',
          'Abilities decide how he fights',
        ).text,
        text: const Phrase(
          'Пятьдесят пять, и они складываются',
          'Fifty-five of them, and they stack',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),
    TrailerBeat(
      shot: const TrailerShot(anchor: Onboarding.anchorForkOrder, fill: 0.44),
      line: TrailerLine(
        const Phrase(
          'А приказ решает, когда вас нет',
          'Your standing order decides when you are gone',
        ).text,
        text: const Phrase(
          'На развилке он ждёт 45 секунд и выбирает сам',
          'At a fork he waits 45 seconds, then picks for himself',
        ).text,
      ),
      hold: const Duration(milliseconds: 2800),
    ),

    // --- Спуск ---
    TrailerBeat(
      act: (s) async {
        await s.back();
        s.deployBest();
      },
      shot: const TrailerShot(anchor: Onboarding.anchorDescent, fill: 0.54),
      line: TrailerLine(
        const Phrase('Дальше он сам по себе', 'From here he is on his own')
            .text,
      ),
      hold: const Duration(milliseconds: 2200),
    ),
    TrailerBeat(
      // Время игры гонится по-настоящему: глубина в кадре растёт потому, что
      // контракт действительно доходит до этажа, а не потому, что счётчику
      // велели крутиться.
      act: (s) => s.until(() => s.contract?.atFork ?? false, speed: 40),
      shot: const TrailerShot(anchor: Onboarding.anchorDescent, fill: 0.46),
      line: TrailerLine(
        const Phrase(
          'Этаж за этажом, пока не погибнет',
          'Floor after floor, until he dies',
        ).text,
      ),
      hold: const Duration(milliseconds: 1600),
      move: const Duration(milliseconds: 500),
    ),
    TrailerBeat(
      shot: const TrailerShot(anchor: Onboarding.anchorFork, fill: 0.5),
      line: TrailerLine(
        const Phrase('Путь раздваивается', 'The path splits').text,
        text: const Phrase(
          'Дорога короче или добыча богаче. Останетесь — откроется третья',
          'A shorter road, or a richer haul. Stay, and a third one opens.',
        ).text,
      ),
      hold: const Duration(seconds: 3),
    ),
    TrailerBeat(
      act: (s) async {
        s.chooseBold();
        await s.until(
            () => s.controller.collectableContract != null, speed: 40);
      },
      shot: const TrailerShot(anchor: Onboarding.anchorCollect, fill: 0.5),
      line: TrailerLine(
        const Phrase(
          'Рано или поздно этаж оказывается последним',
          'Sooner or later, a floor is his last',
        ).text,
      ),
      hold: const Duration(milliseconds: 2400),
    ),

    // --- Поворот: смерть не наказание ---
    TrailerBeat(
      act: (s) async {
        final c = s.controller.collectableContract;
        if (c == null) return;
        await s.open(JournalScreen(
          contract: c,
          controller: s.controller,
          onCollect: s.collect,
        ));
      },
      shot:
          const TrailerShot(anchor: Onboarding.anchorJournalCollect, fill: 0.44),
      line: TrailerLine(
        const Phrase('Гибель — не проигрыш', 'Death is not a loss').text,
        text: const Phrase(
          'Снаряжение, золото и Эхо возвращаются на Заставу',
          'Gear, gold and Echo all come back to the Outpost',
        ).text,
        top: true,
      ),
      hold: const Duration(seconds: 3),
    ),
    TrailerBeat(
      act: (s) async {
        s.collect();
        await s.back();
        if (!s.profile.hasPendingLoot) return;
        await s.open(LootSortScreen(controller: s.controller));
      },
      shot: const TrailerShot(anchor: Onboarding.anchorLootRow, fill: 0.36),
      line: TrailerLine(
        const Phrase('Теряется только глубина', 'Only depth is lost').text,
      ),
      hold: const Duration(milliseconds: 2800),
    ),

    // --- Чем растёт следующий ---
    //
    // Внутри этих экранов меток нет: наводиться не на что, и общим планом они
    // четыре кадра подряд стояли бы неподвижно. Поэтому у них свой масштаб —
    // камера входит в экран и медленно подъезжает.
    TrailerBeat(
      act: (s) async {
        await s.back();
        await s.open(EchoTreeScreen(controller: s.controller));
      },
      shot: const TrailerShot(zoom: 1.22, push: 0.12),
      line: TrailerLine(
        const Phrase(
          'Эхо растит не наёмника, а Заставу',
          'Echo grows the Outpost, not the man',
        ).text,
        text: const Phrase(
          'Следующий уйдёт глубже',
          'The next one goes deeper',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),
    TrailerBeat(
      act: (s) async {
        await s.back();
        await s.open(PassiveTreeScreen(controller: s.controller));
      },
      shot: const TrailerShot(zoom: 1.3, push: 0.14),
      line: TrailerLine(
        const Phrase(
          'Триста узлов пассивного древа',
          'Three hundred passive nodes',
        ).text,
      ),
      hold: const Duration(milliseconds: 2400),
    ),
    TrailerBeat(
      act: (s) async {
        await s.back();
        await s.open(ForgeScreen(controller: s.controller));
      },
      shot: const TrailerShot(zoom: 1.24, push: 0.12),
      line: TrailerLine(
        const Phrase(
          'Осколок вынимается из вещи и вбивается в другую',
          'Shards pull out of one item and into another',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),
    TrailerBeat(
      act: (s) async {
        await s.back();
        await s.open(StashScreen(controller: s.controller));
      },
      shot: const TrailerShot(zoom: 1.2, push: 0.12),
      line: TrailerLine(
        const Phrase(
          'Сундук тесен, и это решение',
          'The stash is small on purpose',
        ).text,
        text: const Phrase(
          'Держать всё нельзя — придётся выбрать',
          'You cannot keep everything',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),
    TrailerBeat(
      act: (s) async {
        await s.back();
        await s.open(QuestsScreen(controller: s.controller));
      },
      shot: const TrailerShot(zoom: 1.22, push: 0.12),
      line: TrailerLine(
        const Phrase('Сорок четыре задания', 'Forty-four quests').text,
      ),
      hold: const Duration(milliseconds: 2200),
    ),
    TrailerBeat(
      act: (s) => s.back(),
      shot: const TrailerShot(anchor: Onboarding.anchorBuildings, fill: 0.48),
      line: TrailerLine(
        const Phrase(
          'Восемь построек на Заставе',
          'Eight buildings at the Outpost',
        ).text,
        text: const Phrase(
          'Каждая меняет то, что приходит снизу',
          'Each one changes what comes back up',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),
    TrailerBeat(
      shot: const TrailerShot(anchor: Onboarding.anchorRift, fill: 0.4),
      line: TrailerLine(
        const Phrase(
          'Разлом дня — один на всех',
          'One rift a day, the same for everyone',
        ).text,
        text: const Phrase(
          'Общий сид, свои модификаторы',
          'Shared seed, its own modifiers',
        ).text,
      ),
      hold: const Duration(milliseconds: 2600),
    ),

    // --- Финал ---
    TrailerBeat(
      shot: const TrailerShot(zoom: 1.04, push: 0.12),
      line: TrailerLine(
        // Название берётся у игры, а не пишется здесь заново: разойтись с
        // переводом ровно в финальном кадре было бы обиднее всего.
        S.gameTitle,
        text: const Phrase(
          'Idle-RPG про наёмников, которые спускаются вместо вас',
          'An idle RPG about mercenaries who go down in your place',
        ).text,
      ),
      hold: const Duration(seconds: 4),
      move: const Duration(milliseconds: 1400),
    ),
  ];
}
