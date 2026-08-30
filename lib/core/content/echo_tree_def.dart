import '../model/stat_key.dart';
import 'json_node.dart';

/// Что делает узел древа Эха.
///
/// Ровно два вида, и это не упрощение: узел либо двигает число в собранном
/// билде, либо меняет правило. Третьего вида нет, потому что узел, которого
/// не читает симуляция, — это текст на экране (GDD §8.3).
enum EchoEffectKind { stat, rule }

/// Правила, которые древо умеет менять. Закрытый список: правило, которого
/// нет здесь, не сможет ничего изменить, и валидатор скажет об этом сразу,
/// а не через месяц молчаливым «узел ничего не даёт».
enum EchoRule {
  /// Стартовая глубина спуска.
  startDepth,

  /// Дополнительный слот способностей.
  abilitySlot,

  /// +1 слот аффикса всем предметам.
  affixSlot,

  /// Раз за спуск смертельный удар оставляет 1 HP.
  deathThreshold,

  /// Один осколок переживает смерть наёмника.
  keepShard,
}

/// Узел древа.
class EchoNodeDef {
  const EchoNodeDef({
    required this.id,
    required this.branchId,
    required this.name,
    required this.text,
    required this.kind,
    required this.value,
    this.stat,
    this.rule,
    this.allResists = false,
  });

  final String id;
  final String branchId;
  final String name;
  final String text;

  final EchoEffectKind kind;
  final double value;

  /// Для [EchoEffectKind.stat]: какой стат двигает. `null` у правил и у
  /// особого случая «все сопротивления».
  final StatKey? stat;

  /// Для [EchoEffectKind.rule]: какое правило меняет.
  final EchoRule? rule;

  /// Особый случай: одна запись вместо трёх одинаковых по сопротивлениям.
  final bool allResists;

  bool get isRule => kind == EchoEffectKind.rule;
}

/// Ветка древа.
class EchoBranchDef {
  const EchoBranchDef({
    required this.id,
    required this.name,
    required this.about,
    required this.nodes,
  });

  final String id;
  final String name;

  /// Одно слово о том, за что ветка отвечает: выживание, урон, правила.
  final String about;

  /// Узлы в порядке открытия: следующий доступен, когда куплен предыдущий.
  final List<EchoNodeDef> nodes;
}

/// Разбор древа Эха.
class EchoTreeParser {
  EchoTreeParser._();

  static const _branchKeys = {'id', 'ru', 'about', 'nodes'};
  static const _nodeKeys = {
    'id', 'ru', 'text', 'kind', 'stat', 'rule', 'value',
  };

  /// Особый стат: одна запись «+10 ко всем сопротивлениям» вместо трёх.
  static const _allResists = 'allResists';

  static List<EchoBranchDef> parse(JsonNode root) {
    final out = <EchoBranchDef>[];
    final seen = <String>{};

    for (final node in root.children('branches')) {
      node.checkKeys(_branchKeys);

      final branchId = node.str('id');
      final nodes = <EchoNodeDef>[];

      for (final raw in node.children('nodes')) {
        final parsed = _node(raw, branchId, seen);
        if (parsed != null) nodes.add(parsed);
      }

      if (nodes.isEmpty) {
        node.issues.add('${node.path}.nodes', 'ветка без узлов');
      }

      out.add(EchoBranchDef(
        id: branchId,
        name: node.str('ru'),
        about: node.str('about'),
        nodes: nodes,
      ));
    }

    if (out.isEmpty) root.issues.add(root.path, 'древо без веток');
    return out;
  }

  static EchoNodeDef? _node(JsonNode node, String branchId, Set<String> seen) {
    node.checkKeys(_nodeKeys);

    final id = node.str('id');
    if (!seen.add(id)) {
      node.issues.add('${node.path}.id', 'узел «$id» объявлен дважды');
    }

    final kind = node.enumByName('kind', EchoEffectKind.values);
    if (kind == null) return null;

    final value = node.dbl('value');
    if (value == 0.0) {
      node.issues.add('${node.path}.value',
          'узел без величины не делает ничего');
    }

    if (kind == EchoEffectKind.rule) {
      final rule = node.enumByName('rule', EchoRule.values);
      if (rule == null) return null;

      return EchoNodeDef(
        id: id,
        branchId: branchId,
        name: node.str('ru'),
        text: node.str('text'),
        kind: kind,
        rule: rule,
        value: value,
      );
    }

    final statName = node.str('stat');
    final allResists = statName == _allResists;
    final stat = allResists ? null : _stat(node, statName);
    if (!allResists && stat == null) return null;

    return EchoNodeDef(
      id: id,
      branchId: branchId,
      name: node.str('ru'),
      text: node.str('text'),
      kind: kind,
      stat: stat,
      allResists: allResists,
      value: value,
    );
  }

  static StatKey? _stat(JsonNode node, String name) {
    for (final key in StatKey.values) {
      if (key.name == name) return key;
    }
    node.issues.add('${node.path}.stat', 'неизвестный стат «$name»');
    return null;
  }
}
