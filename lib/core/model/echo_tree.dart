import 'dart:math' as math;

import '../balance/curves.dart';
import '../content/content_pack.dart';
import '../content/echo_tree_def.dart';
import 'stat_block.dart';
import 'stat_key.dart';

/// Древо Эха (GDD §8.3): 20 узлов в трёх ветках.
///
/// Древо — единственное место, где игрок тратит Эхо, и единственная прогрессия,
/// переживающая смерть наёмника. Поэтому здесь ВЫБОР: ветка открывается по
/// порядку, и Эхо, вложенное в урон, не досталось выживанию. Раньше здесь был
/// один безымянный узел «+8 % силы», покупаемый пачкой, — то есть не выбор,
/// а счётчик.
///
/// Цена растёт от ЧИСЛА купленных узлов, а не от ветки: иначе дешёвая ветка
/// выкупалась бы целиком раньше, чем игрок увидит две другие. Экспонента —
/// потому что Эхо экспоненциально по глубине (GDD §8.2): только так число
/// новых узлов за ран остаётся константой, а не затухает к десятому рану.
class EchoTree {
  EchoTree({double? baseCost, double? costGrowth, Iterable<String>? bought})
      : _baseCost = baseCost,
        _costGrowth = costGrowth,
        _bought = {...?bought};

  final double? _baseCost;
  final double? _costGrowth;

  /// Цена берётся из контента: это баланс, а не код. Аргументы конструктора
  /// оставлены тестам, которым нужна своя шкала.
  double get baseCost => _baseCost ?? Curves.echoNodeBaseCost;
  double get costGrowth => _costGrowth ?? Curves.echoNodeCostGrowth;

  final Set<String> _bought;

  /// Купленные узлы. Порядок покупки не хранится: цена зависит от их числа,
  /// а эффект — от набора.
  Set<String> get bought => Set.unmodifiable(_bought);

  int get nodesBought => _bought.length;

  bool has(String nodeId) => _bought.contains(nodeId);

  List<EchoBranchDef> get branches => ContentPack.current.echoTree;

  double get nextNodeCost =>
      baseCost * math.pow(costGrowth, nodesBought / 4.0).toDouble();

  /// Сколько всего узлов в древе. Когда куплены все, Эхо копится впустую —
  /// и это видно.
  int get totalNodes =>
      branches.fold(0, (sum, branch) => sum + branch.nodes.length);

  bool get complete => nodesBought >= totalNodes;

  /// Доступен ли узел: предыдущий в его ветке должен быть куплен.
  bool isAvailable(String nodeId) {
    for (final branch in branches) {
      for (var i = 0; i < branch.nodes.length; i++) {
        if (branch.nodes[i].id != nodeId) continue;
        if (_bought.contains(nodeId)) return false;
        return i == 0 || _bought.contains(branch.nodes[i - 1].id);
      }
    }
    return false;
  }

  EchoNodeDef? node(String nodeId) {
    for (final branch in branches) {
      for (final node in branch.nodes) {
        if (node.id == nodeId) return node;
      }
    }
    return null;
  }

  /// Покупает узел. Возвращает остаток Эха или `null`, если купить нельзя:
  /// узел закрыт предыдущим, уже куплен или не по карману.
  int? buy(String nodeId, int available) {
    if (!isAvailable(nodeId)) return null;
    if (available < nextNodeCost) return null;

    final left = (available - nextNodeCost).floor();
    _bought.add(nodeId);
    return left;
  }

  /// Все купленные узлы одним списком.
  Iterable<EchoNodeDef> get boughtNodes sync* {
    for (final branch in branches) {
      for (final node in branch.nodes) {
        if (_bought.contains(node.id)) yield node;
      }
    }
  }

  /// Узел, который купит автоматика: следующий в ветке, где куплено меньше
  /// всего. Это ПОЛИТИКА замера и офлайн-раздачи, а не совет игроку —
  /// балансировщику нужен воспроизводимый средний игрок, а не оптимальный.
  String? nextByBalancedPolicy() {
    String? best;
    var fewest = 1 << 30;

    for (final branch in branches) {
      final bought = branch.nodes.where((n) => has(n.id)).length;
      if (bought >= branch.nodes.length) continue;

      final next = branch.nodes[bought];
      if (!isAvailable(next.id)) continue;
      if (bought < fewest) {
        fewest = bought;
        best = next.id;
      }
    }
    return best;
  }

  // --- Эффекты ---------------------------------------------------------------

  /// Долевые и плоские прибавки к собранному билду.
  ///
  /// Применяются там же, где пассивки: «+14 % к максимуму HP» — это доля от
  /// собранного HP, а не ещё один множитель всего билда.
  StatBlock applyTo(StatBlock base) {
    var maxHpPct = 0.0;
    var armorPct = 0.0;
    var hpRegen = 0.0;
    var resists = 0.0;
    var increasedDamage = 0.0;
    var critChance = 0.0;
    var critMulti = 0.0;
    var attackSpeed = 0.0;
    var cooldown = 0.0;

    for (final node in boughtNodes) {
      if (node.isRule) continue;
      if (node.allResists) {
        resists += node.value;
        continue;
      }
      switch (node.stat) {
        case StatKey.maxHpPct:
          maxHpPct += node.value;
        case StatKey.armorPct:
          armorPct += node.value;
        case StatKey.hpRegen:
          hpRegen += node.value;
        case StatKey.increasedDamage:
          increasedDamage += node.value;
        case StatKey.critChance:
          critChance += node.value;
        case StatKey.critMulti:
          critMulti += node.value;
        case StatKey.increasedAttackSpeed:
          attackSpeed += node.value;
        case StatKey.cooldownReduction:
          cooldown += node.value;
        default:
          // Валидатор контента не пропустит неизвестный стат, но узел с
          // статом, которого древо не умеет складывать, молча ничего не даст.
          // Пусть лучше он останется видимым тут одной строкой.
          break;
      }
    }

    return base +
        StatBlock(
          maxHp: base.maxHp * maxHpPct,
          armor: base.armor * armorPct,
          hpRegen: hpRegen,
          resistFire: resists,
          resistCold: resists,
          resistLightning: resists,
          resistVoid: resists,
          increasedDamage: increasedDamage,
          critChance: critChance,
          critMulti: critMulti,
          increasedAttackSpeed: attackSpeed,
          cooldownReduction: cooldown,
        );
  }

  double _rule(EchoRule rule) {
    var sum = 0.0;
    for (final node in boughtNodes) {
      if (node.rule == rule) sum += node.value;
    }
    return sum;
  }

  /// Прибавка к стартовой глубине.
  int get startDepthBonus => _rule(EchoRule.startDepth).round();

  /// Дополнительные слоты способностей.
  int get abilitySlotBonus => _rule(EchoRule.abilitySlot).round();

  /// Сколько способностей открыто сверх стартового набора.

  /// +1 слот аффикса всем предметам.
  int get affixSlotBonus => _rule(EchoRule.affixSlot).round();

  /// Раз за спуск смертельный удар оставляет 1 HP.
  bool get hasDeathThreshold => _rule(EchoRule.deathThreshold) > 0;

  /// Один осколок переживает смерть наёмника.
  bool get keepsShard => _rule(EchoRule.keepShard) > 0;
}
