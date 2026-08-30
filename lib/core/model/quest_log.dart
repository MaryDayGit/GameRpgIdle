import '../content/content_pack.dart';
import '../content/quest_def.dart';
import 'outpost.dart';
import 'tags.dart';

/// Всё, что заданиям нужно знать об игроке и о последнем спуске.
///
/// Отдельным объектом, а не ссылкой на профиль, по двум причинам. Первая:
/// проверка условий становится проверяемой в одиночку — тест на «задание
/// закрывается, когда доля урона Молнией дошла до половины» не должен
/// поднимать спуск целиком. Вторая: видно, какие ровно факты игра о себе
/// знает, — а значит видно и то, какие цели ей можно ставить.
class QuestFacts {
  const QuestFacts({
    this.maxDepthEver = 0,
    this.runsCompleted = 0,
    this.relicsFound = 0,
    this.echoNodes = 0,
    this.passivePoints = 0,
    this.shardsHeld = 0,
    this.bestDepthByBrand = const {},
    this.outpost = const {},
    this.bossesKilled = const {},
    this.damageShare = const {},
    this.loadoutTags = const {},
  });

  // --- Накопленное игроком ---------------------------------------------------
  final int maxDepthEver;
  final int runsCompleted;
  final int relicsFound;
  final int echoNodes;
  final int passivePoints;
  final int shardsHeld;

  /// Лучшая глубина на каждом ранге Клейма.
  final Map<int, int> bestDepthByBrand;
  final Map<Building, int> outpost;

  // --- Про ПОСЛЕДНИЙ спуск ---------------------------------------------------
  //
  // Эти факты живут ровно один вызов проверки. Задание про билд («нанесите
  // половину урона Молнией») обязано спрашивать про один конкретный спуск:
  // сумма за всю игру ответила бы «да» любому игроку, который однажды взял
  // молнию в слот.
  final Set<String> bossesKilled;

  /// Доля урона по типам за спуск, 0..1.
  final Map<DamageType, double> damageShare;

  /// Сколько способностей с каждым тегом было в сборке.
  final Map<Tag, int> loadoutTags;

  /// Есть ли данные о спуске. Часть условий без него не проверяется, и
  /// проверять их «на всякий случай» значило бы закрывать задания в момент,
  /// когда игрок ничего не делал.
  bool get hasRun => damageShare.isNotEmpty || bossesKilled.isNotEmpty;
}

/// Журнал заданий: что выполнено и сколько всего пройдено.
///
/// Задания — единственный источник новых способностей. Раньше их открывало
/// древо Эха по одиннадцать штук одним узлом, и живой прогон дал приговор:
/// «умений мало, и они все сразу открыты». Открытие, случающееся одиннадцать
/// раз одновременно, перестаёт быть событием — а это ровно то, ради чего
/// новое умение и нужно.
class QuestLog {
  QuestLog({
    Iterable<String>? completed,
    this.runsCompleted = 0,
    this.relicsFound = 0,
  }) : _completed = {...?completed};

  final Set<String> _completed;

  /// Счётчики, которых нет больше нигде: профиль хранит текущее состояние, а
  /// не историю. «Закройте десять контрактов» по нему не проверить.
  int runsCompleted;
  int relicsFound;

  Set<String> get completed => Set.unmodifiable(_completed);
  int get doneCount => _completed.length;

  bool isDone(String id) => _completed.contains(id);

  /// Показывается ли задание. Не запрет, а видимость: игрок должен видеть
  /// следующий шаг, а не все сорок четыре сразу.
  bool isVisible(QuestDef quest) =>
      quest.after.every(_completed.contains);

  /// Способности, открытые заданиями.
  Set<String> get unlockedAbilities => {
        for (final quest in ContentPack.current.quests)
          if (_completed.contains(quest.id)) quest.rewardAbility,
      };

