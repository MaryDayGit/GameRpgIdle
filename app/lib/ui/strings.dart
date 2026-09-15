import 'package:rift/core/model/lang.dart';

import 'format.dart';

export 'package:rift/core/model/lang.dart' show Lang, Phrase;

/// Строки интерфейса.
///
/// ## Почему не `.arb` и не `gen_l10n`
///
/// Штатный механизм Flutter выдаёт строки через `AppLocalizations.of(context)`
/// — то есть требует `BuildContext`. В этой игре половина текста собирается
/// вне виджетов: `help_content.dart` — справочник, `tutorial.dart` — подсказки
/// по состоянию игры, `run_ending_text.dart` — исход спуска. Контекста там нет
/// и заводить его незачем; протаскивать его через эти файлы значило бы
/// переписать их ради механизма, а не ради задачи.
///
/// Ядро уже говорит на двух языках через [Phrase] и статик [Lang.current]
/// (`lib/core/model/lang.dart`). Два разных механизма локализации в одной
/// игре — это два места, где язык может разъехаться, и один из них рано или
/// поздно забудут переключить. Поэтому здесь тот же [Phrase].
///
/// Цена решения названа честно: строки лежат в коде, а не в файле, который
/// можно отдать переводчику отдельно от репозитория. Для игры, которую пишет
/// один человек, это дешевле; для игры с внешним переводчиком — нет, и тогда
/// этот файл станет генератором, а не источником.
///
/// ## Правила
///
/// * имя getter'а называет МЕСТО и СМЫСЛ, а не текст: `deployDeadHint`, а не
///   `hePerishedText`. Текст меняется, место — нет;
/// * строка с числом остаётся функцией, а не склейкой на стороне вызова:
///   порядок слов у языков разный, и `'$n этажей'` в английском встанет не
///   туда;
/// * `Phrase.same` — для того, что одинаково на всех языках, чтобы это было
///   видно как решение, а не как забытый перевод.
class S {
  S._();

  // --- Настройки -------------------------------------------------------------

  static String get settingsTitle => const Phrase(
        'Язык, звук и отдача',
        'Language, sound and haptics',
      ).text;

  static String get settingsLanguage =>
      const Phrase('Язык', 'Language').text;

  static String get settingsLanguageAbout =>
      const Phrase('Меню, названия, всё на экране',
              'Menus, names, everything on screen')
          .text;

  static String get settingsSound => const Phrase('Звук', 'Sound').text;

  static String get settingsSoundAbout => const Phrase(
        'Удары, гибель, находки',
        'Blows, deaths, finds',
      ).text;

  static String get settingsHaptics =>
      const Phrase('Отдача', 'Haptics').text;

  static String get settingsHapticsAbout => const Phrase(
        'Короткий толчок на важном',
        'A short buzz when something lands',
      ).text;

  static String get settingsAnalytics =>
      const Phrase('Статистика игры', 'Gameplay stats').text;

  // Подпись говорит, ЧТО уходит, а не «помогите нам стать лучше». Игрок
  // выключает то, чего не понимает, а «на какой глубине погиб» понятно.
  static String get settingsAnalyticsAbout => const Phrase(
        'Обезличенно: глубина, сборка, что убило. Ничего о вас',
        'Anonymous: depth, build, what killed you. Nothing about you',
      ).text;

  // --- Аккаунт ---------------------------------------------------------------

  static String get accountTitle =>
      const Phrase('Сохранение в облаке', 'Cloud save').text;

  // Подпись говорит, что игрок ПОТЕРЯЕТ без привязки, а не «войдите в
  // аккаунт». Вход — это цена; сорок этажей, пережившие переустановку, —
  // это то, за что её платят.
  static String get accountAnonymousAbout => const Phrase(
        'Прогресс живёт только на этом телефоне. Переустановка сотрёт его',
        'Progress lives on this phone only. Reinstalling wipes it',
      ).text;

  static String get accountOfflineAbout => const Phrase(
        'Нет связи с сервером. Игра идёт, сохранение — на телефоне',
        'No server connection. The game runs, the save stays on the phone',
      ).text;

  static String get accountLinkedAbout => const Phrase(
        'Прогресс переживёт переустановку и переезд на другой телефон',
        'Progress survives a reinstall and a move to another phone',
      ).text;

  static String get accountLink =>
      const Phrase('Привязать Google', 'Link Google').text;

  static String get accountSignOut => const Phrase('Выйти', 'Sign out').text;

  static String get accountLinkFailed => const Phrase(
        'Не удалось привязать. Попробуйте позже',
        'Could not link. Try again later',
      ).text;

  static String get accountLinkedNow => const Phrase(
        'Готово: прогресс уехал в облако',
        'Done: progress is in the cloud',
      ).text;

  static String get accountAlreadyInUse => const Phrase(
        'Под этим Google уже есть сохранение',
        'This Google account already has a save',
      ).text;

  // --- Расхождение сохранений ------------------------------------------------

  static String get syncConflictTitle =>
      const Phrase('Два сохранения', 'Two saves').text;

  // Вопрос задан про ВЫБОР, а не про ошибку: расхождение — это нормальное
  // следствие игры на двух устройствах, и пугать им незачем. Пугает другое —
  // то, что одно из двух не переживёт ответа, и об этом сказано прямо.
  static String get syncConflictAbout => const Phrase(
        'Здесь и в облаке лежат разные сохранения. Выберите, какое оставить '
            '— второе будет перезаписано',
        'This phone and the cloud hold different saves. Pick the one to keep '
            '— the other will be overwritten',
      ).text;

  static String get syncThisPhone =>
      const Phrase('На этом телефоне', 'On this phone').text;

  static String get syncCloud => const Phrase('В облаке', 'In the cloud').text;

  /// Сводка сохранения: рекорд, спуски, Застава. Одной строкой, потому что
  /// выбирают именно по ней — дата у idle-игры почти всегда одна и та же.
  static String syncSummary(int depth, int runs, int outpost) => Phrase(
        'Рекорд $depth · спусков $runs · Застава $outpost',
        'Record $depth · runs $runs · Outpost $outpost',
      ).text;

  static String syncSeen(String when) =>
      Phrase('Были здесь $when', 'Last seen $when').text;

  // --- Обучение --------------------------------------------------------------

  static String get settingsTutorial =>
      const Phrase('Обучение', 'Tutorial').text;

  static String get settingsTutorialAbout => const Phrase(
        'Провести по игре заново, как в первый раз',
        'Walk through the game again, the way it went on day one',
      ).text;

  static String get settingsTutorialRunning =>
      const Phrase('Идёт прямо сейчас', 'Under way right now').text;

  static String get settingsTutorialRestart =>
      const Phrase('Пройти заново', 'Do it again').text;

  /// «Шаг 3 из 21». Игрок должен видеть, что обучение кончится, и когда.
  static String tutorialProgress(int step, int total) => Lang.current == Lang.ru
      ? 'ШАГ $step ИЗ $total'
      : 'STEP $step OF $total';

  static String get tutorialNext => const Phrase('Дальше', 'Next').text;

  static String get tutorialSkip =>
      const Phrase('Дальше сам', 'I have got this').text;

  // --- Развилка --------------------------------------------------------------

  /// Где наёмник стоит, сколько ещё ждёт и что сделает без игрока.
  ///
  /// Собирается целиком, а не склейкой на стороне вызова: в русском род
  /// правит глагол («Остановилась», «решит сама»), в английском — только
  /// местоимение. Порядок слов у языков тоже разный, и склейка из кусков
  /// поставила бы английское «alone» не туда.
  static String forkStanding({
    required bool she,
    required int floor,
    required String waiting,
    required String order,
  }) =>
      Lang.current == Lang.ru
          ? '${she ? "Остановилась" : "Остановился"} перед этажом $floor. '
              '$waiting, потом решит сам${she ? "а" : ""}: $order.'
          : '${she ? "She" : "He"} has stopped short of floor $floor. '
              '$waiting, then picks without you: $order.';

  static String forkWaitsMore(String left) =>
      Lang.current == Lang.ru ? 'Ждёт ещё $left' : 'Waiting $left more';

  static String get forkWaitsNoMore =>
      const Phrase('Ждать перестал', 'Done waiting').text;

  /// Здоровье после прошлого этажа. Четыре порога, а не число: игрок решает
  /// «рискнуть или нет», и «45 %» отвечает на этот вопрос хуже, чем «запас
  /// есть».
  static String forkHealth({required bool she, required String left}) =>
      Lang.current == Lang.ru
          ? 'С прошлого этажа сошл${she ? "а" : "ёл"} с $left здоровья'
          : 'Came off the last floor at $left health';

  static String get forkHealthUntouched => const Phrase(
        'Прошлый этаж прошёл без единой царапины.',
        'Walked the last floor without a scratch.',
      ).text;

  static String get forkHealthRoomLeft =>
      const Phrase(' — запас есть.', ' — plenty in reserve.').text;

  static String forkHealthNearlyOut({required bool she}) => Lang.current ==
          Lang.ru
      ? ' — ещё чуть-чуть, и всё.'
      : ' — one more hit and that would have been it.';

  static String get forkBoldOnlyWhilePresent => const Phrase(
        'Открыт, только пока вы в игре',
        'Yours only while you are watching',
      ).text;

  static String get forkCostHarmless => const Phrase(
        'Эта плата вам почти ничего не стоит',
        'This one barely costs you anything',
      ).text;

  // --- Общее -----------------------------------------------------------------

  /// «3 из 8» — самая частая пара чисел в игре: слоты, узлы, уровни.
  /// Отдельной функцией, потому что предлог между ними у каждого языка свой,
  /// а склейка на стороне вызова означала бы полсотни мест, где его забудут.
  static String outOf(Object done, Object total) =>
      Lang.current == Lang.ru ? '$done из $total' : '$done of $total';

  static String get keep => const Phrase('Оставить', 'Keep').text;
  static String get reset => const Phrase('Сбросить', 'Reset').text;
  static String get take => const Phrase('Взять', 'Take').text;
  static String get drop => const Phrase('Снять', 'Drop').text;

  // --- Древо Эха -------------------------------------------------------------

  static String get echoTreeTitle => const Phrase('Древо Эха', 'Echo Tree').text;

  static String echoAmount(int echo) =>
      Lang.current == Lang.ru ? 'Эхо $echo' : '$echo Echo';

  static String get echoTreeComplete =>
      const Phrase('Древо выкуплено', 'Every node bought').text;

  static String echoNextNode(int cost) => Lang.current == Lang.ru
      ? 'следующий узел — $cost'
      : 'next node costs $cost';

  static String echoTreeAbout(int bought, int total) => Lang.current == Lang.ru
      ? 'Куплено ${plural(bought, "узел", "узла", "узлов")} из $total. '
          'Каждый купленный узел дорожает следующий.'
      : '${pluralEn(bought, "node")} of $total bought. '
          'Each purchase raises the price of the next.';

  static String get resonanceTitle =>
      const Phrase('Отзвук глубины', 'Echo of the Deep').text;

  static String resonanceAbout(int level, String multiplier, String step) =>
      Lang.current == Lang.ru
          ? 'Уровень $level · сила наёмника ×$multiplier. Каждый уровень '
              'добавляет $step ко всей силе и стоит дороже предыдущего.'
          : 'Level $level · mercenary power ×$multiplier. Each level adds '
              '$step to all power and costs more than the last.';

