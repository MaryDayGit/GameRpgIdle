import '../balance/curves.dart';
import '../content/content_pack.dart';
import '../content/passive_tree_def.dart';
import 'stat_block.dart';
import 'stat_key.dart';
import 'tags.dart';

/// Дерево пассивок — общая прокачка ИГРОКА, а не наёмника.
///
/// Три отличия от древа Эха, и все три намеренные (GDD §6.1: валюты не
/// дублируют друг друга):
///
///  * очки даёт достигнутая глубина, а не потраченная валюта — прокачка
///    подтверждает, что игрок там был;
///  * дерево двигает ЧИСЛА и разменивает их друг на друга, а древо Эха
///    меняет ПРАВИЛА;
///  * действует на всех наёмников сразу: наёмник — это ран, а дерево —
///    то, что переживает любое число ранов.
///
/// Узел берётся, только если рядом уже взят другой: дорога до дальнего
/// кластера стоит очков, и в этом весь выбор.
class PassiveTree {
  PassiveTree({Iterable<String>? allocated}) : _allocated = {...?allocated};

  final Set<String> _allocated;

  Set<String> get allocated => Set.unmodifiable(_allocated);
  int get spent => _allocated.length;

  PassiveTreeDef get def => ContentPack.current.passiveTree;

  List<PassiveNodeDef> get nodes => def.nodes;

  bool has(String nodeId) => _allocated.contains(nodeId);

