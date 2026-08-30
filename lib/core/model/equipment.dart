import '../content/ability_def.dart';
import 'build_power.dart';
import 'gear.dart';
import 'item.dart';
import '../sim/relics.dart';
import 'relic_effect.dart';
import 'stat_block.dart';

/// Девять слотов снаряжения (GDD §4.1).
///
/// Заменяет синтетическую модель Фазы 1. Правило то же и оно важное: пустой
/// слот — это реальная слабость, а не нейтраль. Отставание снаряжения от
/// глубины должно получаться эмерджентно, из скорости дропа и числа слотов,
/// а не задаваться коэффициентом.
class Equipment {
  Equipment();

  /// Порядок слотов фиксирован: на него завязаны сейв и UI. Колец два —
  /// восемь типов предметов на девять слотов.
  static const List<GearKind> slotKinds = [
    GearKind.weapon,
    GearKind.offhand,
    GearKind.helmet,
    GearKind.armor,
    GearKind.gloves,
    GearKind.boots,
    GearKind.ring,
    GearKind.ring,
    GearKind.amulet,
  ];

  static int get slotCount => slotKinds.length;

  final List<Item?> _slots = List<Item?>.filled(slotKinds.length, null);

  List<Item?> get slots => List.unmodifiable(_slots);

  Item? at(int slot) => _slots[slot];

  int get filledSlots => _slots.where((i) => i != null).length;

  /// Сколько слотов вообще можно занять. С двуручником — на один меньше:
  /// левая рука не пустует, а физически недоступна.
  int get usableSlots => slotKinds.length - (offhandUsable ? 0 : 1);

  int get bestIlvl {
    var best = 0;
    for (final item in _slots) {
      if (item != null && item.ilvl > best) best = item.ilvl;
    }
    return best;
  }

  double get averageIlvl {
    var sum = 0;
    for (final item in _slots) {
      sum += item?.ilvl ?? 0;
    }
    return sum / slotKinds.length;
  }

  bool _conflictsWith(String relicId) {
    final def = RelicRules.definitionOf(relicId);
    if (def == null || def.exclusiveWith.isEmpty) return false;
    for (final item in _slots) {
      final worn = item?.relicId;
      if (worn != null && def.exclusiveWith.contains(worn)) return true;
    }
    return false;
  }

  bool get _hasRelic {
    for (final item in _slots) {
      if (item?.relicId != null) return true;
    }
    return false;
  }

  /// Свободна ли левая рука.
  ///
  /// Двуручник занимает оба слота — кроме случая, когда в левой руке лежит
  /// «Расколотый противовес». Реликт меняет правило, а не цифру, и это ровно
  /// то правило, которое он меняет.
  bool get offhandUsable {
    final weapon = _slots[0];
    if (weapon == null || !weapon.twoHanded) return true;
    return _slots[1]?.relicEffect == RelicEffect.twoHandedInOneHand;
  }

  /// Собирает итоговый блок статов поверх базового.
  ///
  /// Порядок обязателен: сначала складываются все плоские вклады, и только
  /// потом применяются долевые множители максимума HP и брони. Иначе «+6 % к
  /// HP» с амулета считался бы от базы, а не от собранного билда, и два
  /// одинаковых аффикса давали бы разный результат в зависимости от порядка
  /// надевания.
  StatBlock apply(StatBlock base) {
    var total = base;
    var maxHpPct = 0.0;
    var armorPct = 0.0;

    final offhandOk = offhandUsable;
    // «Парные кольца»: оба кольца считаются дважды, амулет не считается
    // вовсе. Правило слотов, а не прибавка к статам, — и потому живёт здесь,
    // где слоты и складываются.
    final rules = _hasRelic ? RelicRules.from(this) : RelicRules.none;

    for (var i = 0; i < _slots.length; i++) {
      final item = _slots[i];
      if (item == null) continue;
      if (i == 1 && !offhandOk) continue;

      if (rules.twinRings) {
        if (slotKinds[i] == GearKind.amulet) continue;
        if (slotKinds[i] == GearKind.ring) {
          total = total + item.stats + item.stats;
          maxHpPct += item.maxHpPct * 2;
          armorPct += item.armorPct * 2;
          continue;
        }
      }

      total = total + item.stats;
      maxHpPct += item.maxHpPct;
      armorPct += item.armorPct;
    }

    // Штраф реликта к максимуму HP считается ЗДЕСЬ, а не в профиле героя.
    // Иначе наёмник, сравнивающий предметы по силе билда, не видел бы, что
    // «Кожа отчаяния» забирает две трети запаса прочности, и надевал бы её
    // ради четырёх аффиксов.
    maxHpPct -= rules.maxHpPenalty;

    if (maxHpPct == 0.0 && armorPct == 0.0) return total;
    return total.withFractions(maxHpPct: maxHpPct, armorPct: armorPct);
  }