  static String get resonanceLocked => const Phrase(
        'Бесконечный узел за выкупленным древом: каждый уровень добавляет '
            'силы всем наёмникам. Откроется, когда будут куплены все узлы.',
        'An endless node beyond the finished tree: every level adds power '
            'to every mercenary. Opens once all nodes are bought.',
      ).text;

  static String resonanceBuy(String cost) =>
      Lang.current == Lang.ru ? 'Купить за $cost' : 'Buy for $cost';

  static String get resonanceBuyAll =>
      const Phrase('На всё Эхо', 'Spend it all').text;

  // --- Дерево пассивок -------------------------------------------------------

  static String get passiveTreeTitle =>
      const Phrase('Дерево пассивок', 'Passive Tree').text;

  static String get passiveResetTitle =>
      const Phrase('Сбросить дерево?', 'Reset the tree?').text;

  static String get passiveResetAbout => const Phrase(
        'Очки вернутся все до одного, и разложить их можно будет иначе. '
            'Пропадёт только сама сборка.',
        'You get every point back and can spend them differently. The only '
            'thing lost is the shape you had.',
      ).text;

  static String passivePointsFree(int left) => Lang.current == Lang.ru
      ? '${plural(left, "очко", "очка", "очков")} свободно'
      : '${pluralEn(left, "point")} free';

  static String get passiveNoPoints =>
      const Phrase('Очков нет', 'No points').text;

  static String passiveSpent(int spent, int total, {int? nextAt}) {
    final base = Lang.current == Lang.ru
        ? 'вложено ${outOf(spent, total)}'
        : '${outOf(spent, total)} spent';
    if (nextAt == null) return base;
    return Lang.current == Lang.ru
        ? '$base · следующее с этажа $nextAt'
        : '$base · next one from floor $nextAt';
  }

  static String get passiveRuleMark => const Phrase('правило', 'rule').text;
  static String get passiveKeystone =>
      const Phrase('ключевой', 'keystone').text;
  static String get passiveNotable => const Phrase('крупный', 'notable').text;

  // --- Задания ---------------------------------------------------------------

  static String get questsTitle => const Phrase('Задания', 'Quests').text;

  static String questsDone(int done, int all) => Lang.current == Lang.ru
      ? 'Выполнено ${outOf(done, all)} · каждое открывает умение'
      : '${outOf(done, all)} done · each one unlocks an ability';

  static String get questsNow => const Phrase('Сейчас', 'Now').text;
  static String get questsFinished =>
      const Phrase('Выполнено', 'Finished').text;

  static String questsHiddenAhead(int hidden) => Lang.current == Lang.ru
      ? 'Ещё $hidden ждут дальше по цепочкам.'
      : 'Another $hidden wait further down the chains.';

  static String questReward(String name, {required bool opened, int echo = 0}) {
    final head = Lang.current == Lang.ru
        ? (opened ? 'Открыто: $name' : 'Награда: $name')
        : (opened ? 'Opened: $name' : 'Reward: $name');
    if (opened || echo <= 0) return head;
    return Lang.current == Lang.ru
        ? '$head · $echo Эха'
        : '$head · $echo Echo';
  }

  static String get questsEmpty => const Phrase(
        'Заданий пока нет. Отправьте наёмника вниз — первая цель приедет '
            'наверх вместе с первой добычей.',
        'No quests yet. Send someone down — the first goal comes up with '
            'the first haul.',
      ).text;

  // --- Карточка наёмника -----------------------------------------------------

  static String backpackOf(int slots) => Lang.current == Lang.ru
      ? 'рюкзак ${plural(slots, "предмет", "предмета", "предметов")}'
      : '$slots-slot backpack';

  static String get buildPower =>
      const Phrase('Сила сборки', 'Build power').text;
  static String get statDamage => const Phrase('Урон', 'Damage').text;
  static String get statArmor => const Phrase('Броня', 'Armor').text;
  static String get mercTrait => const Phrase('Черта', 'Trait').text;
  static String get mercAbilities => const Phrase('Умения', 'Abilities').text;
  static String get mercGear => const Phrase('Снаряжение', 'Gear').text;

  static String get mercSlotsEmpty =>
      const Phrase('Слоты пусты', 'Slots are empty').text;

  static String gearSlotsFilled(int filled, int usable) =>
      Lang.current == Lang.ru
          ? '${outOf(filled, usable)} слотов'
          : '${outOf(filled, usable)} slots';

  static String get statsInFull =>
      const Phrase('Все числа', 'The full sheet').text;

  static String get openBuild =>
      const Phrase('Сборка: снаряжение и умения', 'Build: gear and abilities')
          .text;

  static String get hire => const Phrase('Нанять', 'Hire').text;

  static String get sendIntoAbyss =>
      const Phrase('Отправить в бездну', 'Send into the abyss').text;

  // --- Сундук ----------------------------------------------------------------

  static String stashTitle(int total, int slots) => Lang.current == Lang.ru
      ? 'Сундук · ${outOf(total, slots)}'
      : 'Stash · ${outOf(total, slots)}';

  static String get stashFull => const Phrase(
        'Сундук полон — лишняя добыча уйдёт в золото. Переплавьте ненужное '
            'или улучшите Хранилище.',
        'The stash is full — extra loot turns to gold. Melt what you do not '
            'need or upgrade the Vault.',
      ).text;

  static String get stashEmpty => const Phrase(
        'Пусто. Вещи приносят снизу.',
        'Empty. Items come up from below.',
      ).text;

  static String stashEquipped(String kind, String merc) =>
      Lang.current == Lang.ru
          ? 'Надето: $kind · $merc'
          : 'Equipped: $kind · $merc';

  static String stashNotEquipped(String merc) => Lang.current == Lang.ru
      ? 'Не встало: $merc не может это надеть'
      : 'Would not go on: $merc cannot use this';

  static String stashSalvaged(String kind, String gold) =>
      Lang.current == Lang.ru
          ? 'Переплавлено: $kind · $gold'
          : 'Salvaged: $kind · $gold';

  static String get filterAll => const Phrase('Всё', 'All').text;

  /// Заголовок вещи: уровень, редкость, сколько свойств из скольких.
  static String itemLine({
    required int ilvl,
    required String rarity,
    required int used,
    required int max,
    required bool relic,
  }) {
    final head = Lang.current == Lang.ru
        ? '$ilvl ур. · $rarity · свойств ${outOf(used, max)}'
        : 'ilvl $ilvl · $rarity · ${outOf(used, max)} properties';
    if (!relic) return head;
    return Lang.current == Lang.ru ? '$head · реликт' : '$head · relic';
  }

  static String affixQuality(int percentile, int rerolls) {
    final head = Lang.current == Lang.ru
        ? 'качество $percentile'
        : 'quality $percentile';
    if (rerolls <= 0) return head;
    return Lang.current == Lang.ru
        ? '$head · ${plural(rerolls, "переброс", "переброса", "перебросов")}'
        : '$head · ${pluralEn(rerolls, "reroll")}';
  }

  static String get stashNobodyToEquip => const Phrase(
        'Надеть некому: наёмник внизу, снаряжение заперто.',
        'No one to equip: your mercenary is below, gear locked.',
      ).text;

  static String get equip => const Phrase('Надеть', 'Equip').text;

  static String equipOn(String merc) =>
      Lang.current == Lang.ru ? 'Надеть · $merc' : 'Equip · $merc';

  static String get toForge => const Phrase('В Кузницу', 'To the Forge').text;

  static String salvageFor(String gold) =>
      Lang.current == Lang.ru ? 'Переплавить · $gold' : 'Salvage · $gold';

  static String get salvageAbout => const Phrase(
        'Переплавка превращает вещь в золото. Сколько — решает Алтарь.',
        'Salvage turns the item into gold. The Altar decides how much.',
      ).text;

  // --- Разбор добычи ---------------------------------------------------------

  static String get lootSortTitle =>
      const Phrase('Разбор добычи', 'Sorting the haul').text;

  static String get howItWorks =>
      const Phrase('Как это работает', 'How this works').text;

  static String get done => const Phrase('Готово', 'Done').text;

  static String lootSortRest(int count) => Lang.current == Lang.ru
      ? 'Разобрать остальное за меня · '
          '${plural(count, "вещь", "вещи", "вещей")}'
      : 'Sort the rest for me · ${pluralEn(count, "item")}';

  static String lootBrought(int pending, int room, {required bool tight}) {
    final head = Lang.current == Lang.ru
        ? 'Наёмник донёс ${plural(pending, "вещь", "вещи", "вещей")}.'
        : 'Your mercenary hauled up ${pluralEn(pending, "item")}.';
    final tail = Lang.current == Lang.ru
        ? (tight ? 'Сундук полон.' : 'В сундуке свободно $room.')
        : (tight ? 'The stash is full.' : 'Room for $room more.');
    return '$head $tail';
  }

  static String get lootSortTight => const Phrase(
        'Освободите место в сундуке — или решите всё прямо здесь.',
        'Free up the stash, or settle these here and now.',
      ).text;

  static String get lootSortAbout => const Phrase(
        'Переплавка даёт золото и осколок, продажа — только золото, но больше.',
        'Salvage pays gold and a shard. Selling pays gold alone — but more '
            'of it.',
      ).text;

  static String get relicMark => const Phrase('реликт', 'relic').text;
  static String get triggerMark => const Phrase('триггер', 'trigger').text;

  static String salvageFull(String gold) =>
      Lang.current == Lang.ru ? 'Переплавить\n$gold' : 'Salvage\n$gold';

  static String sellFor(String gold) =>
      Lang.current == Lang.ru ? 'Продать\n$gold' : 'Sell\n$gold';

  // --- Журнал спуска ---------------------------------------------------------

  static String journalTitle(String merc) =>
      Lang.current == Lang.ru ? 'Спуск: $merc' : 'Descent: $merc';

  /// Вместимость показывается, только пока в неё укладываются: наёмник
  /// несёт наверх всё найденное, и «15 из 10» читалось ошибкой счёта.
  static String journalFinds(int count, int capacity) {
    final amount = count > capacity ? '$count' : outOf(count, capacity);
    return Lang.current == Lang.ru ? 'Находки · $amount' : 'Finds · $amount';
  }

  static String get journalNothingNew => const Phrase(
        'Ничего нового наверх не приехало.',
        'Nothing new came up this time.',
      ).text;

  static String journalOverflow(int count, String gold, int shards) {
    final head = Lang.current == Lang.ru
        ? '$count не влезло в рюкзак → $gold золота'
        : '$count would not fit in the backpack → $gold gold';
    if (shards == 0) return head;
    return Lang.current == Lang.ru
        ? '$head и ${plural(shards, "осколок", "осколка", "осколков")}'
        : '$head and ${pluralEn(shards, "shard")}';
  }

  static String get journalOnTheWay =>
      const Phrase('Что было по дороге', 'What happened along the way').text;

  static String journalCollect(String gold, int echo) =>
      Lang.current == Lang.ru
          ? 'Забрать всё · $gold золота, $echo Эха'
          : 'Take it all · $gold gold, $echo Echo';

