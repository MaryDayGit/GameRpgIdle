import '../balance/tuning.dart';
import '../content/ability_def.dart';
import '../content/content_pack.dart';
import '../sim/abilities.dart';
import '../sim/loot.dart';
import '../sim/relics.dart';
import 'damage.dart';
import 'echo_tree.dart';
import 'equipment.dart';
import 'item.dart';
import 'passive_tree.dart';
import 'stat_block.dart';

/// Постоянный профиль игрока — то, что переживает смерть.
class HeroProfile {
  HeroProfile({
    Equipment? gear,
    List<String>? abilities,
    this.echoTotal = 0,
    this.gold = 0.0,
    this.echoTreeBonus = 0.0,
    this.tree,
    this.passives,
    this.startDepthBonus = 0,
    this.powerMultiplier = 1.0,
    this.traitStats,
  })  : gear = gear ?? ItemFactory.starterKit(),
        abilities = List<String>.from(abilities ?? starterAbilityIds()) {
    // Четыре слота — это и есть выбор билда. Пятая способность, просочившаяся
    // из сейва или из редактора лоадаута, ломает не баланс, а сам смысл
    // ограничения, и заметить это по поведению невозможно.
    // Верхняя граница — с учётом того, что «Оберег молчания» вмещает по две
    // пассивки в слот. Точное правило проверяется там, где известно
    // снаряжение; здесь стоит только потолок, за который не может выйти
    // никакой лоадаут.
    if (this.abilities.length > Tuning.abilitySlots * _maxPassivesPerSlot) {
      throw ArgumentError('Способностей ${this.abilities.length}, '
          'слотов ${Tuning.abilitySlots}');
    }
  }

  /// Снаряжение переживает смерть (GDD §8.1) — это и есть главный двигатель
  /// прогрессии между ранами, Эхо лишь добавляется сверху.
  final Equipment gear;

  /// Слоты способностей: id из контента, не больше [Tuning.abilitySlots].
  /// Активные и пассивные конкурируют за один пул — в этом и состоит выбор.
  final List<String> abilities;

  int echoTotal;
  double gold;

  /// Устаревший скалярный бонус древа: до раунда 20 древо было одним
  /// безымянным узлом «+8 % силы». Остаётся ради контрактов, посчитанных
  /// ДО перехода: их результат уже записан, и повтор обязан совпасть.
  double echoTreeBonus;

  /// Древо Эха. Даёт конкретные статы и правила, а не множитель всего билда.
  final EchoTree? tree;

  /// Дерево пассивок игрока. Общее для всех наёмников: наёмник — это ран,
  /// а дерево переживает любое их число.
  final PassiveTree? passives;

  /// Узлы «Стартовая глубина».
  int startDepthBonus;

  /// Искусственный множитель силы билда — используется балансировщиком
  /// для замера Δd (`sim_cli --wall`). В игре всегда 1.0.
  double powerMultiplier;

  /// Врождённая черта наёмника. Применяется ПОСЛЕ масштабирования, потому что
  /// черта — это долевой модификатор билда, а не ещё один множитель силы:
  /// иначе «+25 % урона Огнём» тихо превратилось бы в +25 % ко всему.
  final StatBlock Function(StatBlock)? traitStats;

  /// Агрегированный StatBlock. Пересчитывается по требованию, не каждый тик
  /// (GDD §3.2): меняется при смене снаряжения, узла древа или входе на этаж
  /// с новым модификатором.
  ///
  /// Порядок обязателен. Снаряжение складывается с базой ПЕРВЫМ, и только
  /// потом всё вместе умножается на множители силы билда. Иначе древо Эха и
  /// множитель балансировщика поднимали бы голого героя, но не найденный меч,
  /// и `--wall` мерил бы не удвоение билда, а удвоение половины билда.
  StatBlock aggregate() {
    // Пассивки, меняющие статы, входят до множителей силы билда: «+40 % брони»
    // — это доля от собранной брони, а не ещё один множитель всего билда.
    // Штраф реликтов к максимуму HP уже учтён в `gear.apply`: он обязан быть
    // виден и наёмнику, который сравнивает предметы по силе билда.
    final geared = applyPassiveAbilities(gear.apply(Tuning.heroBase), loadout);

    // Древо Эха и дерево пассивок — там же, где пассивки способностей:
    // «+14 % к максимуму HP» это доля от собранного HP, а не ещё один
    // множитель всего билда.
    final withTree = tree?.applyTo(geared) ?? geared;
    final withPassives = passives?.applyTo(withTree) ?? withTree;
    final full = withPassives.scaled(buildMultiplier);
    return traitStats?.call(full) ?? full;
  }