  /// Триггерные аффиксы надетого. Потолок в шесть штук держится не здесь,
  /// а в контенте: триггер разрешён только на пяти типах предметов, а это
  /// шесть слотов (колец два).
  List<String> get triggerIds => [
        for (final item in _slots)
          if (item?.triggerAffixId != null) item!.triggerAffixId!,
      ];

  /// Индексы слотов, куда подходит предмет такого типа.
  List<int> slotsFor(GearKind kind) {
    final out = <int>[];
    for (var i = 0; i < slotKinds.length; i++) {
      if (slotKinds[i] == kind) out.add(i);
    }
    return out;
  }

  /// Надевает предмет, если он усиливает сборку.
  ///
  /// Возвращает то, что осталось на руках: вытесненное, если обмен состоялся,
  /// сам предмет, если он не подошёл, и пусто, если слот был свободен.
  /// Список, а не одна вещь: двуручник вытесняет и старое оружие, и то, что
  /// лежало в левой руке. Наёмник — профессионал: он не понесёт лучший меч в
  /// мешке. Но и худший не выбросит, поэтому вытесненное уходит в рюкзак.
  ///
  /// [onlyEmpty] — не трогать надетое, заполнить только пустые слоты.
  ///
  /// Нужен ровно там, где наёмник уходит вниз: игрок собрал сборку руками, и
  /// подменять его выбор «лучшим по оценке» нельзя. Оценка не знает, зачем он
  /// надел именно это, — а он знает.
  List<Item> tryEquip(Item item,
      {required StatBlock base,
      required int depth,
      List<AbilityDef> loadout = const [],
      bool onlyEmpty = false}) {
    final candidates = slotsFor(item.kind);
    if (candidates.isEmpty) return [item];

    // Несовместимые реликты объявлены в контенте жёсткой парой: «одна активка»
    // и «ноль активок» противоречат друг другу, и порядок надевания не должен
    // решать, какое правило победит.
    if (item.relicId != null && _conflictsWith(item.relicId!)) {
      return [item];
    }

    // Левая рука занята двуручником — щит туда не влезет.
    if (item.kind == GearKind.offhand &&
        (_slots[0]?.twoHanded ?? false) &&
        item.relicEffect != RelicEffect.twoHandedInOneHand) {
      return [item];
    }

    for (final slot in candidates) {
      if (_slots[slot] == null) {
        _slots[slot] = item;
        return _freeBlockedOffhand();
      }
    }

    if (onlyEmpty) return [item];

    final current = BuildPower.of(apply(base), depth, loadout: loadout);
    var bestSlot = -1;
    var bestPower = current;

    for (final slot in candidates) {
      final previous = _slots[slot];
      _slots[slot] = item;
      final power = BuildPower.of(apply(base), depth, loadout: loadout);
      _slots[slot] = previous;

      if (power > bestPower) {
        bestPower = power;
        bestSlot = slot;
      }
    }

    if (bestSlot < 0) return [item];

    final displaced = <Item>[];
    final previous = _slots[bestSlot];
    _slots[bestSlot] = item;
    if (previous != null) displaced.add(previous);
    displaced.addAll(_freeBlockedOffhand());
    return displaced;
  }

  /// Снимает левую руку, если её занял двуручник. Держать в снаряжении вещь,
  /// которая не работает, — это молча потерянный слот.
  List<Item> _freeBlockedOffhand() {
    if (offhandUsable) return const [];
    final offhand = _slots[1];
    if (offhand == null) return const [];
    _slots[1] = null;
    return [offhand];
  }