  /// Итог спуска целиком: в русском род правит глагол, в английском —
  /// местоимение, и предложения строятся по-разному.
  static String journalOutcomeDeath(
          {required bool she, required int floor, String? killedBy}) =>
      Lang.current == Lang.ru
          ? (killedBy == null
              ? '${she ? "Погибла" : "Погиб"} на этаже $floor.'
              : '${she ? "Погибла" : "Погиб"} на этаже $floor: $killedBy.')
          : (killedBy == null
              ? '${she ? "She" : "He"} fell on floor $floor.'
              : '${she ? "She" : "He"} fell on floor $floor: $killedBy.');

  static String journalOutcomeStalled({required bool she, required int floor}) =>
      Lang.current == Lang.ru
          ? '${she ? "Упёрлась" : "Упёрся"} в стену на этаже $floor — '
              'волна не убивается.'
          : '${she ? "She" : "He"} hit a wall on floor $floor — the wave '
              'would not go down.';

  static String journalOutcomeTimeCap({required bool she}) =>
      Lang.current == Lang.ru
          ? (she ? 'Время вышло — отозвана.' : 'Время вышло — отозван.')
          : 'Time ran out; pulled back up.';

  static String journalOutcomeFloorCap({required bool she}) =>
      Lang.current == Lang.ru
          ? (she ? 'Дошла до самого дна.' : 'Дошёл до самого дна.')
          : 'Reached the bottom of the rift.';

  static String journalOutcomeAtFork(int floor) => Lang.current == Lang.ru
      ? 'Стоит на развилке у этажа $floor.'
      : 'Standing at a fork by floor $floor.';

  static String journalOutcomeRecalled(
          {required bool she, required int floor}) =>
      Lang.current == Lang.ru
          ? '${she ? "Отозвана" : "Отозван"} с этажа $floor, не закончив его. '
              '${she ? "Жива, добыча при ней." : "Жив, добыча при нём."}'
          : 'Called back from floor $floor, part-way through it. Alive, '
              'and the haul came up with ${she ? "her" : "him"}.';

  static String journalFloors(int from, int to, int gained) =>
      Lang.current == Lang.ru
          ? 'Этажи $from → $to  (+$gained)'
          : 'Floors $from → $to  (+$gained)';

  static String journalInAbyss(String time) => Lang.current == Lang.ru
      ? 'в бездне $time'
      : '$time in the abyss';

  static String get journalFork => const Phrase('Развилка', 'Fork').text;
  static String get journalRift => const Phrase('Разлом', 'Rift').text;

  static String journalButCost(String minus) =>
      Lang.current == Lang.ru ? 'но $minus' : 'but $minus';

  static String journalBossDown(String boss, {required bool she}) =>
      Lang.current == Lang.ru
          ? '$boss ${she ? "повержена" : "повержен"}'
          : '$boss brought down';

  static String journalNearlyDied({required bool she, required String left}) =>
      Lang.current == Lang.ru
          ? 'Чуть не ${she ? "погибла" : "погиб"} — оставалось $left здоровья'
          : 'Came within $left health of dying';

  static String get journalSlowing => const Phrase(
        'Этажи пошли вдвое медленнее — стена близко',
        'Floors started taking twice as long — the wall is close',
      ).text;

  static String journalEndedHere([String? killedBy]) {
    final head = const Phrase('Здесь всё и кончилось', 'This is where it ended')
        .text;
    return killedBy == null ? head : '$head: $killedBy';
  }

  static String critFor(String amount) =>
      Lang.current == Lang.ru ? 'Крит · $amount' : 'Crit · $amount';

  // --- Экран боя -------------------------------------------------------------

  static String battleKilled(String name, {required bool she}) =>
      Lang.current == Lang.ru
          ? '«$name» ${she ? "повержена" : "повержен"}'
          : '“$name” brought down';

  static String battleAbility(String name) =>
      Lang.current == Lang.ru ? 'Умение: $name' : 'Ability: $name';

  static String battleTook(String amount) => Lang.current == Lang.ru
      ? 'Получено $amount'
      : 'Took $amount';

  static String get battleMercFell =>
      const Phrase('Наёмник погиб', 'The mercenary fell').text;

  static String get recallTitle =>
      const Phrase('Отозвать наёмника?', 'Recall the mercenary?').text;

  static String get recallAbout => const Phrase(
        'Спуск кончится на том этаже, где он стоит. Всё найденное '
            'поднимется вместе с ним: за отзыв не берут ничего.',
        'The descent ends on the floor they are standing on. Everything they '
            'found comes up with them — calling someone back costs nothing.',
      ).text;

  static String get recallLetThemGo =>
      const Phrase('Пусть идёт дальше', 'Let them go on').text;

  static String get recall => const Phrase('Отозвать', 'Recall').text;

  static String get recallMercenary =>
      const Phrase('Отозвать наёмника', 'Recall the mercenary').text;

  static String get battleOver =>
      const Phrase('Спуск окончен', 'Descent over').text;

  static String battleFloor(int depth, {required bool boss}) {
    final head = Lang.current == Lang.ru ? 'Этаж $depth' : 'Floor $depth';
    if (!boss) return head;
    return Lang.current == Lang.ru ? '$head · БОСС' : '$head · BOSS';
  }

  static String get battleAtFork => const Phrase(
        'Развилка · наёмник ждёт решения',
        'A fork · waiting on your call',
      ).text;

  static String get battleWaitsAtOutpost => const Phrase(
        'Наёмник ждёт вас на Заставе',
        'Waiting for you back at the Outpost',
      ).text;

  static String get battleResting => const Phrase(
        'Переход · наёмник переводит дух',
        'Between floors · catching their breath',
      ).text;

  static String battleWave(int index) =>
      Lang.current == Lang.ru ? 'Волна $index' : 'Wave $index';

  static String get battleMercHp =>
      const Phrase('HP наёмника', 'Mercenary HP').text;

  static String get battleRest => const Phrase('Переход', 'Rest').text;
  static String get battleWaveShort => const Phrase('Волна', 'Wave').text;

  static String get battleWatching => const Phrase(
        'Вы наблюдаете: сборка заперта до конца спуска.',
        'Watching only: the build is locked until the descent ends.',
      ).text;

  static String battlePath(int floors) => Lang.current == Lang.ru
      ? 'Путь · ${plural(floors, "этаж", "этажа", "этажей")}'
      : 'Path · ${pluralEn(floors, "floor")}';

  static String battleNow(String what) =>
      Lang.current == Lang.ru ? 'сейчас · $what' : 'now · $what';

  static String battleForkAhead(String name, String minus) =>
      Lang.current == Lang.ru
          ? 'Развилка → $name: $minus'
          : 'Fork → $name: $minus';

  static String get battleClearPath =>
      const Phrase('Ровный путь', 'A clear path').text;

  // --- Лист характеристик ----------------------------------------------------

  static String get statsTitle =>
      const Phrase('Характеристики', 'Statistics').text;

  static String statsAbout(String merc, int depth, {required bool she}) =>
      Lang.current == Lang.ru
          ? '$merc · всё, с чем ${she ? "она" : "он"} уйдёт вниз. '
              'Проценты посчитаны для глубины $depth.'
          : '$merc · everything ${she ? "she" : "he"} takes down. '
              'Percentages are worked out for depth $depth.';

  static String get statsGroupSurvival =>
      const Phrase('Живучесть', 'Survival').text;
  static String get statsGroupResists =>
      const Phrase('Сопротивления', 'Resistances').text;
  static String get statsGroupDamage => const Phrase('Урон', 'Damage').text;
  static String get statsGroupAbilities =>
      const Phrase('Способности', 'Abilities').text;
  static String get statsGroupLoot => const Phrase('Добыча', 'Loot').text;
  static String get statsGroupTags =>
      const Phrase('Множители по тегам', 'Tag multipliers').text;

  static String get statMaxHp => const Phrase('Максимум HP', 'Maximum HP').text;
  static String get statHpRegen =>
      const Phrase('Восстановление HP', 'HP regeneration').text;

  static String perSecond(String value) =>
      Lang.current == Lang.ru ? '$value в секунду' : '$value per second';

  static String get statsRestNote => const Phrase(
        'Между этажами наёмник всё равно отдыхает',
        'They catch their breath between floors either way',
      ).text;

  static String get resistFire => const Phrase('Огню', 'Fire').text;
  static String get resistCold => const Phrase('Холоду', 'Cold').text;
  static String get resistLightning =>
      const Phrase('Молнии', 'Lightning').text;
  static String get resistVoid => const Phrase('Пустоте', 'Void').text;

  static String resistsAbout(int cap) => Lang.current == Lang.ru
      ? 'Физический урон режет броня, стихийный — сопротивления. '
          'Потолок сопротивления — $cap.'
      : 'Armor cuts physical damage, resistances cut elemental. '
          'The resistance cap is $cap.';

  static String get statWeaponDamage =>
      const Phrase('Урон оружия', 'Weapon damage').text;
  static String get statWeaponDamageAbout => const Phrase(
        'От него растут умения с тегом «Атака» и автоатака',
        'Attack-tagged abilities and the auto-attack grow off this',
      ).text;

  static String get statSpellPower =>
      const Phrase('Сила чар', 'Spell power').text;
  static String get statSpellPowerAbout => const Phrase(
        'От неё растут умения с тегом «Чары». Автоатака — нет',
        'Spell-tagged abilities grow off this. The auto-attack does not',
      ).text;

  static String get statIncreasedDamage =>
      const Phrase('Увеличение урона', 'Increased damage').text;
  static String get statAttackSpeed =>
      const Phrase('Скорость атаки', 'Attack speed').text;

  static String hitsPerSecond(String value) =>
      Lang.current == Lang.ru ? '$value уд/с' : '$value hits/s';

  static String attackSpeedBreakdown(String base, String extra,
          {required bool positive}) =>
      Lang.current == Lang.ru
          ? 'база $base, ${positive ? "сверху" : "минус"} $extra'
          : 'base $base, ${positive ? "plus" : "minus"} $extra';

  static String get statCritChance =>
      const Phrase('Шанс крита', 'Crit chance').text;
  static String get statCritMulti =>
      const Phrase('Множитель крита', 'Crit multiplier').text;

  static String get statMana => const Phrase('Запас маны', 'Mana pool').text;

  static String manaReserved(String share) => Lang.current == Lang.ru
      ? 'ауры держат занятыми $share'
      : 'auras keep $share reserved';

  static String get statManaRegen =>
      const Phrase('Восстановление маны', 'Mana regeneration').text;

  static String get statCooldown => const Phrase('Перезарядка', 'Cooldown').text;
  static String get statCooldownAbout => const Phrase(
        'У каждого умения свой отсчёт',
        'Every ability runs its own timer',
      ).text;

  static String get statLeech => const Phrase('Вампиризм', 'Life leech').text;
  static String get statLeechAbout => const Phrase(
        'часть нанесённого урона возвращается здоровьем',
        'part of the damage you deal comes back as health',
      ).text;

  static String get statLootQuality =>
      const Phrase('Качество добычи', 'Loot quality').text;
  static String get statLootQualityAbout => const Phrase(
        'Сдвигает выпадение к старшим редкостям',
        'Tilts what drops toward the better rarities',
      ).text;

  static String get statLootQuantity =>
      const Phrase('Количество добычи', 'Loot quantity').text;
  static String get statGoldFind =>
      const Phrase('Находимое золото', 'Gold found').text;

