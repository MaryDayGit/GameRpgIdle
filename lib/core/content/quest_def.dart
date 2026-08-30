import '../model/tags.dart';
import 'json_node.dart';
import 'params.dart';

/// Что именно проверяет задание.
///
/// Закрытый список, как `AbilityKind` и `EchoRule`: условие, которого нет в
/// этом перечислении, никто не сможет выполнить, и валидатор скажет об этом
/// на загрузке, а не через месяц молчаливым «задание висит вечно».
enum QuestCondition {
  /// Рекорд глубины достиг N.
  reachDepth,

  /// Закрыто N контрактов.
  runsCompleted,

  /// Уложен конкретный босс (`boss` — его id).
  defeatBoss,

  /// За ОДИН спуск нанесена доля урона данного типа (`damageType`, `value`).
  ///
  /// Единственный вид цели, который спрашивает про билд, а не про глубину:
  /// выполнить его можно только собрав сборку вокруг стихии.
  damageShare,

  /// В сборке одновременно N способностей с тегом `tag`.
  loadoutTag,

  /// Глубина N достигнута на Клейме ранга не ниже `rank`.
  brandDepth,

  /// Постройка `building` доведена до уровня N.
  outpostLevel,

  /// Куплено N узлов древа Эха.
  echoNodes,

  /// Потрачено N очков дерева пассивок.
  passivePoints,

  /// На Верстаке лежит N осколков одновременно.
  shardsHeld,

  /// Найдено N реликтов за всё время.
  relicsFound,
}

/// Схема параметров условия. Пустой список — условию хватает `value`.
const Map<QuestCondition, List<ParamSpec>> questParamSpecs = {
  QuestCondition.defeatBoss: [ParamSpec.text('boss')],
  QuestCondition.damageShare: [ParamSpec.text('damageType')],
  QuestCondition.loadoutTag: [ParamSpec.text('tag')],
  QuestCondition.brandDepth: [ParamSpec.integer('rank')],
  QuestCondition.outpostLevel: [ParamSpec.text('building')],
};

/// Задание.
///
/// Смысл заданий один и он не про награду: **вложенные цели.** Idle живёт
/// тем, что игрок в любой момент знает, ради чего сделает следующий шаг, — и
/// цель, названная вслух, держит лучше, чем цель, о которой он догадывается
/// сам.
///
/// Живой прогон дал это замечанием «умений мало, и они все сразу открыты»:
/// древо Эха открывало по одиннадцать способностей одним узлом, и открытие
/// переставало быть событием. Теперь у каждой способности своё задание, и
/// путь к ней — это цепочка, а не покупка.
class QuestDef {
  const QuestDef({
    required this.id,
    required this.name,
    required this.text,
    required this.chain,
    required this.condition,
    required this.value,
    required this.params,
    required this.after,
    required this.rewardAbility,
    required this.rewardEcho,
  });

  final String id;
  final String name;

  /// Что надо сделать — словами. Пишется как ЗАДАЧА, а не как описание
  /// условия: «Уложите Владыку Пепла», а не «bossesKilled содержит ash_lord».
  final String text;

  /// Цепь, к которой задание принадлежит. Нужна экрану для группировки:
  /// сорок четыре задания одним списком — это не цели, а простыня.
  final String chain;

  final QuestCondition condition;

  /// Порог условия. У `damageShare` — доля, у остальных — число.
  final double value;

  final Params params;

  /// Задания, без которых это не показывается.
  ///
  /// Не запрет, а видимость: игрок должен видеть следующий шаг, а не все
  /// сорок четыре сразу. Выполниться задание может и раньше срока — тогда
  /// оно закроется в тот же миг, когда откроется, и это честно.
  final List<String> after;

  /// Способность, которую задание открывает. Ради неё оно и существует.
  final String rewardAbility;

  /// Эхо сверх способности. Небольшое: награда задания — новое умение, а не
  /// валюта.
  final int rewardEcho;

  static const _keys = {
    'id', 'ru', 'text', 'chain', 'condition', 'value', 'params',
    'after', 'ability', 'echo',
  };

  static QuestDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final condition =
        node.enumByName('condition', QuestCondition.values,
            or: QuestCondition.reachDepth)!;
    final params = readParams(node, questParamSpecs[condition] ?? const []);

    final value = node.dbl('value', or: 0.0);
    if (value <= 0.0) {
      node.issues.add('${node.path}.value',
          'условие с нулевым порогом выполнено с самого начала');
    }
    if (condition == QuestCondition.damageShare && value > 1.0) {
      node.issues.add('${node.path}.value',
          'доля урона задаётся в пределах (0, 1], а не процентами');
    }

    // Перекрёстные проверки: строка, которая не совпала ни с чем, — это
    // задание, которое невозможно выполнить, и заметить это можно только
    // играя.
    if (condition == QuestCondition.damageShare && params.has('damageType')) {
      final name = params.str('damageType');
      if (!DamageType.values.any((t) => t.name == name)) {
        node.issues.add('${node.path}.params.damageType',
            'неизвестный тип урона «$name»');
      }
    }
    if (condition == QuestCondition.loadoutTag && params.has('tag')) {
      final name = params.str('tag');
      if (!Tag.values.any((t) => t.name == name)) {
        node.issues.add('${node.path}.params.tag', 'неизвестный тег «$name»');
      }
    }

    if (node.str('ability', or: '').isEmpty) {
      node.issues.add('${node.path}.ability',
          'задание без награды — это цель без причины её достигать');
    }

    return QuestDef(
      id: node.str('id'),
      name: node.str('ru'),
      text: node.str('text'),
      chain: node.str('chain', or: 'main'),
      condition: condition,
      value: value,
      params: params,
      after: node.strList('after'),
      rewardAbility: node.str('ability', or: ''),
      rewardEcho: node.integer('echo', or: 0),
    );
  }

  @override
  String toString() => 'QuestDef($id -> $rewardAbility)';
}
