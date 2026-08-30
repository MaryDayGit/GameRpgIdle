import '../model/stat_key.dart';
import '../model/tags.dart';
import 'json_node.dart';

/// Правило, которое меняет узел дерева.
///
/// Дерево из одних процентов — это ползунок, а не выбор: любой узел в нём
/// заменяется любым другим той же величины. Правила существуют ради узлов,
/// ради которых СТРОЯТ билд, а не просто идут мимо.
///
/// Делятся на два вида, и это разделение важно:
///  * пересчёты статов (`manaToDamage`, `armorToResist`, `hpToArmor`) живут
///    в сборке билда: они превращают один стат в другой и должны быть видны
///    в силе билда на экране;
///  * боевые (`killHeal`, `lowLifeDamage`, `critVsSlowed`, `critHeal`,
///    `firstStrike`) живут в бою и
///    зависят от того, что в нём происходит.
enum PassiveRule {
  /// Часть запаса маны считается прибавкой к урону.
  manaToDamage,

  /// Часть брони считается сопротивлением всем стихиям.
  armorToResist,

  /// Часть максимума HP считается бронёй.
  hpToArmor,

  /// Убийство восстанавливает долю максимума HP.
  killHeal,

  /// Ниже половины здоровья урон умножается.
  lowLifeDamage,

  /// По замедленным крит всегда.
  critVsSlowed,

  /// Критический удар восстанавливает долю максимума HP.
  critHeal,

  /// Первый удар по новой волне усилен.
  firstStrike,

  /// Часть запаса маны считается силой чар — зеркало [manaToDamage] для
  /// второй оси.
  manaToSpellPower,

  /// Длительный урон умножается. Плата за сборку вокруг дотов: они бьют не
  /// сразу, и множитель — единственный способ сделать ожидание выгодным.
  dotMoreDamage,

  /// Удары замедляют цель. Правило, а не число: оно включает целый пласт
  /// контента, который иначе работает только с аурой Холода.
  chillOnHit,

  /// Урон Молнией задевает вторую цель.
  shockSplash,

  /// По проклятым целям урон умножается.
  curseMoreDamage,
}

/// Роль узла в дереве пассивок.
enum PassiveKind {
  /// Точка входа. Ничего не даёт, но с неё начинается любой путь.
  root,

  /// Мелкая прибавка. Таких большинство — это «дорога».
  stat,

  /// Крупный узел: ради него в ветку и идут.
  notable,

  /// Размен: заметный плюс и настоящий минус.
  keystone,
}

/// Узел дерева пассивок.
class PassiveNodeDef {
  const PassiveNodeDef({
    required this.id,
    required this.name,
    required this.text,
    required this.cluster,
    required this.kind,
    required this.x,
    required this.y,
    this.stat,
    this.value = 0.0,
    this.penaltyStat,
    this.penalty = 0.0,
    this.rule,
    this.ruleValue = 0.0,
    this.icon = 'dot',
    this.tag,
  });

  final String id;
  final String name;

  /// Текст для экрана. Ядро его не читает, но пустым он быть не должен:
  /// узел, который игрок не может прочитать, — невидимая механика.
  final String text;

  /// Луч дерева. Нужен экрану для цвета и группировки.
  final String cluster;

  final PassiveKind kind;

  /// Координаты в условных единицах. Дерево — граф, и его рисуют, а не
  /// перечисляют списком: без координат экран пришлось бы раскладывать
  /// самому, и раскладка разъехалась бы с содержанием.
  final int x;
  final int y;

  final StatKey? stat;
  final double value;

  /// Для `stat: tagDamage` — по какому тегу узел даёт прибавку.
  ///
  /// Без него узлы дерева не умели тегов вовсе: `tagDamage` попадал в ветку
  /// «ничего не делаем», и дерево из ста восьмидесяти пяти узлов не могло
  /// усилить ни одного огненного билда.
  final Tag? tag;

  /// Плата ключевого узла. Тот же список статов — минус выражается тем же
  /// языком, что и плюс, иначе размен не сравнить.
  final StatKey? penaltyStat;
  final double penalty;

  /// Правило узла и его величина. У большинства узлов правила нет — они
  /// двигают числа, и это нормально: правило, стоящее на каждом шагу,
  /// перестаёт быть событием.
  final PassiveRule? rule;
  final double ruleValue;

  /// Что нарисовано в узле. Рисует клиент кодом — по той же причине, что и
  /// силуэты мобов: лицензии, вес пакета и второй источник истины.
  final String icon;

  bool get isRoot => kind == PassiveKind.root;
}

/// Связь между узлами. Ненаправленная: дерево обходится в обе стороны.
class PassiveLink {
  const PassiveLink(this.from, this.to, {this.bridge = false});

  final String from;
  final String to;

  /// Перемычка между соседними лучами. Экран рисует её дугой: прямая через
  /// чужой сектор читается как случайное пересечение.
  final bool bridge;
}

/// Разобранное дерево.
/// Пикселей на единицу координат узла — масштаб, в котором рисуется дерево.
///
/// Живёт в ядре, хотя рисует экран: по этому числу три места принимают
/// решения — генератор раскладки (`tool/make_passive_tree.dart`), проверка
/// контента и сам экран. Пока константа была у каждого своя, разъехаться они
/// могли порознь, а слипшиеся узлы выглядели бы ошибкой раскладки.
const double treeScreenScale = 0.95;