  /// Потолок числа способностей: два в слот с «Оберегом молчания».
  static const int _maxPassivesPerSlot = 2;

  /// Правила от надетых реликтов.
  RelicRules get relicRules => RelicRules.from(gear);

  /// Разобранный лоадаут способностей — уже с учётом реликтов.
  ///
  /// Фильтрация здесь, а не в бою: агрегат статов тоже считает пассивки, и
  /// «Оберег молчания», выключивший активки только в бою, дал бы разные билды
  /// на экране и в симуляции.
  List<AbilityDef> get loadout {
    final pack = ContentPack.current;
    final all = [
      for (final id in abilities)
        pack.ability(id) ?? (throw StateError('Нет способности «$id»')),
    ];

    final rules = relicRules;
    if (rules.passivesOnly) {
      return [for (final def in all) if (!def.isActive) def];
    }
    if (rules.singleActive) {
      var actives = 0;
      return [
        for (final def in all)
          if (!def.isActive || actives++ == 0) def,
      ];
    }

    // Слотов ровно столько, сколько даёт база: удвоение под пассивки —
    // награда «Оберега молчания», и снять оберег, оставив восемь умений,
    // нельзя. Без этого среза сборка молча переживала бы снятие реликта.
    final slots = Tuning.abilitySlots * rules.passivesPerSlot;
    return all.length <= slots ? all : all.take(slots).toList();
  }

  double get buildMultiplier => (1.0 + echoTreeBonus) * powerMultiplier;

  /// Пытается надеть найденное прямо в спуске. Возвращает то, что осталось
  /// на руках.
  ///
  /// Одевается из сундука — ровно так же, как это делает отправка в игре:
  /// только пустые слоты и без реликтов.
  ///
  /// Полное совпадение с `PlayerProfile.deploy` обязательно: это модель того
  /// же действия, и разойдясь, она начнёт мерить не ту игру, в которую играют.
  void equipFrom(List<Item> stash, {int depth = 1}) => gear.equipFrom(stash,
      base: Tuning.heroBase,
      depth: depth,
      loadout: loadout,
      onlyEmpty: true,
      skipRelics: true);

}

/// Боевое состояние героя в пределах одного рана.
class HeroState {
  HeroState(this.stats)
      : hp = stats.maxHp,
        mana = stats.maxMana;

  StatBlock stats;
  double hp;

  /// Мана — общий бюджет активных способностей.
  ///
  /// Наёмник кастует сам, поэтому решение про ману игрок принимает не в бою,
  /// а в сборке: сколько дорогих активок он унесёт вниз и чем за них платит.
  /// Пустая мана не ломает бой — герой просто бьёт оружием, — и в этом смысл:
  /// это бюджет, который можно переоценить, а не налог на всех.
  double mana;

  double attackAccumulator = 0.0;

  final MoreStack moreDamage = MoreStack();

  bool get alive => hp > 0.0;

  double get hpFraction => stats.maxHp > 0.0 ? hp / stats.maxHp : 0.0;

  double get manaFraction => stats.maxMana > 0.0 ? mana / stats.maxMana : 0.0;

  /// Хватает ли маны на каст.
  bool canPay(double cost) => cost <= 0.0 || mana >= cost;

  /// Списывает ману. Возвращает `false`, если не хватило, — и тогда ничего
  /// не списано: половина каста хуже, чем его отсутствие.
  bool pay(double cost) {
    if (cost <= 0.0) return true;
    if (mana < cost) return false;
    mana -= cost;
    return true;
  }

  void restoreMana(double amount) {
    mana += amount;
    if (mana > stats.maxMana) mana = stats.maxMana;
  }

  void refresh(StatBlock next) {
    final fraction = hpFraction;
    final manaLeft = manaFraction;
    stats = next;
    hp = stats.maxHp * fraction;
    mana = stats.maxMana * manaLeft;
  }

  void heal(double amount) {
    hp += amount;
    if (hp > stats.maxHp) hp = stats.maxHp;
  }
}