  static String get statsTagsAbout => const Phrase(
        'Работают только на умениях с этим тегом — и на автоатаке, если её '
            'тег совпал.',
        'These count only on abilities carrying that tag — and on the '
            'auto-attack, if its own tag matches.',
      ).text;

  static String get statsNoArmor => const Phrase(
        'Брони нет — физический урон приходит целиком',
        'No armor — physical damage lands in full',
      ).text;

  static String statsPhysicalCut(String share, {required bool capped}) {
    final head = Lang.current == Lang.ru
        ? 'Физический урон меньше на $share'
        : 'Physical damage reduced by $share';
    if (!capped) return head;
    return Lang.current == Lang.ru
        ? '$head — это потолок'
        : '$head — and that is the ceiling';
  }

  static String statsDamageCut(String share, {required bool capped}) {
    final head = Lang.current == Lang.ru
        ? 'Урон меньше на $share'
        : 'Damage reduced by $share';
    if (!capped) return head;
    return Lang.current == Lang.ru
        ? '$head — выше потолка не считается'
        : '$head — anything past the cap is wasted';
  }

  static String get statsNoCrits => const Phrase(
        'Критов нет — множителю не на чем сработать',
        'No crits — the multiplier has nothing to work on',
      ).text;

  static String statsAverageCrit(String value) => Lang.current == Lang.ru
      ? 'В среднем ×$value по всему урону'
      : '×$value on average across all damage';

  // --- Уведомления -----------------------------------------------------------
  //
  // Единственный текст игры, который читают, не открыв её. Он собирается в
  // момент отправки контракта и до шторки доезжает как есть, поэтому язык
  // здесь — тот, что стоял при отправке, а не при показе.

  static String get notificationChannel =>
      const Phrase('Спуски', 'Descents').text;

  static String get notificationChannelAbout => const Phrase(
        'Что случилось с наёмником, пока вас не было',
        'Word from the abyss while you were away',
      ).text;

  static String notifyForkTitle(String merc) => Lang.current == Lang.ru
      ? '$merc ждёт решения'
      : '$merc is waiting on you';

  static String notifyDeathTitle(String merc) => Lang.current == Lang.ru
      ? '$merc не вернётся'
      : '$merc is not coming back';

  static String notifyForkBody({required bool she, required int depth}) =>
      Lang.current == Lang.ru
          ? '${she ? "Остановилась" : "Остановился"} на развилке у этажа '
              '$depth. Выберите путь, пока ${she ? "она" : "он"} ждёт.'
          : 'Stopped at a fork below floor $depth. Pick the path while '
              '${she ? "she" : "he"} is still standing there.';

  static String get notifyRelayTitle =>
      const Phrase('Смена закончилась', 'The relief is over').text;

  static String notifyRelayBody({required int runs, required int depth}) =>
      Lang.current == Lang.ru
          ? 'Сменщиков ушло вниз: $runs, глубже всех — этаж $depth. '
              'Добыча ждёт на Заставе.'
          : '$runs relief ${runs == 1 ? "mercenary" : "mercenaries"} went '
              'down, the deepest reached floor $depth. The haul waits at the '
              'Outpost.';

  static String get helpTitle => const Phrase('Справка', 'Help').text;

  // --- Застава ---------------------------------------------------------------

  /// Название игры. `Phrase.same`, а не пара форм: имя не переводится —
  /// игрок ищет в магазине и в отзывах ровно одно слово. Расселина как
  /// МЕСТО при этом остаётся русской в русских текстах: «расселина
  /// разошлась надвое» — это художественный текст, а не заголовок.
  static String get gameTitle => const Phrase.same('Riftmark').text;
  static String get outpostTitle => const Phrase('Застава', 'Outpost').text;
  static String get gotIt => const Phrase('Понятно', 'Got it').text;
  static String get fine => const Phrase('Хорошо', 'Fine').text;
  static String get cancel => const Phrase('Отмена', 'Cancel').text;

  static String shardsLost(int lost) => Lang.current == Lang.ru
      ? 'Верстак полон — ${plural(lost, "осколок", "осколка", "осколков")} '
          'не доехало. Поднимите Верстак.'
      : 'The Bench is full — ${pluralEn(lost, "shard")} never made it. '
          'Upgrade the Shard Bench.';

  static String stashOverflowed(int count) => Lang.current == Lang.ru
      ? 'В сундуке не хватило места: '
          '${plural(count, "вещь", "вещи", "вещей")} переплавлено в золото. '
          'Поднимите Хранилище.'
      : 'The stash ran out of room — ${pluralEn(count, "item")} melted down '
          'into gold. Upgrade the Vault.';

  static String stashButton(int count) =>
      Lang.current == Lang.ru ? 'Сундук · $count' : 'Stash · $count';

  static String get forgeTitle => const Phrase('Кузница', 'Forge').text;
  static String get passivesTitle => const Phrase('Пассивки', 'Passives').text;

  static String get resourceGold => const Phrase('Золото', 'Gold').text;
  static String get resourceEcho => const Phrase('Эхо', 'Echo').text;
  static String get resourceRecord => const Phrase('Рекорд', 'Record').text;
  static String get resourceShards => const Phrase('Осколки', 'Shards').text;

  static String get abyssEmpty =>
      const Phrase('Бездна пуста', 'The abyss is empty').text;

  static String get abyssEmptyAbout => const Phrase(
        'Наёмник уходит вниз один и идёт, пока не погибнет. Пока он там, '
            'вы не получаете ничего: всё, что он найдёт, вернётся только с '
            'ним. Снаряжение и умения выставляются ДО отправки и заперты до '
            'конца контракта.',
        'A mercenary goes down alone and keeps going until they die. While '
            'they are down there you get nothing: whatever they find comes up '
            'only with them. Gear and abilities are set BEFORE they leave, '
            'and locked until the contract ends.',
      ).text;

  static String get ropeAbout => const Phrase(
        'Спуск начинается не с первого этажа: до трети вашего рекорда '
            'спущена верёвка. Пройденное однажды не надо проходить заново — '
            'там нечего искать и некому сопротивляться.',
        'A descent does not start on the first floor: a rope reaches down '
            'to a third of your record. Ground you have covered once is not '
            'worth covering twice — nothing left to find there, and nobody '
            'left to put up a fight.',
      ).text;

  static String sendDownFrom(int start) => Lang.current == Lang.ru
      ? 'Отправьте наёмника вниз. Верёвка спущена до этажа $start.'
      : 'Send someone down. The rope reaches floor $start.';

  static String get sendDown => const Phrase(
        'Отправьте наёмника вниз.',
        'Send someone down.',
      ).text;

  static String mercAtFork(String merc) => Lang.current == Lang.ru
      ? '$merc на развилке'
      : '$merc is at a fork';

  static String get forkCardAbout => const Phrase(
        'Каждый пятый этаж расселина расходится надвое. Выбранный путь '
            'держится до следующей развилки — это не один этаж, а отрезок '
            'спуска. Пока вас нет, наёмник выбирает сам по приказу, но ждёт '
            'не вечно — и третий путь без вас ему недоступен.',
        'Every fifth floor the rift splits in two. Whichever path you pick '
            'holds until the next fork — a stretch of the descent, not one '
            'floor. With you away, the mercenary goes by their standing '
            'order, and they do not wait forever. The third path is beyond '
            'them without you.',
      ).text;

  static String mercInAbyss(String merc) => Lang.current == Lang.ru
      ? '$merc в бездне'
      : '$merc is in the abyss';

  static String get descentCardAbout => const Phrase(
        'Снаряжение и умения заперты до конца контракта: наёмник уже внизу, '
            'и передать ему нечего. Отзыв кончает спуск на том этаже, где он '
            'стоит. Всё найденное поднимется с ним, и стоит это ничего.',
        'Gear and abilities are locked until the contract ends: they are '
            'already down there, and nothing can be handed to them now. '
            'Calling them back ends the descent on the floor they stand on. '
            'Everything they found comes up with them — it costs nothing.',
      ).text;

  static String floorNumber(int depth) =>
      Lang.current == Lang.ru ? 'Этаж $depth' : 'Floor $depth';

  static String inAbyssFor(String time) => Lang.current == Lang.ru
      ? 'в бездне $time'
      : '$time in the abyss';

  static String get firstDescent =>
      const Phrase('Первый спуск', 'First descent').text;

  static String get newRecord =>
      const Phrase('Новый рекорд глубины', 'New depth record').text;

  static String recordIs(int record) => Lang.current == Lang.ru
      ? 'Рекорд: этаж $record'
      : 'Record: floor $record';

  static String get watchBattle =>
      const Phrase('Смотреть бой', 'Watch the fight').text;

  static String get openJournal =>
      const Phrase('Открыть журнал', 'Open the journal').text;

  static String haulWaiting(int items, String gold, int echo) =>
      Lang.current == Lang.ru
          ? 'Добыча ждёт: '
              '${plural(items, "предмет", "предмета", "предметов")}, '
              '$gold золота, $echo Эха'
          : 'The haul is waiting: ${pluralEn(items, "item")}, $gold gold, '
              '$echo Echo';

  static String allSlotsBusy(int used, int total) => Lang.current == Lang.ru
      ? 'Все слоты спуска заняты: ${outOf(used, total)}'
      : 'Every descent slot is taken: ${outOf(used, total)}';

  static String mercenariesCount(int count) => Lang.current == Lang.ru
      ? 'Наёмники ($count)'
      : 'Mercenaries ($count)';

  static String get nobodyHired => const Phrase(
        'Никого нет — наймите в Таверне.',
        'Nobody here — hire someone at the Tavern.',
      ).text;

  static String get send => const Phrase('Отправить', 'Send').text;
  static String get slotsBusy =>
      const Phrase('Слоты заняты', 'Slots are busy').text;

  // --- Смена (GDD §9.4) ------------------------------------------------------

  static String get toRelay => const Phrase('В смену', 'To relief').text;

  static String get toRelayLong =>
      const Phrase('Поставить в смену', 'Put on relief').text;

  static String get fromRelay => const Phrase('Вернуть', 'Take back').text;

  static String relayTitle(int used, int total) => Lang.current == Lang.ru
      ? 'Смена у Костра · ${outOf(used, total)}'
      : 'Relief at the campfire · ${outOf(used, total)}';

  static String get relayAboutTitle => const Phrase('Смена', 'Relief').text;

  static String get relayAbout => const Phrase(
        'Сменщики ждут у Костра. Когда наёмник гибнет, следующий уходит вниз '
            'в ту же секунду — в его снаряжении, с его умениями и приказом '
            'на развилку. Ранг и черта у сменщика свои.\n\n'
            'Добыча павшего ждёт вас на Заставе, как и без смены. Если вас '
            'нет в игре, сменщик идёт по приказу и на развилках не стоит.\n\n'
            'Места в смене даёт Костёр.',
        'Relief mercenaries wait at the campfire. When a mercenary falls, '
            'the next one goes down that very second — in the same gear, '
            'with the same skills and fork orders. Rank and trait are their '
            'own.\n\n'
            'The fallen one’s haul waits for you at the Outpost, same as '
            'without a relief. If you are not in the game, the relief follows '
            'orders and does not stop at forks.\n\n'
            'The Campfire opens relief places.',
      ).text;

  static String relayEmpty(int free) => Lang.current == Lang.ru
      ? 'Свободно мест: $free. Поставьте наёмника из резерва — он уйдёт вниз, '
          'когда погибнет тот, кто внизу.'
      : '$free free ${free == 1 ? "place" : "places"}. Put a mercenary from '
          'the reserve here — they go down when the one below falls.';