  /// Ставит предмет в КОНКРЕТНЫЙ слот — так его кладёт игрок, а не наёмник.
  ///
  /// Возвращает то, что при этом снялось, включая левую руку, если её занял
  /// двуручник. Пустой список означает, что предмет не подошёл: чужой слот,
  /// несовместимый реликт или занятая двуручником рука.
  List<Item> equipTo(int slot, Item item) {
    if (slot < 0 || slot >= _slots.length) return [item];
    if (slotKinds[slot] != item.kind) return [item];
    if (item.relicId != null && _conflictsWith(item.relicId!)) return [item];
    if (slot == 1 &&
        (_slots[0]?.twoHanded ?? false) &&
        item.relicEffect != RelicEffect.twoHandedInOneHand) {
      return [item];
    }

    final displaced = <Item>[];
    final previous = _slots[slot];
    _slots[slot] = item;
    if (previous != null) displaced.add(previous);
    displaced.addAll(_freeBlockedOffhand());
    return displaced;
  }

  /// Снимает предмет со слота.
  Item? unequip(int slot) {
    final item = _slots[slot];
    _slots[slot] = null;
    return item;
  }

  /// Правила от надетых реликтов. Считаются по снаряжению, а не по наёмнику:
  /// реликт лежит в слоте и снимается вместе с ним.
  RelicRules get relicRules => RelicRules.from(this);

  /// Насколько предмет усилит билд. Отрицательное значение — ослабит.
  /// Это и есть «дельта к надетому» из карточки предмета.
  double gainFrom(Item item,
      {required StatBlock base,
      required int depth,
      List<AbilityDef> loadout = const []}) {
    final candidates = slotsFor(item.kind);
    if (candidates.isEmpty) return 0.0;

    final current = BuildPower.of(apply(base), depth, loadout: loadout);
    var best = current;

    for (final slot in candidates) {
      final previous = _slots[slot];
      _slots[slot] = item;
      final power = BuildPower.of(apply(base), depth, loadout: loadout);
      _slots[slot] = previous;
      if (power > best) best = power;
    }
    return best - current;
  }

  /// Собирает снаряжение из сундука. Забранное УДАЛЯЕТСЯ из [stash]:
  /// без этого два наёмника в одном спуске носили бы один и тот же меч.
  ///
  /// [onlyEmpty] оставляет надетое игроком нетронутым — см. [tryEquip].
  ///
  /// [skipRelics] не берёт реликты. Реликт меняет ПРАВИЛО боя («активок нет»,
  /// «критов нет»), и такое решение принимает игрок. Замер уже показывал,
  /// чем кончается обратное: наёмник исправно подбирал реликты, ломавшие его
  /// же сборку.
  void equipFrom(List<Item> stash,
      {required StatBlock base,
      required int depth,
      List<AbilityDef> loadout = const [],
      bool onlyEmpty = false,
      bool skipRelics = false}) {
    // Сначала лучшее по уровню: жадный проход близок к оптимуму и не требует
    // перебора 9 слотов против всего сундука на каждом шаге.
    final queue = [...stash]..sort((a, b) => b.ilvl.compareTo(a.ilvl));
    final leftovers = <Item>[];

    for (final item in queue) {
      if (skipRelics && item.isRelic) {
        leftovers.add(item);
        continue;
      }
      leftovers.addAll(tryEquip(item,
          base: base, depth: depth, loadout: loadout, onlyEmpty: onlyEmpty));
    }

    stash
      ..clear()
      ..addAll(leftovers);
  }

  /// Снимает всё. Снаряжение переживает наёмника: теряется только глубина.
  List<Item> unequipAll() {
    final out = <Item>[];
    for (var i = 0; i < _slots.length; i++) {
      final item = _slots[i];
      if (item != null) {
        out.add(item);
        _slots[i] = null;
      }
    }
    return out;
  }

  void equipAt(int slot, Item? item) => _slots[slot] = item;

  /// Снимок снаряжения. Предметы иммутабельны, поэтому копируются ссылки —
  /// копия нужна, чтобы дальнейшие находки наёмника не переписывали то, с чем
  /// он уходил вниз.
  Equipment copy() {
    final out = Equipment();
    for (var i = 0; i < _slots.length; i++) {
      out._slots[i] = _slots[i];
    }
    return out;
  }
}
