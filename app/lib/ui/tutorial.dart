import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';

/// Шаг обучения — одна подсказка о следующем действии.
class TutorialStep {
  const TutorialStep({
    required this.id,
    required Phrase title,
    required Phrase text,
  })  : _title = title,
        _text = text;

  final String id;

  final Phrase _title;
  final Phrase _text;

  /// Что сделать. Одно действие, повелительным наклонением.
  String get title => _title.text;

  /// Зачем это нужно. Без «зачем» подсказка превращается в команду, а игрок —
  /// в исполнителя чужого сценария.
  String get text => _text.text;
}

/// Обучение.
///
/// Не сценарий с шагами «нажмите сюда», а функция от состояния игры: по
/// профилю видно, на чём игрок стоит, и подсказка — это ответ на вопрос
/// «что дальше». Отсюда два свойства, которых у сценария не бывает:
///
///  * его нельзя рассинхронизировать. Игрок, ушедший в Кузницу посреди
///    обучения, вернётся и увидит ту же подсказку — она вычисляется заново,
///    а не хранится указателем на шаг;
///  * его не нужно проходить. Сделал действие сам — подсказка исчезла.
///
/// ## О языке
///
/// Живой прогон дал замечание: «часто попадаются странные слова и
/// формулировки, хочу понятное обучение без заумных слов». Оно было
/// справедливым — первые подсказки говорили «ран», «билд», «перцентиль
/// ролла», «детерминизм». Это слова разработчика, а не игрока.
///
/// Правило теперь такое: **в подсказке нет ни одного слова, которого игрок
/// не встретил бы на экране.** «Ран» стал спуском, «билд» — сборкой,
/// «перцентиль» — качеством. Термины игры («Эхо», «Клеймо», «Осколок») —
/// остаются: это имена вещей, а не жаргон, и каждое объясняется там, где
/// впервые встречается.
class Tutorial {
  Tutorial._();

  /// Что подсказать прямо сейчас. `null` — игрок и так знает, что делает.
  static TutorialStep? stepFor(PlayerProfile profile) {
    final descending = profile.contracts.any((c) => c.descending);
    final waiting = profile.contracts.any((c) => c.awaitingCollection);
    final atFork = profile.contracts.any((c) => c.atFork);

    // Порядок проверок — это и есть цикл игры. Развилка идёт первой: наёмник
    // СТОИТ, и каждая секунда раздумий тратит его терпение. Добыча подождёт,
    // она уже никуда не денется, а развилка — денется.
    if (atFork) {
      return const TutorialStep(
        id: 'fork',
        title: Phrase('Наёмник ждёт решения',
            'Your mercenary is waiting'),
        text: Phrase(
            'Он остановился на развилке. Выберите путь — или он выберет '
                'сам, и вы прочитаете об этом в журнале.',
            'They have stopped at a fork. Pick the path — or they will pick '
                'it for you, and you will read about it in the journal.'),
      );
    }

    // Дальше то, что закрывает предыдущий спуск: добыча, забытая на Заставе,
    // важнее нового найма.
    if (waiting) {
      return const TutorialStep(
        id: 'collect',
        title: Phrase('Заберите добычу', 'Collect the haul'),
        text: Phrase(
            'Пока не заберёте — ничего из этого не ваше: ни золота, ни вещей. '
                'Откройте журнал, там написано, чем всё кончилось.',
            'Until you do, none of it is yours: no gold, no items. Open the '
                'journal — it tells you how it ended.'),
      );
    }

    if (descending) {
      return const TutorialStep(
        id: 'watch',
        title: Phrase('Наёмник внизу', 'Someone is down there'),
        text: Phrase(
            'Игру можно закрыть — спуск идёт по часам, а не по экрану. '
                'Но каждые пять этажей расселина расходится надвое, и наёмник '
                'встаёт и ждёт вас. Не дождётся — пойдёт сам.',
            'Close the game if you like — the descent runs on the clock, not '
                'on the screen. But every five floors the rift splits in two, '
                'and they stop to ask you. Left waiting too long, they go on '
                'without an answer.'),
      );
    }

    if (profile.roster.reserve.isEmpty) {
      return const TutorialStep(
        id: 'hire',
        title: Phrase('Наймите наёмника', 'Hire a mercenary'),
        text: Phrase(
            'Он спустится один раз и погибнет. Это не поломка: всё, что он '
                'найдёт, останется вам.',
            'They go down once, and they die. That is not a flaw — whatever '
                'they find stays with you.'),
      );
    }

    final merc = profile.roster.reserve.first;
    if (merc.gear.filledSlots < 2 && profile.stash.isNotEmpty) {
      return const TutorialStep(
        id: 'gear',
        title: Phrase('Соберите наёмника', 'Build them out'),
        text: Phrase(
            'Нажмите «Сборка». Девять слотов под вещи и четыре под умения — '
                'больше вы не решаете ничего. Внизу вмешаться уже нельзя.',
            'Tap “Build”. Nine slots for items, four for abilities — that is '
                'the whole of what you decide. Once they are down there, you '
                'cannot step in.'),
      );
    }

    if (profile.maxDepthEver == 0) {
      return const TutorialStep(
        id: 'deploy',
        title: Phrase('Отправьте его вниз', 'Send them down'),
        text: Phrase(
            'Снаряжение и умения решаются здесь, до отправки. Внизу он '
                'справляется сам — кроме развилок: там он встанет и спросит '
                'вас.',
            'Gear and abilities are settled up here, before they leave. Below '
                'they manage on their own — except at forks, where they stop '
                'and ask.'),
      );
    }

    // Задания — главный источник новых умений, и узнать о них игрок должен
    // сразу после первой добычи: до неё их всё равно нечем закрывать.
    if (profile.quests.doneCount > 0 &&
        profile.availableAbilities.length <=
            profile.abilitySlots + _spareAbilities) {
      return const TutorialStep(
        id: 'quests',
        title: Phrase('Загляните в задания', 'Look in on the quests'),
        text: Phrase(
            'Новые умения не покупаются — их дают за дела: дойти глубже, '
                'одолеть чудовище, собрать всё вокруг одной стихии.',
            'New abilities are not for sale — they are earned: get deeper, '
                'bring down a monster, build the whole thing around one '
                'element.'),
      );
    }

    // Второй спуск: игрок уже видел цикл, и теперь стоит показать, куда
    // девается Эхо — иначе оно копится молча.
    if (profile.echo > 0 && profile.tree.nodesBought == 0) {
      return const TutorialStep(
        id: 'tree',
        title: Phrase('Потратьте Эхо', 'Spend the Echo'),
        text: Phrase(
            'Эхо приходит только со смертью наёмника и копится между '
                'спусками. В древе оно превращается в то, что останется '
                'навсегда.',
            'Echo only ever comes from a mercenary’s death, and it piles up '
                'between descents. Spent in the tree, it turns into something '
                'that stays for good.'),
      );
    }

    if (profile.shards.isNotEmpty &&
        profile.outpost.levelOf(Building.forge) == 0) {
      return const TutorialStep(
        id: 'forge',
        title: Phrase('В Кузнице лежат осколки', 'Shards are piling up'),
        text: Phrase(
            'Осколок помнит не число, а удачу броска. Вставьте его в вещь '
                'получше — и та же удача даст больше.',
            'A shard remembers the luck of the roll, not the number. Set it '
                'into a better item and the same luck pays out more.'),
      );
    }

    return null;
  }