  static String relayWaiting(int count) => Lang.current == Lang.ru
      ? 'Следом уйдут сменщики: $count'
      : 'Relief waiting to follow: $count';

  static String get awayTitle =>
      const Phrase('Пока вас не было', 'While you were away').text;

  static String awaySummary(int runs, int deepest) => Lang.current == Lang.ru
      ? 'Спусков закончено: $runs, глубже всех — этаж $deepest. '
          'Добыча каждого ждёт в своём журнале.'
      : '${pluralEn(runs, "descent")} ended, the deepest at floor $deepest. '
          'Each haul waits in its own journal.';

  static String get dailyRift => const Phrase('Разлом дня', 'The Daily Rift').text;

  static String riftRecord(int best) => Lang.current == Lang.ru
      ? 'Ваш рекорд в разломах: этаж $best'
      : 'Your best in a rift: floor $best';

  static String riftModifierLine(String name) => Lang.current == Lang.ru
      ? '$name — на каждом этаже, а не между развилками.'
      : '$name — on every floor, not between forks.';

  static String riftReward(String plus) => Lang.current == Lang.ru
      ? '$plus. Эхо за спуск удваивается'
      : '$plus. The descent pays double Echo';

  static String get sendIntoRift =>
      const Phrase('Отправить в разлом', 'Send into the rift').text;

  static String get riftDoneToday => const Phrase(
        'Сегодня разлом уже пройден',
        'You have already run today’s rift',
      ).text;

  static String get tavernTitle => const Phrase('Таверна', 'Tavern').text;

  static String get tavernAbout => const Phrase(
        'Ранг наёмника поднимает все его характеристики и размер рюкзака. '
            'Таверна сильнее никого не делает — она повышает шансы, что '
            'придёт кто-то хороший.',
        'Rank lifts every stat a mercenary has, and the size of their '
            'pack. The Tavern makes nobody stronger — it only improves the '
            'odds that someone good walks in.',
      ).text;

  static String get hireCostAbout => const Phrase(
        ' Задаток растёт с вашим рекордом: чем глубже расселина, тем дороже '
            'те, кто в неё пойдёт. Оборванцы стоят своё всегда.',
        ' The fee climbs with your record: the deeper the rift runs, the '
            'more they want for going into it. The Ragged always come at '
            'their own flat price.',
      ).text;

  static String get refresh => const Phrase('Обновить', 'Refresh').text;

  static String get takeForFree =>
      const Phrase('Взять даром', 'Take them for free').text;

  static String hireFor(String cost) =>
      Lang.current == Lang.ru ? 'Нанять за $cost' : 'Hire for $cost';

  static String notEnoughGold(String cost) => Lang.current == Lang.ru
      ? 'Не хватает золота: нужно $cost.'
      : 'Not enough gold — you need $cost.';

  static String volunteerFree(String merc) => Lang.current == Lang.ru
      ? 'Платить нечем — $merc пойдёт даром.'
      : 'Nothing left to pay with — $merc will go for nothing.';

  static String get forFree => const Phrase('даром', 'free').text;

  static String backpackShort(int slots) => Lang.current == Lang.ru
      ? 'рюкзак $slots'
      : 'backpack $slots';

  static String gearAndAbilities(
          int gear, int gearMax, int abilities, int abilityMax) =>
      Lang.current == Lang.ru
          ? 'Снаряжение $gear/$gearMax · умения $abilities/$abilityMax'
          : 'Gear $gear/$gearMax · abilities $abilities/$abilityMax';

  static String get buildButton => const Phrase('Сборка', 'Build').text;

  static String get buildingsTitle =>
      const Phrase('Постройки', 'Buildings').text;

  static String get buildingsAbout => const Phrase(
        'Застава покупается золотом. Она не делает наёмника сильнее — она '
            'облегчает жизнь вам: сколько вещей влезет, сколько даёт '
            'переплавка лишнего, кто приходит в Таверну.\n\n'
            'Уровень открывает достигнутая ГЛУБИНА, а не кошелёк. Иначе '
            'Застава выкупалась бы вперёд прогресса, и дальше игра шла бы '
            'сама.\n\nНажмите на постройку, чтобы увидеть, что даст '
            'следующий уровень.',
        'The Outpost is bought with gold. It makes no mercenary stronger — '
            'it makes your life easier: how much the stash holds, what '
            'salvage pays back, who walks into the Tavern.\n\n'
            'Levels are unlocked by DEPTH reached, not by your purse. '
            'Otherwise you would buy the whole Outpost out ahead of your own '
            'progress, and the game would run itself from there.\n\nTap a '
            'building to see what the next level gives.',
      ).text;

  static String buildingLevel(String name, int level, int max) =>
      Lang.current == Lang.ru
          ? '$name · ${outOf(level, max)}'
          : '$name · ${outOf(level, max)}';

  static String buildingNow(String effect) =>
      Lang.current == Lang.ru ? 'Сейчас: $effect' : 'Now: $effect';

  static String buildingNext(String effect) =>
      Lang.current == Lang.ru ? 'Станет: $effect' : 'Becomes: $effect';

  static String get buildingMaxedFull =>
      const Phrase('Дальше некуда.', 'Nowhere left to go.').text;
  static String get buildingMaxed => const Phrase('Предел', 'Maxed').text;

  static String buildingGate(int floor) => Lang.current == Lang.ru
      ? 'Следующий уровень откроется, когда наёмник дойдёт до этажа $floor.'
      : 'The next level opens when a mercenary reaches floor $floor.';

  static String upgradeFor(String cost) =>
      Lang.current == Lang.ru ? 'Улучшить · $cost' : 'Upgrade · $cost';

  static String opensFromFloor(int gate) => Lang.current == Lang.ru
      ? 'откроется с этажа $gate'
      : 'opens from floor $gate';

  // --- Логова стражей --------------------------------------------------------

  static String get lairsTitle =>
      const Phrase('Логова стражей', 'Guardian lairs').text;

  static String get lairsAbout => const Phrase(
        'В логове страж ждёт один на один, на глубине своего круга. Спуска '
            'перед ним нет — только бой, и решается в нём одно: чем идти. У '
            'каждого стража свои повадки и своя слабость.\n\nВызов стоит '
            'подношения, и оно не возвращается. Проигравший наёмник гибнет, '
            'победивший возвращается в резерв.\n\nУ каждого стража свои '
            'умения: он готовит их с замахом, и замах видно на арене. Первая '
            'победа над стражем даёт два очка дерева пассивок; каждая первая '
            'победа на круге открывает следующий и отдаёт уникальную вещь того '
            'босса, которого страж воплощает. К взятому кругу можно вернуться '
            '— за вещью.',
        'In a lair the guardian waits one on one, at the depth of its '
            'circle. No descent before it — only the fight, and it decides '
            'one thing: what to bring. Each guardian has its own habits and '
            'its own weakness.\n\nA challenge costs an offering, and it is '
            'not returned. A mercenary who loses dies; one who wins returns '
            'to the reserve.\n\nEach guardian has its own skills: it winds '
            'them up, and the wind-up shows in the arena. The first win over '
            'a guardian grants two passive points; each first win of a '
            'circle opens the next and drops the unique item of the boss the '
            'guardian embodies. You can return to a taken circle — for the '
            'item.',
      ).text;

  static String lairCircle(int circle, int depth) => Lang.current == Lang.ru
      ? 'Круг $circle · этаж $depth'
      : 'Circle $circle · floor $depth';

  static String lairOffering(String gold) => Lang.current == Lang.ru
      ? 'Подношение: $gold'
      : 'Offering: $gold';

  static String lairTaken(int circles) => Lang.current == Lang.ru
      ? 'Взято кругов: $circles'
      : 'Circles taken: $circles';

  static String lairTrophies(int circles, int points, int maxPoints) =>
      Lang.current == Lang.ru
          ? 'Взято кругов: $circles · очков пассивок от логов: '
              '$points из $maxPoints'
          : 'Circles taken: $circles · passive points from lairs: '
              '$points of $maxPoints';

  static String lairSkills(String names) => Lang.current == Lang.ru
      ? 'Умения: $names'
      : 'Skills: $names';

  static String lairFightTitle(int circle) => Lang.current == Lang.ru
      ? 'Логово · круг $circle'
      : 'Lair · circle $circle';

  static String lairPreparing(String skill) => Lang.current == Lang.ru
      ? 'Готовит: $skill'
      : 'Preparing: $skill';

  static String lairWeakness(String types, String conduits) =>
      Lang.current == Lang.ru
          ? (conduits.isEmpty
              ? 'Слабость: $types'
              : 'Слабость: $types · $conduits')
          : (conduits.isEmpty
              ? 'Weakness: $types'
              : 'Weakness: $types · $conduits');

  static String lairOfferingLost(String gold) => Lang.current == Lang.ru
      ? 'Подношение сгорело: $gold'
      : 'Offering lost: $gold';

  static String get lairLossHint => const Phrase(
        'Без ответа на его слабость круг у рекорда не берётся.',
        'Without an answer to its weakness, a circle near your record '
            'will not fall.',
      ).text;

  static String get lairStunned => const Phrase('Оглушён', 'Stunned').text;
  static String get lairSilenced => const Phrase('Немота', 'Silenced').text;
  static String get lairExposed => const Phrase('Уязвим', 'Exposed').text;
  static String get lairBurning => const Phrase('Горит', 'Burning').text;
  static String get lairShielded => const Phrase('Щит', 'Shielded').text;
  static String get lairEnraged => const Phrase('Ярость', 'Enraged').text;
  static String get lairGuardianHp =>
      const Phrase('Страж', 'Guardian').text;
  static String get lairSkip => const Phrase('К исходу', 'Skip to end').text;
  static String get lairResult => const Phrase('Исход', 'Outcome').text;

  static String battleBossWindup(String skill) => Lang.current == Lang.ru
      ? 'Страж готовит: $skill'
      : 'The guardian prepares: $skill';

  static String battleBossSkill(String skill) => Lang.current == Lang.ru
      ? '$skill!'
      : '$skill!';

  static String lairDrops(String items) => Lang.current == Lang.ru
      ? 'Роняет: $items'
      : 'Drops: $items';

  static String get lairChallenge =>
      const Phrase('Вызвать', 'Challenge').text;

  static String get lairPickMerc =>
      const Phrase('Кого отправить к стражу', 'Who faces the guardian').text;

  static String get lairLossWarning => const Phrase(
        'Проигравший погибнет. Подношение не возвращается.',
        'The loser dies. The offering is not returned.',
      ).text;

  static String get lairNoMercs => const Phrase(
        'В резерве никого — наймите в Таверне.',
        'Nobody in reserve — hire at the Tavern.',
      ).text;

  static String lairWon(String guardian, int circle) => Lang.current == Lang.ru
      ? '$guardian повержен. Круг $circle взят.'
      : '$guardian falls. Circle $circle taken.';

  static String lairWonAgain(String guardian, int circle) =>
      Lang.current == Lang.ru
          ? '$guardian повержен на круге $circle.'
          : '$guardian falls at circle $circle.';

  static String lairLost(String merc) => Lang.current == Lang.ru
      ? '$merc не вернулся из логова.'
      : '$merc did not return from the lair.';