  PassiveNodeDef? node(String nodeId) {
    for (final node in def.nodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  String? get rootId {
    for (final node in def.nodes) {
      if (node.isRoot) return node.id;
    }
    return null;
  }

  /// Соседи узла. Пересобирается на каждый запрос: дерево читается редко,
  /// а лишний кэш — это лишний источник расхождения с контентом.
  Set<String> neighbours(String nodeId) {
    final out = <String>{};
    for (final link in def.links) {
      if (link.from == nodeId) out.add(link.to);
      if (link.to == nodeId) out.add(link.from);
    }
    return out;
  }

  /// Можно ли взять узел: он не взят, до него есть дорога от уже взятого
  /// (или это сосед корня) и хватает очков.
  bool canAllocate(String nodeId, int availablePoints) {
    if (_allocated.contains(nodeId)) return false;
    if (availablePoints <= spent) return false;

    final target = node(nodeId);
    if (target == null || target.isRoot) return false;

    final root = rootId;
    for (final neighbour in neighbours(nodeId)) {
      if (neighbour == root || _allocated.contains(neighbour)) return true;
    }
    return false;
  }

  bool allocate(String nodeId, int availablePoints) {
    if (!canAllocate(nodeId, availablePoints)) return false;
    _allocated.add(nodeId);
    return true;
  }

  /// Можно ли снять узел: только если остальные взятые останутся связаны
  /// с корнем. Иначе снятие середины дороги оставило бы висеть её конец —
  /// узлы, до которых игрок больше не может дойти, но они у него есть.
  bool canRefund(String nodeId) {
    if (!_allocated.contains(nodeId)) return false;

    final rest = {..._allocated}..remove(nodeId);
    if (rest.isEmpty) return true;

    final root = rootId;
    if (root == null) return false;

    final seen = <String>{};
    final queue = <String>[root];
    while (queue.isNotEmpty) {
      for (final next in neighbours(queue.removeLast())) {
        if (!rest.contains(next)) continue;
        if (seen.add(next)) queue.add(next);
      }
    }
    return seen.length == rest.length;
  }

  bool refund(String nodeId) {
    if (!canRefund(nodeId)) return false;
    _allocated.remove(nodeId);
    return true;
  }

  /// Снимает всё. Нужен затем же, зачем в любой игре с деревом: ошибка в
  /// сборке не должна стоить игроку аккаунта.
  void reset() => _allocated.clear();

  // --- Эффекты ---------------------------------------------------------------

  /// Складывает прибавки взятых узлов в собранный блок статов.
  ///
  /// Долевые статы считаются от УЖЕ собранного билда — там же, где пассивки
  /// способностей и древо Эха: «+14 % к максимуму HP» это доля от того, что
  /// игрок собрал, а не ещё один множитель всего.
  StatBlock applyTo(StatBlock base) {
    final sums = <StatKey, double>{};

    // Теговые прибавки собираются отдельной картой: у них два ключа — стат и
    // тег, — и в общую сумму по стату они сложились бы в одну кучу, где
    // «+10 % Огнём» и «+10 % Снарядами» стали бы неразличимы.
    final tags = <Tag, double>{};

    void add(StatKey? key, double value) {
      if (key == null || value == 0.0) return;
      sums[key] = (sums[key] ?? 0.0) + value;
    }

    for (final node in def.nodes) {
      if (!_allocated.contains(node.id)) continue;
      if (node.stat == StatKey.tagDamage && node.tag != null) {
        tags[node.tag!] = (tags[node.tag!] ?? 0.0) + node.value;
      } else {
        add(node.stat, node.value);
      }
      // Плата ключевого узла считается всегда — и у теговых тоже: размен без
      // минуса это не размен.
      add(node.penaltyStat, -node.penalty);
    }

    var out = tags.isEmpty ? base : base + StatBlock(tagDamage: tags);
    for (final entry in sums.entries) {
      out = _apply(out, base, entry.key, entry.value);
    }
    // Пересчёты — последними и от исходного билда: узел «часть брони
    // становится сопротивлением» не должен считать броню, которую сам же
    // и добавил, иначе величина зависела бы от порядка обхода.
    return _conversions(out, base);
  }

  /// Одна прибавка. Доли считаются от [base], а не от накопленного [current]:
  /// иначе порядок узлов в списке менял бы результат, а он не должен.
  StatBlock _apply(
      StatBlock current, StatBlock base, StatKey key, double value) {
    return switch (key) {
      StatKey.maxHpPct => current + StatBlock(maxHp: base.maxHp * value),
      StatKey.armorPct => current + StatBlock(armor: base.armor * value),
      StatKey.maxHp => current + StatBlock(maxHp: value),
      StatKey.armor => current + StatBlock(armor: value),
      StatKey.hpRegen => current + StatBlock(hpRegen: value),
      StatKey.maxMana => current + StatBlock(maxMana: value),
      StatKey.manaRegen => current + StatBlock(manaRegen: value),
      StatKey.resistFire => current + StatBlock(resistFire: value),
      StatKey.resistCold => current + StatBlock(resistCold: value),
      StatKey.resistLightning => current + StatBlock(resistLightning: value),
      StatKey.resistVoid => current + StatBlock(resistVoid: value),
      StatKey.attackDamage => current + StatBlock(attackDamage: value),
      StatKey.spellPower => current + StatBlock(spellPower: value),
      StatKey.increasedDamage => current + StatBlock(increasedDamage: value),
      StatKey.increasedAttackSpeed =>
        current + StatBlock(increasedAttackSpeed: value),
      StatKey.critChance => current + StatBlock(critChance: value),
      StatKey.critMulti => current + StatBlock(critMulti: value),
      StatKey.cooldownReduction =>
        current + StatBlock(cooldownReduction: value),
      StatKey.leech => current + StatBlock(leech: value),
      StatKey.lootQuality => current + StatBlock(lootQuality: value),
      StatKey.lootQuantity => current + StatBlock(lootQuantity: value),
      StatKey.goldFind => current + StatBlock(goldFind: value),
      // Собирается отдельной картой в [applyTo] — сюда не доходит.
      StatKey.tagDamage => current,
    };
  }

  /// Суммарная величина правила по всем взятым узлам.
  ///
  /// Сумма, а не «первый найденный»: два узла с одним правилом должны
  /// складываться, иначе второй молча ничего не даёт.
  double ruleValue(PassiveRule rule) {
    var sum = 0.0;
    for (final id in _allocated) {
      final node = this.node(id);
      if (node?.rule == rule) sum += node!.ruleValue;
    }
    return sum;
  }

  bool has_(PassiveRule rule) => ruleValue(rule) > 0.0;

  /// Пересчёты статов: узлы, превращающие один стат в другой.
  ///
  /// Считаются от [base] — от собранного билда ДО прибавок дерева. Иначе
  /// «часть брони становится сопротивлением» зависела бы от того, в каком
  /// порядке игрок брал узлы.
  StatBlock _conversions(StatBlock current, StatBlock base) {
    var out = current;

    final manaToDamage = ruleValue(PassiveRule.manaToDamage);
    if (manaToDamage > 0.0) {
      // «+1 % урона за каждые 20 маны» — правило записано как доля на одну
      // единицу маны, чтобы величина узла читалась одним числом.
      out = out + StatBlock(increasedDamage: base.maxMana * manaToDamage);
    }

    final armorToResist = ruleValue(PassiveRule.armorToResist);
    if (armorToResist > 0.0) {
      final resist = base.armor * armorToResist;
      out = out +
          StatBlock(
            resistFire: resist,
            resistCold: resist,
            resistLightning: resist,
            resistVoid: resist,
          );
    }

    final manaToSpellPower = ruleValue(PassiveRule.manaToSpellPower);
    if (manaToSpellPower > 0.0) {
      out = out + StatBlock(spellPower: base.maxMana * manaToSpellPower);
    }

    final hpToArmor = ruleValue(PassiveRule.hpToArmor);
    if (hpToArmor > 0.0) {
      out = out + StatBlock(armor: base.maxHp * hpToArmor);
    }

    return out;
  }

  /// Сколько очков даёт достигнутая глубина.
  static int pointsFor(int maxDepthEver) => Curves.passivePoints(maxDepthEver);
}
