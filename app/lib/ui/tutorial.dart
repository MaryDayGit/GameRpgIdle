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
            'The mercenary waits for a decision'),
        text: Phrase(
            'Он остановился на развилке. Выберите путь — или он выберет '
                'сам, и вы узнаете об этом из журнала.',
            'They stopped at a fork. Choose the path — or they will choose '
                'it themselves, and you will read about it in the journal.'),
      );
    }

    // Дальше то, что закрывает предыдущий спуск: добыча, забытая на Заставе,
    // важнее нового найма.
    if (waiting) {
      return const TutorialStep(
        id: 'collect',
        title: Phrase('Заберите добычу', 'Collect the haul'),
        text: Phrase(
            'Пока не заберёте — у вас ничего нет: ни золота, ни вещей. '
                'Откройте журнал, там написано, чем всё кончилось.',
            'Until you do, you have nothing: no gold, no items. Open the '
                'journal — it says how it all ended.'),
      );
    }

    if (descending) {
      return const TutorialStep(
        id: 'watch',
        title: Phrase('Наёмник внизу', 'The mercenary is below'),
        text: Phrase(
            'Игру можно закрыть — спуск идёт по часам, а не по экрану. '
                'Но каждые пять этажей расселина расходится надвое, и наёмник '
                'ждёт вашего решения. Не дождётся — выберет сам.',
            'You can close the game — the descent runs on the clock, not on '
                'the screen. But every five floors the rift splits in two, '
                'and the mercenary waits for your decision. If they do not '
                'get one, they choose alone.'),
      );
    }

    if (profile.roster.reserve.isEmpty) {
      return const TutorialStep(
        id: 'hire',
        title: Phrase('Наймите наёмника', 'Hire a mercenary'),
        text: Phrase(
            'Он спустится один раз и погибнет — так и задумано. Всё, что '
                'он найдёт, останется вам.',
            'They go down once and die — that is the design. Everything they '
                'find stays with you.'),
      );
    }

    final merc = profile.roster.reserve.first;
    if (merc.gear.filledSlots < 2 && profile.stash.isNotEmpty) {
      return const TutorialStep(
        id: 'gear',
        title: Phrase('Соберите наёмника', 'Build the mercenary'),
        text: Phrase(
            'Нажмите «Сборка». Девять слотов под вещи и четыре под умения — '
                'это всё, чем вы управляете. Внизу вмешаться уже нельзя.',
            'Tap “Build”. Nine slots for items and four for abilities — that '
                'is everything you control. Down below you cannot step in.'),
      );
    }

    if (profile.maxDepthEver == 0) {
      return const TutorialStep(
        id: 'deploy',
        title: Phrase('Отправьте его вниз', 'Send them down'),
        text: Phrase(
            'Снаряжение и умения решаются здесь, до отправки. Внизу он '
                'справляется сам — кроме развилок: там он остановится и '
                'спросит вас.',
            'Gear and abilities are settled here, before departure. Below they '
                'manage alone — except at forks, where they stop and ask '
                'you.'),
      );
    }

    // Задания — главный источник новых умений, и узнать о них игрок должен
    // сразу после первой добычи: до неё их всё равно нечем закрывать.
    if (profile.quests.doneCount > 0 &&
        profile.availableAbilities.length <=
            profile.abilitySlots + _spareAbilities) {
      return const TutorialStep(
        id: 'quests',
        title: Phrase('Загляните в задания', 'Look at the quests'),
        text: Phrase(
            'Новые умения дают за дела: дойти глубже, одолеть чудовище, '
                'собрать сборку вокруг одной стихии. Кнопка наверху.',
            'New abilities are earned by deeds: reach deeper, bring down a '
                'monster, build around a single element. The button is up '
                'top.'),
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
            'Echo comes only with a mercenary’s death and accumulates between '
                'descents. In the tree it turns into what stays forever.'),
      );
    }

    if (profile.shards.isNotEmpty &&
        profile.outpost.levelOf(Building.forge) == 0) {
      return const TutorialStep(
        id: 'forge',
        title: Phrase('В Кузнице лежат осколки', 'Shards wait in the Forge'),
        text: Phrase(
            'Осколок помнит, насколько удачно выпало свойство. Вставьте '
                'его в вещь получше — и он даст больше.',
            'A shard remembers how well a property rolled. Set it into a '
                'better item and it gives more.'),
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
      "The mercenary takes what you gave them and goes down. You do not "
          "control them in a fight. But every five floors the rift splits in "
          "two, and there they stop and wait for you to choose the path.",
    ),
    Phrase(
      "Он погибнет. Обязательно и довольно скоро — так устроена расселина. "
          "Но всё, что он успел найти, поднимется наверх вместе с вестью о "
          "его смерти.",
      "They will die. Certainly, and fairly soon — that is how the rift "
          "works. But everything they found comes back up along with the "
          "news of their death.",
    ),
    Phrase(
      "Ваша работа здесь, на Заставе: собирать снаряжение, выбирать умения "
          "и решать, кого отправить следующим. Каждый следующий уйдёт глубже "
          "предыдущего.",
      "Your work is here, at the Outpost: assemble gear, choose abilities "
          "and decide who goes next. Each one goes deeper than the last.",
    ),
  ];

  /// Абзацы первого запуска на текущем языке.
  static List<String> get intro => [for (final line in _intro) line.text];
}