  static String lairHpLeft(int percent) => Lang.current == Lang.ru
      ? 'Осталось здоровья: $percent %'
      : 'Health left: $percent%';

  static String lairPassivePoints(int points) => Lang.current == Lang.ru
      ? '+$points очка дерева пассивок'
      : '+$points passive points';

  static String lairRelic(String name) => Lang.current == Lang.ru
      ? 'Добыча: $name — ждёт в разборе'
      : 'Loot: $name — waiting to be sorted';

  static String get brandTitle =>
      const Phrase('Клеймо Бездны', 'Brand of the Abyss').text;

  static String brandNextRank(int depth, [int? onRank]) => onRank == null
      ? (Lang.current == Lang.ru
          ? 'следующий ранг с этажа $depth'
          : 'next rank from floor $depth')
      : (Lang.current == Lang.ru
          ? 'следующий ранг: этаж $depth на ранге $onRank'
          : 'next rank: floor $depth at rank $onRank');

  static String get brandRankZero => const Phrase(
        'Ранг 0 — обычный спуск.',
        'Rank 0 — an ordinary descent.',
      ).text;

  static String brandRankEffect(int mobs, int loot, int echo) =>
      Lang.current == Lang.ru
          ? 'Враги +$mobs %, добыча +$loot %, Эхо +$echo %.'
          : 'Enemies +$mobs%, loot +$loot%, Echo +$echo%.';

  static String brandProven(int ranks) => Lang.current == Lang.ru
      ? 'Доказано рангов: $ranks'
      : 'Ranks proven: $ranks';

  static String get brandAbout => const Phrase(
        'Клеймо — добровольная сложность, которую вы выставляете перед '
            'спуском. Каждый ранг делает врагов крепче, а добычу и Эхо '
            'больше.\n\nПервые ранги открывает рекорд глубины. Дальше — '
            'только делом: чтобы открыть следующий ранг, надо дойти до '
            'нужного этажа НА текущем.\n\nКаждый доказанный ранг даёт лишнее '
            'очко дерева пассивок сверх его потолка. Ради этого Клеймо и '
            'нужно: когда глубина упрётся в потолок, расти начнёт сложность — '
            'и вопрос сменится с «как глубоко ты зашёл» на «на каком Клейме '
            'ты там держишься».',
        'The Brand is voluntary difficulty you set before a descent. Every '
            'rank makes enemies tougher and the haul and Echo larger.\n\n'
            'The first ranks are opened by your depth record. After that only '
            'by deed: to open the next rank you must reach the required floor '
            'ON the current one.\n\nEvery proven rank grants one extra '
            'passive tree point above its cap. That is what the Brand is for: '
            'once depth hits its ceiling, difficulty starts growing instead — '
            'and the question turns from “how deep did you get” into “what '
            'Brand can you hold it at”.',
      ).text;

  static String questsClosedTitle(int count) => count == 1
      ? const Phrase('Задание выполнено', 'Quest complete').text
      : (Lang.current == Lang.ru
          ? 'Заданий выполнено: $count'
          : 'Quests complete: $count');

  static String abilityOpened(String name, int echo) {
    final head = Lang.current == Lang.ru
        ? 'Открыто умение: $name'
        : 'Ability unlocked: $name';
    if (echo <= 0) return head;
    return Lang.current == Lang.ru
        ? '$head · +$echo Эха'
        : '$head · +$echo Echo';
  }

  // --- Сборка наёмника -------------------------------------------------------

  static String get statsShort =>
      const Phrase('Характеристики', 'Statistics').text;

  static String get statsTapHint => const Phrase(
        'Все характеристики — по нажатию',
        'Tap for all stats',
      ).text;

  static String get buildLocked => const Phrase(
        'Наёмник в бездне — сборка заперта до конца контракта.',
        'The mercenary is in the abyss — the build is locked until the '
            'contract ends.',
      ).text;

  static String gearSlotHint(int stashed) => Lang.current == Lang.ru
      ? 'Нажмите на слот, чтобы надеть вещь из сундука ($stashed). '
          'Пустые слоты наёмник заполнит сам.'
      : 'Tap a slot to equip from the stash ($stashed). '
          'Empty slots they fill themselves.';

  static String get gearLockedNote => const Phrase(
        'Наёмник ушёл вот с этим.',
        'This is what they left with.',
      ).text;

  static String get forkOrderTitle =>
      const Phrase('Приказ на развилку', 'Standing order at forks').text;

  /// Приказ — это то, что наёмник сделает БЕЗ игрока. На пробе игрок прочитал
  /// «кидает монетку на каждой развилке» как «игра решит всё сама» — и потом
  /// не понял, зачем уведомление зовёт его выбирать путь.
  static String get forkOrderAbout => const Phrase(
        'Действует, только пока вас нет. Придёте на развилку сами — '
            'выберете путь, и откроется третий.',
        'Applies only while you are away. Reach the fork yourself and you '
            'pick the path — the third one included.',
      ).text;

  static String get whatIsWorn => const Phrase('Что надето', 'What is worn').text;

  static String get statSpell => const Phrase('Чары', 'Spell').text;
  static String get emptySlot => const Phrase('Пустой слот', 'Empty slot').text;
  static String get empty => const Phrase('Пусто', 'Empty').text;
  static String get inDetail => const Phrase('Подробно', 'In detail').text;
  static String get abilityWord => const Phrase('Умение', 'Ability').text;
  static String get clear => const Phrase('Очистить', 'Clear').text;
  static String get filterEvery => const Phrase('Все', 'All').text;

  static String manaLine({
    required String pool,
    required String regen,
    required String drain,
    String? full,
    int? reservedPercent,
  }) {
    final head = full == null
        ? (Lang.current == Lang.ru ? 'Мана $pool' : 'Mana $pool')
        : (Lang.current == Lang.ru
            ? 'Мана $pool из $full (ауры держат $reservedPercent %)'
            : 'Mana $pool of $full (auras reserve $reservedPercent%)');
    return Lang.current == Lang.ru
        ? '$head · восстановление $regen/с · расход $drain/с'
        : '$head · regeneration $regen/s · drain $drain/s';
  }

  static String get manaEnough => const Phrase(
        'Маны хватает на всё.',
        'Mana covers everything.',
      ).text;

  static String get manaShort => const Phrase(
        'Расход выше восстановления: в долгом бою умения будут простаивать.',
        'Drain outruns regen: in a long fight abilities will sit idle.',
      ).text;

  static String abilityActive(String cooldown, String mana) =>
      Lang.current == Lang.ru
          ? 'Активное · $cooldown с · $mana маны'
          : 'Active · ${cooldown}s · $mana mana';

  static String abilityAura(int reservedPercent) => Lang.current == Lang.ru
      ? 'Аура · держит $reservedPercent % маны'
      : 'Aura · reserves $reservedPercent% of mana';

  static String get abilityPassive =>
      const Phrase('Пассивное', 'Passive').text;

  static String get noTagMultipliers => const Phrase(
        'Множителей по тегам пока нет. Их дают вещи, пассивки и черта '
            'наёмника.',
        'No tag multipliers yet. Items, passives and the mercenary’s trait '
            'grant them.',
      ).text;

  static String get tagDamageTitle =>
      const Phrase('Урон по тегам', 'Damage by tag').text;

  static String get paleTagsNote => const Phrase(
        'Бледные теги не встречаются ни в одном выбранном умении — эти '
            'проценты сейчас ничего не дают.',
        'None of the chosen abilities carry the pale tags — those '
            'percentages are doing nothing right now.',
      ).text;

  static String slotTakenByTwoHander(String kind) => Lang.current == Lang.ru
      ? '$kind — занята двуручным'
      : '$kind — taken by a two-hander';

  static String get nothingForSlot => const Phrase(
        'В сундуке нет ничего для этого слота.',
        'Nothing in the stash fits this slot.',
      ).text;

  static String get noAbilitiesWithTag => const Phrase(
        'С этим тегом открытых умений пока нет. Остальные открывает древо Эха.',
        'Nothing with that tag is unlocked yet. The Echo tree unlocks the '
            'rest.',
      ).text;

  static String get forkOrderLoot => const Phrase(
        'Редких предметов и осколков больше, глубина и Эхо ниже',
        'More rares and shards; less depth, less Echo',
      ).text;

  static String get forkOrderSafety => const Phrase(
        'Глубже, больше Эха и золота — но добыча беднее',
        'Deeper, more Echo and gold — but a poorer haul',
      ).text;

  static String get forkOrderRandom =>
      const Phrase('Как повезёт', 'Roll the dice').text;

  // --- Разбор умения ---------------------------------------------------------
  //
  // Экран отвечает на один вопрос: от чего это умение растёт и сколько бьёт
  // ИМЕННО У МЕНЯ. Поэтому здесь много коротких подписей строк расчёта — и
  // почти каждая идёт в паре с пояснением под ней.

  static String get abYourStatWeaponOnly => const Phrase(
        'Это ваше число. Урон оружия этому умению не помогает вовсе.',
        'This one is yours. Weapon damage does nothing for this ability.',
      ).text;

  static String get abYourStatSpellOnly => const Phrase(
        'Это ваше число. Сила чар этому умению не помогает вовсе.',
        'This one is yours. Spell power does nothing for this ability.',
      ).text;

  static String get abYourStatWeaponShort => const Phrase(
        'Это ваше число. Урон оружия этому умению не помогает.',
        'This one is yours. Weapon damage does not help here.',
      ).text;

  static String get abYourStatSpellShort => const Phrase(
        'Это ваше число. Сила чар этому умению не помогает.',
        'This one is yours. Spell power does not help here.',
      ).text;

  static String get abMultiplier =>
      const Phrase('Множитель умения', 'Ability multiplier').text;
  static String get abMultiplierAbout => const Phrase(
        'Число самого умения. Оно не меняется никогда.',
        'The ability’s own number. It never changes.',
      ).text;

  static String get abHitBase =>
      const Phrase('Основа удара', 'Base of the hit').text;
  static String get abIncreases =>
      const Phrase('Ваши увеличения', 'Your increases').text;
  static String get abDamagePerHit =>
      const Phrase('Урон за удар', 'Damage per hit').text;

  static String get abTargetsAtOnce =>
      const Phrase('Целей за раз', 'Targets at once').text;
  static String get abWholeWave =>
      const Phrase('вся волна', 'the whole wave').text;
  static String get abTargetsAbout => const Phrase(
        'Урон считается каждой цели отдельно.',
        'Damage is worked out for each target separately.',
      ).text;

  static String get abVsWounded =>
      const Phrase('По раненой цели', 'Against a wounded target').text;
  static String abVsWoundedAbout(int threshold) => Lang.current == Lang.ru
      ? 'Ниже $threshold % здоровья цели. Умение само выбирает самого '
          'раненого врага.'
      : 'Below $threshold% of the target’s health. The ability picks the most '
          'wounded enemy itself.';

  static String get abChainFalloff =>
      const Phrase('Затухание цепи', 'Chain falloff').text;
  static String get abChainFalloffAbout => const Phrase(
        'Каждая следующая цель получает на столько меньше предыдущей.',
        'Each next target takes that much less than the previous one.',
      ).text;

  static String get abVsSlowed =>
      const Phrase('По замедленным', 'Against slowed').text;
  static String get abVsSlowedAbout => const Phrase(
        'Замедление даёт «Ледяной покров» и узел «Стылая хватка».',
        'Slowing comes from Frost Shroud and the Chilling Grip node.',
      ).text;