  /// Сколько умений сверх слотов считается «уже есть из чего выбирать».
  ///
  /// Пока открытых умений едва хватает на слоты, выбора нет и звать в задания
  /// надо. Как только запас появился — игрок разберётся сам.
  static const _spareAbilities = 8;

  /// Текст первого запуска: про то, как устроена игра, а не про кнопки.
  ///
  /// Четыре коротких абзаца, и ни одного термина. Всё, что игроку нужно
  /// понять на входе: он не герой, герой смертен, смерть — это не поражение,
  /// и решения принимаются наверху.
  static const _intro = [
    Phrase(
      "Вы не спускаетесь в расселину сами. Вы нанимаете тех, кто спускается.",
      "You do not go down into the rift yourself. You hire those who do.",
    ),
    Phrase(
      "Наёмник берёт то, что вы ему дали, и уходит вниз. В бою вы им не "
          "управляете. Но каждые пять этажей расселина расходится надвое — "
          "там он останавливается и ждёт, какой путь выберете вы.",
      "The mercenary takes whatever you gave them and goes down. You do not "
          "command them in a fight. But every five floors the rift splits, "
          "and there they stop and wait for you to choose.",
    ),
    Phrase(
      "Он погибнет. Обязательно и довольно скоро — так устроена расселина. "
          "Но всё, что он успел найти, поднимется наверх вместе с вестью о "
          "его смерти.",
      "They will die. Certainly, and fairly soon — the rift is built that "
          "way. Everything they found comes back up with the news of it.",
    ),
    Phrase(
      "Ваша работа здесь, на Заставе: собирать снаряжение, выбирать умения "
          "и решать, кого отправить следующим. Каждый следующий уйдёт глубже "
          "предыдущего.",
      "Your work is up here at the Outpost: put gear together, pick "
          "abilities, decide who goes next. Each one gets further than the "
          "last.",
    ),
  ];

  /// Абзацы первого запуска на текущем языке.
  static List<String> get intro => [for (final line in _intro) line.text];
}