  /// Закрывает всё, что стало выполненным. Возвращает закрытое ЗА ЭТОТ вызов
  /// — экран показывает по нему «Задание выполнено: открыто умение …».
  ///
  /// Порядок обхода — порядок контента, и это важно: цепь, у которой второе
  /// звено выполнилось вместе с первым, закроется целиком за один вызов, а не
  /// растянется на столько спусков, сколько в ней звеньев.
  List<QuestDef> check(QuestFacts facts) {
    final closed = <QuestDef>[];

    // Несколько проходов: закрытое звено открывает следующее, и оно может
    // быть выполнено уже сейчас. Без повтора игрок увидел бы «выполнено»
    // только после следующего спуска — при том что делать ничего не надо.
    var changed = true;
    var guard = 0;
    while (changed && ++guard < 20) {
      changed = false;
      for (final quest in ContentPack.current.quests) {
        if (_completed.contains(quest.id)) continue;
        if (!isVisible(quest)) continue;
        if (!_satisfied(quest, facts)) continue;

        _completed.add(quest.id);
        closed.add(quest);
        changed = true;
      }
    }
    return closed;
  }

  /// Текущее и нужное — для строки прогресса на экране.
  ///
  /// `null` у условий про один спуск: у них нет накопления, и «3 из 10» о них
  /// соврало бы. Такое задание либо выполнено спуском, либо нет.
  (double current, double target)? progressOf(QuestDef quest, QuestFacts f) {
    final current = switch (quest.condition) {
      QuestCondition.reachDepth => f.maxDepthEver.toDouble(),
      QuestCondition.runsCompleted => f.runsCompleted.toDouble(),
      QuestCondition.echoNodes => f.echoNodes.toDouble(),
      QuestCondition.passivePoints => f.passivePoints.toDouble(),
      QuestCondition.shardsHeld => f.shardsHeld.toDouble(),
      QuestCondition.relicsFound => f.relicsFound.toDouble(),
      QuestCondition.outpostLevel =>
        (f.outpost[_building(quest)] ?? 0).toDouble(),
      QuestCondition.brandDepth => _bestAtRank(quest, f).toDouble(),
      QuestCondition.defeatBoss ||
      QuestCondition.damageShare ||
      QuestCondition.loadoutTag =>
        null,
    };
    if (current == null) return null;
    return (current.clamp(0.0, quest.value), quest.value);
  }

  bool _satisfied(QuestDef quest, QuestFacts f) => switch (quest.condition) {
        QuestCondition.reachDepth => f.maxDepthEver >= quest.value,
        QuestCondition.runsCompleted => f.runsCompleted >= quest.value,
        QuestCondition.echoNodes => f.echoNodes >= quest.value,
        QuestCondition.passivePoints => f.passivePoints >= quest.value,
        QuestCondition.shardsHeld => f.shardsHeld >= quest.value,
        QuestCondition.relicsFound => f.relicsFound >= quest.value,
        QuestCondition.outpostLevel =>
          (f.outpost[_building(quest)] ?? 0) >= quest.value,
        QuestCondition.brandDepth => _bestAtRank(quest, f) >= quest.value,
        QuestCondition.defeatBoss =>
          f.bossesKilled.contains(quest.params.str('boss')),
        QuestCondition.damageShare => _damageShare(quest, f) >= quest.value,
        QuestCondition.loadoutTag => _loadoutTag(quest, f) >= quest.value,
      };

  static Building? _building(QuestDef quest) {
    final name = quest.params.str('building');
    for (final b in Building.values) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// Лучшая глубина на ранге НЕ НИЖЕ требуемого.
  ///
  /// Не «ровно на этом ранге»: игрок, ушедший вниз на более высоком Клейме,
  /// сделал заведомо больше, и требовать от него вернуться на указанный —
  /// значит наказывать за прогресс.
  static int _bestAtRank(QuestDef quest, QuestFacts f) {
    final wanted = quest.params.integer('rank', 0);
    var best = 0;
    f.bestDepthByBrand.forEach((rank, depth) {
      if (rank >= wanted && depth > best) best = depth;
    });
    return best;
  }

  static double _damageShare(QuestDef quest, QuestFacts f) {
    final name = quest.params.str('damageType');
    for (final type in DamageType.values) {
      if (type.name == name) return f.damageShare[type] ?? 0.0;
    }
    return 0.0;
  }

  static int _loadoutTag(QuestDef quest, QuestFacts f) {
    final name = quest.params.str('tag');
    for (final tag in Tag.values) {
      if (tag.name == name) return f.loadoutTags[tag] ?? 0;
    }
    return 0;
  }
}