  static String get abDot =>
      const Phrase('Длительный урон', 'Damage over time').text;
  static String abDotAbout(int fraction) => Lang.current == Lang.ru
      ? 'Доля вашего урона в секунду: $fraction %.'
      : 'A share of your damage per second: $fraction%.';

  static String get abHolds => const Phrase('Держится', 'Lasts').text;
  static String get abTotalPerCast =>
      const Phrase('Всего за наложение', 'Total per application').text;

  static String get abStrikesEvery =>
      const Phrase('Бьёт раз в', 'Strikes every').text;
  static String abTotemAbout(String duration) => Lang.current == Lang.ru
      ? 'Тотем стоит $duration с и бьёт, пока вы заняты другим. Повторное '
          'применение обновляет тот же тотем, а не ставит второй.'
      : 'The totem stands for ${duration}s and strikes while you are busy '
          'elsewhere. Casting again refreshes the same totem instead of '
          'placing a second.';

  static String get abRestores =>
      const Phrase('Восстанавливает', 'Restores').text;
  static String abHealAbout(int fraction) => Lang.current == Lang.ru
      ? '$fraction % вашего максимума HP. На полном здоровье не тратится.'
      : '$fraction% of your maximum HP. Not spent at full health.';

  static String get abAutoAttackDeals =>
      const Phrase('Автоатака бьёт', 'The auto-attack deals').text;
  static String abInfusionAbout(String tag) => Lang.current == Lang.ru
      ? 'Вместо физического урона. Теги автоатаки становятся '
          '«Атака · Удар · $tag» — и всё, что усиливает эту стихию, начинает '
          'работать на автоатаке.'
      : 'Instead of physical damage. The auto-attack’s tags become '
          '“Attack · Strike · $tag” — and everything that boosts that element '
          'starts working on the auto-attack.';

  static String get abAndHarder =>
      const Phrase('И бьёт сильнее', 'And strikes harder').text;
  static String get abAndHarderAbout => const Phrase(
        'Множитель к урону автоатаки.',
        'A multiplier on auto-attack damage.',
      ).text;

  static String get abGivesAlways =>
      const Phrase('Даёт постоянно', 'Gives permanently').text;
  static String get abGivesAlwaysAbout => const Phrase(
        'Работает всё время, пока аура в слоте.',
        'Works the whole time the aura is in a slot.',
      ).text;

  static String abGivesFor(String duration) => Lang.current == Lang.ru
      ? 'Даёт на $duration с'
      : 'Gives for ${duration}s';

  static String get abDoubleHitChance =>
      const Phrase('Шанс ударить дважды', 'Chance to strike twice').text;
  static String get abDoubleHitAbout => const Phrase(
        'Второй удар бесплатный и не трогает перезарядки.',
        'The second strike is free and does not touch cooldowns.',
      ).text;

  static String get abDoubleCastChance =>
      const Phrase('Шанс сработать дважды', 'Chance to trigger twice').text;
  static String get abDoubleCastAbout => const Phrase(
        'Работает только на умениях с тегом «Чары». Повтор бесплатный.',
        'Works only on Spell-tagged abilities. The repeat is free.',
      ).text;

  static String get abReturnsToAttacker =>
      const Phrase('Возвращает ударившему', 'Returns to the attacker').text;
  static String get abReturnsAbout => const Phrase(
        'Долю полученного урона. Считается от того, что до вас дошло: броня и '
            'сопротивления уменьшают и его.',
        'A share of the damage taken. Counted from what actually reached you: '
            'armor and resistances reduce that too.',
      ).text;

  static String abBelowThresholdDamage(int threshold, int percent) =>
      Lang.current == Lang.ru
          ? 'Ниже $threshold % — $percent % урона'
          : 'Below $threshold% — $percent% damage';

  static String get abLessDamageAbout => const Phrase(
        'Множитель к получаемому урону, а не к броне.',
        'A multiplier on damage taken, not on armor.',
      ).text;

  static String abBelowThresholdLeech(int threshold, String multiplier) =>
      Lang.current == Lang.ru
          ? 'Ниже $threshold % — вампиризм ×$multiplier'
          : 'Below $threshold% — life leech ×$multiplier';

  static String get abLeechMultiAbout => const Phrase(
        'Множитель к вампиризму, который у вас уже есть. Без вампиризма '
            'умножать нечего.',
        'A multiplier on the life leech you already have. With no leech there '
            'is nothing to multiply.',
      ).text;

  static String get abTradeoff => const Phrase('Размен', 'Trade-off').text;
  static String get abTradeoffAbout => const Phrase(
        'Считается один раз при сборке, а не в бою.',
        'Worked out once when you build, not during the fight.',
      ).text;

  static String get abSlowsAttackers =>
      const Phrase('Замедляет атакующих', 'Slows attackers').text;
  static String get abSlowsAbout => const Phrase(
        'Скорость их атак. Замедленные цели — условие для «Морозного шипа» и '
            'узла «Охотник на медленных».',
        'Their attack speed. Slowed targets are the condition for Frost Spike '
            'and the Hunter of the Slow node.',
      ).text;

  static String abCorpseBurst(int percent) => Lang.current == Lang.ru
      ? 'Взрыв трупа — $percent % HP убитого'
      : 'Corpse burst — $percent% of the slain enemy’s HP';

  static String get abCorpseBurstAbout => const Phrase(
        'Только по проклятым целям. От ваших характеристик урон взрыва не '
            'зависит — зато теги на него действуют.',
        'Only on cursed targets. The burst does not scale from your '
            'statistics — but tags do apply to it.',
      ).text;

  static String get abTargetTakesMore =>
      const Phrase('Цель получает больше урона', 'Target takes more damage')
          .text;

  static String abBrandAbout(String duration) => Lang.current == Lang.ru
      ? 'От любого источника, $duration с. Проклятие — условие для «Печати '
          'бездны» и узла «Печать увядания».'
      : 'From any source, for ${duration}s. A curse is the condition for Seal '
          'of the Abyss and the Seal of Withering node.';

  static String abOnCrit(String chance) => Lang.current == Lang.ru
      ? 'Срабатывает от крита — ваш шанс $chance'
      : 'Triggers on a crit — your chance is $chance';

  static String get abOnCritAbout => const Phrase(
        'Без шанса крита умение не работает вовсе.',
        'With no crit chance the ability does not work at all.',
      ).text;

  static String get abPerSecondTotal =>
      const Phrase('Итого в секунду', 'Total per second').text;
  static String get abPerSecondAbout => const Phrase(
        'С учётом перезарядки и числа целей. Мана и живучесть цели тут не '
            'учтены.',
        'Cooldown and target count included. Mana and the target’s toughness '
            'are not.',
      ).text;

  static String get abScalesFrom =>
      const Phrase('От чего растёт', 'What it scales from').text;

  static String get abDamageType =>
      const Phrase('Тип урона', 'Damage type').text;

  static String get abPhysicalAbout => const Phrase(
        'Уменьшается бронёй цели. Броня врагов растёт с глубиной, поэтому '
            'физический урон труднее всего тащить вниз.',
        'Reduced by the target’s armor. Enemy armor grows with depth, which '
            'makes physical damage the hardest to carry down.',
      ).text;

  static String abElementalAbout(String element) => Lang.current == Lang.ru
      ? 'Уменьшается сопротивлением «$element» у цели, и бронёй тоже. '
          'У чудовищ сопротивление своей стихии обычно высокое — бить их той '
          'же стихией невыгодно.'
      : 'Reduced by the target’s $element resistance, and by armor too. '
          'Monsters usually resist their own element strongly — hitting them '
          'with it is a poor trade.';

  static String get abCooldown => const Phrase('Перезарядка', 'Cooldown').text;

  static String abCooldownBreakdown(String base, String cut) =>
      Lang.current == Lang.ru
          ? 'Базовая $base с, ваше сокращение $cut'
          : 'Base ${base}s, your reduction $cut';

  static String get abCooldownAbout => const Phrase(
        'Сокращается свойством «−% ко времени перезарядки» и лучом «Порыв».',
        'Reduced by the “−% cooldown time” property and the Gust branch.',
      ).text;

  static String get abManaCost => const Phrase('Стоит маны', 'Mana cost').text;

  static String abManaCostAbout(String pool, String regen) =>
      Lang.current == Lang.ru
          ? 'Ваш запас $pool, восстановление $regen в секунду. Не хватило — '
              'умение ждёт, наёмник продолжает бить оружием.'
          : 'Your pool is $pool, regeneration $regen per second. If it runs '
              'short the ability waits and the mercenary keeps swinging.';

  static String get abDrain => const Phrase('Расход', 'Drain').text;

  static String abManaPerSecond(String value) => Lang.current == Lang.ru
      ? '$value маны в секунду'
      : '$value mana per second';

  static String get abDrainAbout => const Phrase(
        'Столько это умение съедает из общего запаса, если срабатывает без '
            'перерыва.',
        'That is what this ability eats from the shared pool if it fires '
            'without a break.',
      ).text;

  static String get abReserves => const Phrase('Резервирует', 'Reserves').text;

  static String abReservesPercent(int percent) => Lang.current == Lang.ru
      ? '$percent % маны'
      : '$percent% of mana';

  static String abReservesAbout(String pool, String left) =>
      Lang.current == Lang.ru
          ? 'Забирает и запас, и восстановление — насовсем, пока аура в слоте. '
              'Из $pool останется $left.'
          : 'Takes the pool and the regeneration both, for as long as the '
              'aura sits in a slot. Of $pool, $left is left to you.';

  static String get abCostsWord => const Phrase('Стоит', 'Costs').text;
  static String get abOneSlot =>
      const Phrase('одно место', 'one slot').text;

  static String get abPassiveAbout => const Phrase(
        'Пассивное умение работает всегда и маны не тратит. Его цена — место, '
            'которое не досталось активному.',
        'A passive ability always works and spends no mana. Its price is the '
            'slot an active one did not get.',
      ).text;

  static String get abPrice => const Phrase('Цена', 'Price').text;
  static String get abTags => const Phrase('Теги', 'Tags').text;

  static String get abTagsAbout => const Phrase(
        'Тег — единственное, за что цепляются вещи, дерево пассивок и черта '
            'наёмника. Множитель по тегу, которого у умения нет, на него не '
            'действует.',
        'A tag is the only thing items, the passive tree and a mercenary’s '
            'trait can hook onto. A multiplier for a tag the ability does not '
            'carry does nothing at all.',
      ).text;

  static String abTagElement(String tag) => Lang.current == Lang.ru
      ? 'Стихия. Ищите «+% к урону $tag» на вещах и луч этой стихии в дереве.'
      : 'An element. Look for “+% $tag” on items and this element’s branch in '
          'the tree.';

  static String get abTagAttack => const Phrase(
        'Растёт от урона оружия. Его же несёт автоатака.',
        'Scales from weapon damage. The auto-attack carries it too.',
      ).text;

  static String get abTagSpell => const Phrase(
        'Растёт от силы чар. Урон оружия не помогает.',
        'Scales from spell power. Weapon damage does not help.',
      ).text;

  static String get abTagProjectile => const Phrase(
        'Летит в цель. Аффиксы на снаряды усиливают.',
        'Flies at a target. Projectile affixes boost it.',
      ).text;