class PassiveTreeDef {
  const PassiveTreeDef({required this.nodes, required this.links});

  final List<PassiveNodeDef> nodes;
  final List<PassiveLink> links;
}

/// Разбор дерева пассивок.
class PassiveTreeParser {
  PassiveTreeParser._();

  static const _nodeKeys = {
    'id', 'ru', 'text', 'cluster', 'kind', 'stat', 'value',
    'penaltyStat', 'penalty', 'x', 'y', 'rule', 'ruleValue', 'icon', 'tag',
  };

  static PassiveTreeDef parse(JsonNode root) {
    final nodes = <PassiveNodeDef>[];
    final ids = <String>{};

    for (final node in root.children('nodes')) {
      node.checkKeys(_nodeKeys);

      final id = node.str('id');
      if (!ids.add(id)) {
        node.issues.add('${node.path}.id', 'узел «$id» объявлен дважды');
      }

      final kind = node.enumByName('kind', PassiveKind.values);
      if (kind == null) continue;

      final rule = node.has('rule')
          ? node.enumByName('rule', PassiveRule.values)
          : null;

      // Узел без стата и без правила не даёт ничего. Такой узел нельзя
      // заметить в игре — только по тому, что очко потрачено впустую.
      final hasStat = node.has('stat');
      if (kind != PassiveKind.root && !hasStat && rule == null) {
        node.issues.add(node.path, 'узел не даёт ни стата, ни правила');
      }
      if (rule != null && node.dbl('ruleValue', or: 0.0) <= 0.0) {
        node.issues.add('${node.path}.ruleValue',
            'правило с нулевой величиной ничего не меняет');
      }

      final stat = kind == PassiveKind.root || !hasStat
          ? null
          : _stat(node, 'stat', node.str('stat'));

      // Тег и `tagDamage` существуют только вместе: узел «+% к урону с
      // тегом» без тега молча не даёт ничего, а тег при любом другом стате
      // читается как обещание, которого узел не выполняет.
      final tag = node.has('tag')
          ? node.enumByName('tag', Tag.values)
          : null;
      if (stat == StatKey.tagDamage && tag == null) {
        node.issues.add('${node.path}.tag',
            'узел на tagDamage обязан называть тег');
      }
      if (stat != StatKey.tagDamage && tag != null) {
        node.issues.add('${node.path}.tag',
            'тег осмыслен только вместе со статом tagDamage');
      }

      nodes.add(PassiveNodeDef(
        id: id,
        name: node.str('ru'),
        text: node.str('text'),
        cluster: node.str('cluster'),
        kind: kind,
        stat: stat,
        value: node.dbl('value', or: 0.0),
        penaltyStat: node.has('penaltyStat')
            ? _stat(node, 'penaltyStat', node.str('penaltyStat'))
            : null,
        penalty: node.dbl('penalty', or: 0.0),
        x: node.integer('x', or: 0),
        y: node.integer('y', or: 0),
        rule: rule,
        ruleValue: node.dbl('ruleValue', or: 0.0),
        icon: node.str('icon', or: 'dot'),
        tag: tag,
      ));
    }

    final links = <PassiveLink>[];
    for (final link in root.children('links')) {
      link.checkKeys({'from', 'to', 'bridge'});

      final from = link.str('from');
      final to = link.str('to');
      if (!ids.contains(from) || !ids.contains(to)) {
        link.issues.add(link.path, 'связь ведёт в несуществующий узел');
        continue;
      }
      links.add(PassiveLink(from, to, bridge: link.flag('bridge')));
    }

    _checkShape(root, nodes, links);
    return PassiveTreeDef(nodes: nodes, links: links);
  }

  /// Проверки формы дерева. Дерево генерируется скриптом, и именно поэтому
  /// проверять его надо здесь: ошибка в генераторе иначе доедет до игрока
  /// в виде узла, до которого нельзя дойти.
  static void _checkShape(
    JsonNode root,
    List<PassiveNodeDef> nodes,
    List<PassiveLink> links,
  ) {
    final roots = nodes.where((n) => n.isRoot).toList();
    if (roots.length != 1) {
      root.issues.add(root.path,
          'корней должно быть ровно один, а их ${roots.length}');
      return;
    }

    final neighbours = <String, Set<String>>{};
    for (final link in links) {
      (neighbours[link.from] ??= {}).add(link.to);
      (neighbours[link.to] ??= {}).add(link.from);
    }

    // Обход от корня: узел, до которого нет пути, взять нельзя никогда.
    final seen = <String>{roots.first.id};
    final queue = <String>[roots.first.id];
    while (queue.isNotEmpty) {
      for (final next in neighbours[queue.removeLast()] ?? const <String>{}) {
        if (seen.add(next)) queue.add(next);
      }
    }

    for (final node in nodes) {
      if (!seen.contains(node.id)) {
        root.issues.add('${root.path}.nodes.${node.id}',
            'до узла нет пути от корня');
      }
    }
  }

  static StatKey? _stat(JsonNode node, String field, String name) {
    for (final key in StatKey.values) {
      if (key.name == name) return key;
    }
    node.issues.add('${node.path}.$field', 'неизвестный стат «$name»');
    return null;
  }
}