  static String get abTagArea => const Phrase(
        'Задевает нескольких сразу. Аффиксы на область усиливают.',
        'Hits several at once. Area affixes boost it.',
      ).text;

  static String get abTagDuration => const Phrase(
        'Урон идёт со временем, а не сразу.',
        'Damage arrives over time, not at once.',
      ).text;

  static String get abTagCurse => const Phrase(
        'Вешает проклятие. Его ждут «Печать бездны» и «Печать увядания».',
        'Applies a curse. Seal of the Abyss and Seal of Withering wait for it.',
      ).text;

  static String get abTagAura => const Phrase(
        'Работает постоянно за резерв маны.',
        'Works permanently for a mana reservation.',
      ).text;

  static String get abTagTotem => const Phrase(
        'Бьёт сам, пока наёмник занят другим.',
        'Strikes on its own while the mercenary is busy elsewhere.',
      ).text;

  static String get abTagStrike => const Phrase(
        'Удар оружием. Его же несёт автоатака.',
        'A weapon strike. The auto-attack carries it too.',
      ).text;

  static String get abTagBlood => const Phrase(
        'Кровь: вампиризм, кровотечение, добивание.',
        'Blood: leech, bleeding, finishers.',
      ).text;

  static String abIncreaseGeneral(int percent) => Lang.current == Lang.ru
      ? 'общее +$percent %'
      : 'general +$percent%';

  static String get abNoIncreases => const Phrase(
        'Увеличений нет. Их дают свойства вещей, дерево пассивок и черта '
            'наёмника.',
        'No increases. They come from item properties, the passive tree and '
            'the mercenary’s trait.',
      ).text;

  static String abIncreasesFrom(String parts) => Lang.current == Lang.ru
      ? 'Складывается: $parts.'
      : 'Adds up from: $parts.';

  static String get abKindActive => const Phrase(
        'Активное — срабатывает само, когда готово и хватает маны',
        'Active — fires by itself when ready and mana allows',
      ).text;

  static String get abKindAura => const Phrase(
        'Аура — работает всегда, держит часть маны занятой',
        'Aura — always on, keeps part of the mana reserved',
      ).text;

  static String get abKindPassive => const Phrase(
        'Пассивное — работает всегда и ничего не стоит',
        'Passive — always on and costs nothing',
      ).text;

  // --- Кузница ---------------------------------------------------------------

  static String get forgeNow => const Phrase('Сейчас', 'Now').text;
  static String get forgeBecomes => const Phrase('Станет', 'Becomes').text;
  static String get notEnoughGoldShort =>
      const Phrase('Не хватает золота', 'Not enough gold').text;

  static String get rerollTitle =>
      const Phrase('Перебросить свойство', 'Reroll a property').text;

  static String get rerollAbout => const Phrase(
        'Число у свойства бросается заново. Что выпадет — неизвестно; '
            'известно только, между чем и чем.',
        'The property’s number is rolled again. You will not know what comes '
            'up — only the range it lands in.',
      ).text;

  static String qualityOutOf(int percentile) => Lang.current == Lang.ru
      ? 'качество $percentile из 100'
      : 'quality $percentile out of 100';

  static String rerollNoWorse(String line) => Lang.current == Lang.ru
      ? 'не хуже: $line'
      : 'no worse than: $line';

  static String rerollNoBetter(String line) => Lang.current == Lang.ru
      ? 'не лучше: $line'
      : 'no better than: $line';

  static String get rerollRisk => const Phrase(
        'Может выйти хуже, чем сейчас. Кузница поднимает нижнюю границу — '
            'чем она выше, тем спокойнее переброс.',
        'It can land worse than it is now. The Forge raises the floor of the '
            'range — the higher that floor, the safer the reroll.',
      ).text;

  static String get rerollSafe => const Phrase(
        'Хуже не станет: Кузница подняла нижнюю границу выше нынешнего числа.',
        'It cannot come out worse: the Forge has raised the floor of the '
            'range above the number you have now.',
      ).text;

  static String get reroll => const Phrase('Перебросить', 'Reroll').text;

  static String get extractTitle =>
      const Phrase('Разобрать на осколок', 'Break down into a shard').text;

  static String get extractAbout => const Phrase(
        'Вещь исчезает целиком. От неё остаётся одно свойство — то, что вы '
            'выбрали, — в виде осколка. Осколок помнит, насколько УДАЧНО оно '
            'выпало, а не само число: поэтому его можно перенести на вещь '
            'получше, и там он даст больше.',
        'The item is destroyed entirely. One property remains — the one you '
            'chose — as a shard. A shard remembers HOW WELL it rolled, not '
            'the number itself: that is why it can be moved onto a better '
            'item, where it gives more.',
      ).text;

  static String shardOfQuality(int quality) => Lang.current == Lang.ru
      ? 'осколок качества $quality из 100'
      : 'a shard of quality $quality out of 100';

  static String get extractLoseRest => const Phrase(
        'Остальные свойства этой вещи пропадут.',
        'Everything else on the item goes with it.',
      ).text;

  static String get extract => const Phrase('Разобрать', 'Break down').text;

  static String get shardStorageFull => const Phrase(
        'Хранилище осколков заполнено',
        'Shard storage is full',
      ).text;

  static String shardReady(int quality) => Lang.current == Lang.ru
      ? 'Осколок качества $quality готов'
      : 'A shard of quality $quality is ready';

  static String get deepenTitle =>
      const Phrase('Углубить реликт', 'Deepen the relic').text;

  static String deepenAbout(int ilvl) => Lang.current == Lang.ru
      ? 'Уровень реликта поднимается до $ilvl, и всё, что от него зависит, '
          'пересчитывается. Уникальный эффект не меняется — он и не стареет.'
      : 'The relic’s level rises to $ilvl, and everything that depends on it '
          'is recomputed. The unique effect does not change — it does not age.';

  static String get deepen => const Phrase('Углубить', 'Deepen').text;

  static String deepenTo(int ilvl) => Lang.current == Lang.ru
      ? 'Углубить до $ilvl'
      : 'Deepen to $ilvl';

  static String get deepenGate => const Phrase(
        'Углубление доступно, пока уровень реликта ниже вашего рекорда глубины.',
        'Deepening is available while the relic’s level is below your depth '
            'record.',
      ).text;

  static String get imprintTitle =>
      const Phrase('Впечатать осколок', 'Imprint a shard').text;

  static String get imprintAbout => const Phrase(
        'Осколок ляжет в свободное место. Его удача пересчитается под уровень '
            'этой вещи — поэтому старый осколок не устаревает.',
        'The shard goes into a free slot. Its luck is recomputed for this '
            'item’s level — which is why an old shard never goes stale.',
      ).text;

  static String shardQualityShort(int quality) => Lang.current == Lang.ru
      ? 'осколок качества $quality'
      : 'shard of quality $quality';

  static String get imprint => const Phrase('Впечатать', 'Imprint').text;

  static String get didNotFit => const Phrase('Не подошло', 'Did not fit').text;

  static String imprinted(int percentile) => Lang.current == Lang.ru
      ? 'Вставлено, качество $percentile'
      : 'Imprinted, quality $percentile';

  static String get replaceTitle =>
      const Phrase('Заменить свойство', 'Replace a property').text;

  static String get replaceNoRoom => const Phrase(
        'Свободных мест нет: осколок займёт место выбранного свойства.',
        'No free slots: the shard takes the place of the chosen property.',
      ).text;

  static String replaceSaveChance(int percent) => Lang.current == Lang.ru
      ? 'Стёртое свойство пропадёт. Верстак осколков спасает его с '
          'вероятностью $percent %.'
      : 'The erased property is lost. The Shard Bench saves it with a '
          '$percent% chance.';

  static String get replaceNoChance => const Phrase(
        'Стёртое свойство пропадёт насовсем. Шанс сохранить его даёт Верстак '
            'осколков.',
        'The erased property is lost for good. The Shard Bench is what gives '
            'a chance to keep it.',
      ).text;

  static String get replace => const Phrase('Заменить', 'Replace').text;

  static String get propertyReplaced =>
      const Phrase('Свойство заменено', 'Property replaced').text;

  static String goldAmount(String gold) =>
      Lang.current == Lang.ru ? 'Золото $gold' : 'Gold $gold';

  static String shardsHeader(int held, int capacity) => Lang.current == Lang.ru
      ? 'Осколки · ${outOf(held, capacity)}'
      : 'Shards · ${outOf(held, capacity)}';

  static String get shardsEmptyAbout => const Phrase(
        'Осколок хранит удачу свойства, а не число, — поэтому не устаревает. '
            'Разберите вещь, чтобы получить первый.',
        'A shard keeps how lucky a roll was, not the number — so it never '
            'goes stale. Break an item down to get your first.',
      ).text;

  static String stashHeader(int held, int capacity) => Lang.current == Lang.ru
      ? 'Сундук · ${outOf(held, capacity)}'
      : 'Stash · ${outOf(held, capacity)}';

  static String get stashEmptyForge => const Phrase(
        'Пусто. Добыча приходит с наёмниками.',
        'Empty. The haul comes with mercenaries.',
      ).text;

  static String get toShard => const Phrase('В осколок', 'To a shard').text;

  static String get shardRecomputeNote => const Phrase(
        'Число пересчитается под уровень выбранной вещи: чем она глубже, тем '
            'больше даст та же удача.',
        'The number is recomputed for the chosen item’s level: the deeper it '
            'is, the more the same luck gives.',
      ).text;

  static String get noSuitableItems => const Phrase(
        'Нет подходящих предметов в сундуке.',
        'No suitable items in the stash.',
      ).text;

  /// Сколько свойств из скольких, и реликт ли это. Без уровня и редкости:
  /// в Кузнице они уже написаны строкой выше.
  static String propertyCount(int used, int max, {required bool relic}) {
    final head = Lang.current == Lang.ru
        ? 'свойств ${outOf(used, max)}'
        : '${outOf(used, max)} properties';
    if (!relic) return head;
    return Lang.current == Lang.ru ? '$head · реликт' : '$head · relic';
  }

  static String get freeSlot => const Phrase('свободный слот', 'free slot').text;
  static String get overwrite => const Phrase('перезапись', 'overwrite').text;

  static String get whatToErase =>
      const Phrase('Что стереть', 'What to erase').text;

  static String get replaceNoRoomAny => const Phrase(
        'Свободных мест нет: осколок займёт место одного из свойств.',
        'No free slots: the shard takes the place of one of the properties.',
      ).text;

  static String becomes(String line) =>
      Lang.current == Lang.ru ? 'станет: $line' : 'becomes: $line';

  static String abilitySlotHint({required bool many}) => Lang.current == Lang.ru
      ? (many
          ? 'Поставить их в слоты можно в сборке наёмника.'
          : 'Поставить его в слот можно в сборке наёмника.')
      : (many
          ? 'You can put them into slots in the mercenary’s build.'
          : 'You can put it into a slot in the mercenary’s build.');

  static String notifyDeathBody({required bool she, required int depth}) =>
      Lang.current == Lang.ru
          ? '${she ? "Погибла" : "Погиб"} на этаже $depth. '
              'Добыча ждёт на Заставе.'
          : '${she ? "She" : "He"} fell on floor $depth. The haul is waiting '
              'at the Outpost.';
}
