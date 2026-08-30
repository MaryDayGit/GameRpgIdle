import '../balance/tuning.dart';
import '../content/ability_def.dart';
import '../content/content_pack.dart';
import '../model/enemy.dart';
import '../model/hero.dart';
import '../model/stat_block.dart';
import '../model/stat_key.dart';
import '../model/tags.dart';
import 'combat_feed.dart';
import 'events.dart';
import 'rng.dart';
import 'relics.dart';
import 'triggers.dart';

/// То, что способностям и триггерам нужно от боя.
///
/// Интерфейс, а не прямая ссылка на бой: и то и другое обязано оставаться
/// проверяемым в одиночку. Тест на «Разлом бьёт по всей волне» не должен
/// поднимать спуск целиком.
abstract class CombatContext {
  HeroState get hero;
  List<EnemyInstance> get enemies;
  Rng get rng;
  EventBus get bus;
  int get depth;

  /// Канал наблюдения — только на запись. Симуляция в него не заглядывает:
  /// бой не имеет права идти иначе оттого, что на него смотрят
  /// (`combat_feed.dart`).
  CombatFeed? get feed;

  /// Наносит урон от способности. Возвращает нанесённое.
  double dealDamage(
    EnemyInstance target, {
    required double base,
    required DamageType type,
    required List<Tag> tags,
    bool canCrit,
  });

  /// Наносит уже посчитанный урон, минуя формулу.
  ///
  /// Нужен триггерам вида «этот удар бьёт вдвое»: они срабатывают ПОСЛЕ того,
  /// как урон посчитан и смягчён, и прогонять его через броню второй раз
  /// значило бы удвоить митигацию, а не урон.
  ///
  /// [type] — чем считать этот урон в разбивке по типам. Формула его уже не
  /// применяет, но задание «нанесите половину урона Молнией» обязано его
  /// увидеть.
  void dealRawDamage(EnemyInstance target, double amount,
      {DamageType type});
}

/// Активная способность в бою: определение плюс её кулдаун.
class _ActiveState {
  _ActiveState(this.def);

  final AbilityDef def;
  double cooldownRemaining = 0.0;
}

/// Установленный тотем: определение, остаток жизни и накопитель ударов.
///
/// Живёт на уровне рана, как и кулдауны: тотем, поставленный в конце волны,
/// не должен исчезать оттого, что волна кончилась. Он и задуман как источник
/// урона, который работает, пока герой занят другим.
class _Totem {
  _Totem(this.def, this.remaining);

  final AbilityDef def;
  double remaining;
  double accumulator = 0.0;
}

/// Временный бафф от способности.
class _Buff {
  _Buff(this.stat, this.value, this.remaining, [this.sourceId = '']);

  final StatKey stat;
  final double value;
  double remaining;

  /// Кто повесил. Нужен для потолка стаков — он считается по источнику.
  final String sourceId;
}

/// Рантайм способностей: 4 слота, активные кастуются по приоритету слота.
///
/// Живёт на уровне РАНА, а не волны: кулдауны и баффы не должны обнуляться
/// между волнами, иначе способность с перезарядкой 14 с была бы готова к
/// началу каждой волны и её кулдаун ничего бы не значил.
///
/// Пассивные способности делятся на два вида, и это разделение важно:
///  * меняющие статы (`statTradeoff`) сворачиваются в [StatBlock] героя один
///    раз при сборке билда — их место в агрегате, а не в тике;
///  * меняющие правила боя (повтор атаки, аура, взрыв трупов) живут здесь.
class AbilityRuntime {
  AbilityRuntime(List<AbilityDef> loadout,
      {CombatModifiers? modifiers, this.rules = RelicRules.none})
      : _loadout = List.unmodifiable(loadout),
        mods = modifiers ?? CombatModifiers() {
    for (final def in _loadout) {
      if (def.isActive) _actives.add(_ActiveState(def));
    }
  }

  /// Рантайм по списку id из профиля. Неизвестные id молча не пропускаются:
  /// способность, которой нет в контенте, — это сломанный сейв, а не пустой
  /// слот.
  factory AbilityRuntime.fromIds(List<String> ids,
      {CombatModifiers? modifiers, RelicRules rules = RelicRules.none}) {
    final pack = ContentPack.current;
    return AbilityRuntime(
      [
        for (final id in ids)
          pack.ability(id) ?? (throw StateError('Нет способности «$id»')),
      ],
      modifiers: modifiers,
      rules: rules,
    );
  }

  static final AbilityRuntime empty = AbilityRuntime(const []);

  /// Поправки от триггеров. Общий объект с [TriggerRuntime].
  final CombatModifiers mods;

  /// Правила от реликтов. Меняются вместе со снаряжением.
  RelicRules rules;

  final List<AbilityDef> _loadout;
  final List<_ActiveState> _actives = [];
  final List<_Buff> _buffs = [];
  final List<_Totem> _totems = [];

  List<AbilityDef> get loadout => _loadout;

  // --- Пассивные правила -----------------------------------------------------

  /// Аура замедления: доля, на которую замедлены атакующие.
  /// Замедление от аур, усиленное тегом «Аура».
  ///
  /// Тег множит не урон (ауры его не наносят), а ВЕЛИЧИНУ ауры. Множитель
  /// берётся из статов героя: он приходит с вещей и из дерева, и на момент
  /// сборки рантайма его ещё нет.
  double auraSlowFor(StatBlock stats) =>
      _paramSum(AbilityKind.auraSlow, 'slow') *
      (1.0 + (stats.tagDamage[Tag.aura] ?? 0.0));

  /// Шанс повторить автоатаку.
  double get repeatAttackChance =>
      _paramSum(AbilityKind.repeatAttack, 'chance');

  /// Шанс повторить каст чар — зеркало [repeatAttackChance] для второй оси.
  double get repeatSpellChance => _paramSum(AbilityKind.repeatSpell, 'chance');

  /// Пропитка оружия: чем бьёт автоатака.
  ///
  /// `null` — ничем не пропитано, автоатака физическая. Берётся ПЕРВАЯ
  /// пропитка в сборке, а не сумма: две стихии на одном клинке — это не
  /// «полтора урона», а вопрос без ответа, каким сопротивлением его резать.
  AbilityDef? get _infusion {
    for (final def in _loadout) {
      if (def.kind == AbilityKind.infusion) return def;
    }
    return null;
  }

  /// Тип урона автоатаки с учётом пропитки.
  DamageType get autoAttackType =>
      _infusion?.damageType ?? DamageType.physical;

  /// Теги автоатаки с учётом пропитки.
  ///
  /// «Атака» и «Удар» остаются всегда — пропитанный клинок не перестаёт быть
  /// оружием. Меняется стихия, и вместе с ней — какие аффиксы её усиливают.
  List<Tag> get autoAttackTags {
    final infusion = _infusion;
    if (infusion == null) return const [Tag.attack, Tag.strike, Tag.physical];
    return [Tag.attack, Tag.strike, infusion.damageType.tag];
  }

  /// Долевая прибавка к урону автоатаки от пропитки.
  double get autoAttackMore => _infusion?.params.dbl('moreDamage') ?? 0.0;

  /// Множитель вампиризма с учётом порога HP.
  double leechMultiplier(HeroState hero) {
    var multiplier = rules.leechMultiplier;
    for (final def in _loadout) {
      if (def.kind != AbilityKind.conditionalLeech) continue;
      // «Кожа отчаяния» держит порог включённым всегда — в этом её смысл.
      if (rules.permanentLowLife ||
          hero.hpFraction <= def.params.dbl('threshold')) {
        multiplier *= def.params.dbl('leechMultiplier', 1.0);
      }
    }
    return multiplier;
  }

  double _paramSum(AbilityKind kind, String key) {
    var sum = 0.0;
    for (final def in _loadout) {
      if (def.kind == kind) sum += def.params.dbl(key);
    }
    return sum;
  }

  /// Статы от пассивок, сворачиваемые в агрегат билда.
  ///
  /// Возвращает долевые поправки, а не готовый блок: `armorPct` умножает
  /// собранную броню, а не добавляется к ней.
  static ({double armorPct, double attackSpeedPct}) passiveFractions(
      List<AbilityDef> loadout) {
    var armor = 0.0;
    var speed = 0.0;
    for (final def in loadout) {
      if (def.kind != AbilityKind.statTradeoff) continue;
      armor += def.params.dbl('armorPct');
      speed += def.params.dbl('attackSpeedPct');
    }
    return (armorPct: armor, attackSpeedPct: speed);
  }

  // --- Баффы -----------------------------------------------------------------

  /// Долевая прибавка к скорости атаки от активных баффов.
  double get buffAttackSpeed => _buffSum(StatKey.increasedAttackSpeed);

  /// Долевая прибавка к урону от активных баффов.
  double get buffIncreasedDamage => _buffSum(StatKey.increasedDamage);

  double _buffSum(StatKey stat) {
    var sum = 0.0;
    for (final buff in _buffs) {
      if (buff.stat == stat) sum += buff.value;
    }
    return sum;
  }

  // --- Тик -------------------------------------------------------------------

  /// Шаг рантайма: стачивает кулдауны и баффы, кастует готовые активки.
  void tick(double dt, CombatContext ctx) {
    for (var i = _buffs.length - 1; i >= 0; i--) {
      _buffs[i].remaining -= dt;
      if (_buffs[i].remaining <= 0.0) _buffs.removeAt(i);
    }

    _tickTotems(dt, ctx);

    final cooldownReduction = ctx.hero.stats.cooldownReduction;

    for (final active in _actives) {
      if (active.cooldownRemaining > 0.0) {
        active.cooldownRemaining -= dt;
        continue;
      }

      // Мана списывается ДО каста и только целиком: половина каста хуже, чем
      // его отсутствие. Не хватило — способность просто ждёт, кулдаун не
      // трогается, и герой продолжает бить оружием. Пустая мана не ломает
      // бой: это бюджет, который можно переоценить, а не налог на всех.
      // «Бесконечная кадильница» отменяет цену целиком, «Печать скорости»
      // её удваивает. Цена считается один раз и здесь: платить и проверять
      // надо одним и тем же числом.
      final cost = rules.freeCasts
          ? 0.0
          : active.def.manaCost * rules.manaCostMultiplier;
      if (!ctx.hero.canPay(cost)) continue;
      if (!_cast(active.def, ctx)) continue;
      ctx.hero.pay(cost);

      // «Двойной удар»: следующая способность бьёт дважды. Флаг снимается ДО
      // повторного каста — иначе он переоткрывал бы сам себя каждый раз.
      if (mods.doubleNextCast) {
        mods.doubleNextCast = false;
        _cast(active.def, ctx);
      }

      // Повтор чар. Бесплатный, как и повтор автоатаки: платить дважды за
      // одно нажатие было бы не «эхо», а вторая способность в том же слоте.
      // Ровно один повтор — рекурсии здесь взяться неоткуда.
      final echo = repeatSpellChance;
      if (echo > 0.0 && active.def.isSpell && ctx.rng.chance(echo)) {
        _cast(active.def, ctx);
      }

      // Сокращение перезарядки — долевое и с полом: 100 % кулдауна означало бы
      // каст каждый тик, то есть деление на ноль в дизайне.
      // Множитель реликтов идёт поверх перезарядки от статов: «кадильница»
      // делает касты бесплатными и вдвое более редкими, «печать» — наоборот.
      var factor = ((1.0 - cooldownReduction) * rules.cooldownMultiplier)
          .clamp(0.1, double.infinity);
      if (rules.singleActive) {
        factor *= 1.0 - rules.singleActiveCooldownReduction;
      }
      active.cooldownRemaining = active.def.cooldown * factor;
    }
  }

  /// Тотемы бьют сами. Урон идёт через ту же точку, что и всё остальное:
  /// проклятие, вампиризм и учёт убийств не должны знать, кто ударил.
  void _tickTotems(double dt, CombatContext ctx) {
    if (_totems.isEmpty) return;

    for (var i = _totems.length - 1; i >= 0; i--) {
      final totem = _totems[i];
      totem.remaining -= dt;

      final interval = totem.def.params.dbl('interval', 1.0);
      totem.accumulator += dt;
      while (totem.accumulator >= interval) {
        totem.accumulator -= interval;
        _totemStrike(totem.def, ctx);
      }

      if (totem.remaining <= 0.0) _totems.removeAt(i);
    }
  }

  void _totemStrike(AbilityDef def, CombatContext ctx) {
    final targets = def.params.integer('targets', 1);
    final base = _sourceBase(ctx, def);

    var hit = 0;
    for (final enemy in ctx.enemies) {
      if (!enemy.alive) continue;
      if (hit >= targets) break;
      ctx.dealDamage(enemy, base: base, type: def.damageType, tags: def.tags);
      hit++;
    }
  }

  /// Добавляет бафф от триггера со стаками.
  ///
  /// Стаки считаются по источнику, а не по стату: два разных триггера,
  /// поднимающих скорость атаки, не должны делить один потолок.
  void addStackingBuff({
    required String sourceId,
    required StatKey stat,
    required double value,
    required double duration,
    required int maxStacks,
  }) {
    var stacks = 0;
    for (final buff in _buffs) {
      if (buff.sourceId == sourceId) stacks++;
    }
    if (stacks >= maxStacks) {
      // Потолок набран — обновляем самый старый стак вместо добавления.
      for (final buff in _buffs) {
        if (buff.sourceId == sourceId) {
          buff.remaining = duration;
          return;
        }
      }
      return;
    }
    _buffs.add(_Buff(stat, value, duration, sourceId));
  }

  /// Сбрасывает кулдаун случайной активки — это триггер «Разряд».
  void resetRandomCooldown(Rng rng) {
    if (_actives.isEmpty) return;
    _actives[rng.nextInt(_actives.length)].cooldownRemaining = 0.0;
  }

  // --- Реакции на события боя ------------------------------------------------

  /// Крит наложил дот («Пепелище»).
  void onCrit(EnemyInstance target, CombatContext ctx) {
    for (final def in _loadout) {
      if (def.kind != AbilityKind.critApplyDot) continue;
      target.applyDot(
        _dotDps(ctx, def.params.dbl('dpsFraction'), spell: def.isSpell),
        def.params.dbl('duration'),
        def.damageType,
        maxStacks: rules.burnCanCrit ? rules.burnMaxStacks : 1,
        tags: def.tags,
      );
    }
  }

  /// Убитый взорвался («Печать бездны»): урон по остальным живым.
  ///
  /// Только по проклятым — правило способности. Взрыв не критует и не
  /// порождает событий: цепочка «взрыв убил -> взрыв убил -> …» это ровно тот
  /// каскад, от которого стоят предохранители шины.
  void onKill(EnemyInstance corpse, CombatContext ctx) {
    for (final def in _loadout) {
      if (def.kind != AbilityKind.corpseExplosion) continue;
      if (!corpse.cursed) continue;

      final damage = corpse.maxHp * def.params.dbl('fractionOfMaxHp');
      for (final enemy in ctx.enemies) {
        if (!enemy.alive || identical(enemy, corpse)) continue;
        ctx.dealDamage(
          enemy,
          base: damage,
          type: def.damageType,
          tags: def.tags,
          canCrit: false,
        );
      }
    }
  }

  // --- Касты -----------------------------------------------------------------

  bool _cast(AbilityDef def, CombatContext ctx) {
    switch (def.kind) {
      case AbilityKind.directDamage:
        return _castDirect(def, ctx);
      case AbilityKind.curse:
        return _castCurse(def, ctx);
      case AbilityKind.dot:
        return _castDot(def, ctx);
      case AbilityKind.buff:
        return _castBuff(def, ctx);
      case AbilityKind.execute:
        return _castExecute(def, ctx);
      case AbilityKind.chainDamage:
        return _castChain(def, ctx);
      case AbilityKind.heal:
        return _castHeal(def, ctx);
      case AbilityKind.summonTotem:
        return _castTotem(def, ctx);
      case AbilityKind.auraSlow:
      case AbilityKind.auraStat:
      case AbilityKind.conditionalLeech:
      case AbilityKind.critApplyDot:
      case AbilityKind.statTradeoff:
      case AbilityKind.repeatAttack:
      case AbilityKind.corpseExplosion:
      case AbilityKind.thorns:
      case AbilityKind.lowLifeGuard:
      case AbilityKind.infusion:
      case AbilityKind.repeatSpell:
        // Пассивки и ауры не кастуются: они работают всегда.
        return false;
    }
  }

  bool _castDirect(AbilityDef def, CombatContext ctx) {
    // «Венец одержимого» оставляет одну активку, зато она бьёт по всей волне.
    final targets =
        rules.singleActive ? ctx.enemies.length : def.params.integer('targets', 1);
    final bonusVsSlowed = def.params.dbl('bonusVsSlowed');
    final weapon = _sourceBase(ctx, def);

    var hit = 0;
    for (final enemy in ctx.enemies) {
      if (!enemy.alive) continue;
      if (hit >= targets) break;
      final base = enemy.slowed ? weapon * (1.0 + bonusVsSlowed) : weapon;
      ctx.dealDamage(enemy, base: base, type: def.damageType, tags: def.tags);
      hit++;
    }
    if (hit > 0) {
      ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    }
    return hit > 0;
  }

  /// Ставит тотем. Повторный каст обновляет уже стоящий, а не добавляет
  /// второй: иначе способность с перезарядкой короче своей длительности
  /// копила бы тотемы и превращалась в единственный источник урона.
  bool _castTotem(AbilityDef def, CombatContext ctx) {
    if (_firstAlive(ctx) == null) return false;

    for (final totem in _totems) {
      if (totem.def.id != def.id) continue;
      totem.remaining = def.params.dbl('duration');
      ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
      ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
      return true;
    }

    _totems.add(_Totem(def, def.params.dbl('duration')));
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  /// Добивание: по раненой цели урон умножается.
  ///
  /// Цель выбирается самая раненая, а не первая живая: способность про
  /// добивание, и бить ею полного здоровья моба — значит не пользоваться ею
  /// вовсе.
  bool _castExecute(AbilityDef def, CombatContext ctx) {
    EnemyInstance? target;
    var lowest = double.infinity;
    for (final enemy in ctx.enemies) {
      if (!enemy.alive) continue;
      final fraction = enemy.maxHp > 0 ? enemy.hp / enemy.maxHp : 1.0;
      if (fraction < lowest) {
        lowest = fraction;
        target = enemy;
      }
    }
    if (target == null) return false;

    final weapon = _sourceBase(ctx, def);
    final base = lowest <= def.params.dbl('threshold')
        ? weapon * (1.0 + def.params.dbl('bonusBelow'))
        : weapon;

    ctx.dealDamage(target, base: base, type: def.damageType, tags: def.tags);
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  /// Цепь: каждая следующая цель получает меньше.
  bool _castChain(AbilityDef def, CombatContext ctx) {
    final targets = def.params.integer('targets', 3);
    final falloff = def.params.dbl('falloff');
    var damage = _sourceBase(ctx, def);

    var hit = 0;
    for (final enemy in ctx.enemies) {
      if (!enemy.alive) continue;
      if (hit >= targets) break;

      ctx.dealDamage(enemy, base: damage, type: def.damageType, tags: def.tags);
      damage *= 1.0 - falloff;
      hit++;
    }
    if (hit == 0) return false;

    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  /// Лечение. Кастуется, только если есть что лечить: иначе способность
  /// сожгла бы ману и кулдаун на полном здоровье.
  bool _castHeal(AbilityDef def, CombatContext ctx) {
    final hero = ctx.hero;
    if (hero.hpFraction > 0.95) return false;

    hero.heal(hero.stats.maxHp * def.params.dbl('fractionOfMaxHp'));
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  /// Доля полученного урона, возвращаемая ударившему («Шипы»).
  double get thornsFraction => _paramSum(AbilityKind.thorns, 'fractionReturned');

  /// Во сколько раз срезан получаемый урон на низком здоровье.
  ///
  /// Считается от состояния героя, поэтому живёт здесь, а не в агрегате:
  /// это правило боя, а не число билда.
  double damageTakenMultiplier(HeroState hero) {
    var multiplier = 1.0;
    for (final def in _loadout) {
      if (def.kind != AbilityKind.lowLifeGuard) continue;
      if (rules.permanentLowLife ||
          hero.hpFraction <= def.params.dbl('threshold')) {
        multiplier *= 1.0 - def.params.dbl('lessDamageTaken');
      }
    }
    return multiplier;
  }

  bool _castCurse(AbilityDef def, CombatContext ctx) {
    final target = _firstAlive(ctx);
    if (target == null) return false;

    // Клеймо ставится ДО удара, а не после. Иначе убивающий каст проклинает
    // уже труп: `onKill` приходит из нанесения урона, и всё, что завязано на
    // «убийство проклятого», промахивается мимо собственного условия. Плюс
    // проклятие успевает поднять урон того самого удара, который его наложил.
    final increase = def.params.dbl('damageTakenIncrease');
    // «Печать тысячи глаз»: проклятие не спадает и переходит на новые волны.
    // Длительность до конца этажа выражается заведомо большим числом — этаж
    // короче любого разумного значения, а отдельного «бесконечно» в модели нет.
    final duration =
        rules.eternalCurse ? 1e9 : def.params.dbl('duration');
    if (rules.eternalCurse) mods.carriedCurse = increase;
    target.applyCurse(increase, duration);
    ctx.dealDamage(
      target,
      base: _sourceBase(ctx, def),
      type: def.damageType,
      tags: def.tags,
    );
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  bool _castDot(AbilityDef def, CombatContext ctx) {
    final target = _firstAlive(ctx);
    if (target == null) return false;

    target.applyDot(
      _dotDps(ctx, def.params.dbl('dpsFraction'), spell: def.isSpell),
      def.params.dbl('duration'),
      def.damageType,
      tags: def.tags,
    );
    ctx.dealDamage(
      target,
      base: _sourceBase(ctx, def),
      type: def.damageType,
      tags: def.tags,
    );
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  bool _castBuff(AbilityDef def, CombatContext ctx) {
    final name = def.params.str('stat');
    final stat = StatKey.values.where((s) => s.name == name);
    if (stat.isEmpty) return false;

    // «Резонанс тотемов» усиливает только тотемные баффы — тег решает, а не
    // тип способности. Ровно ради этого и существует система тегов.
    final totem = def.tags.contains(Tag.totem);
    final duration = def.params.dbl('duration') *
        (1.0 + (totem ? mods.totemDurationBonus : 0.0));
    final value = def.params.dbl('value') *
        (1.0 + (totem ? mods.totemValueBonus : 0.0));

    _buffs.add(_Buff(stat.first, value, duration, def.id));
    ctx.bus.emit(EventContext(GameEventType.onAbilityCast, source: def));
    ctx.feed?.add(CombatBeat(BeatKind.heroCast, id: def.id));
    return true;
  }

  /// Урон дота в секунду. Считается от урона героя в секунду, а не от
  /// абсолютного числа: иначе дот устаревал бы через десяток этажей.
  ///
  /// [spell] — считать по силе чар, а не по урону оружия. Триггер, вешающий
  /// горение, спрашивает это у способности, которая его повесила.
  double dotDpsFor(CombatContext ctx, double fraction, {bool spell = false}) =>
      _dotDps(ctx, fraction, spell: spell);

  /// Долевые прибавки к урону здесь НЕ применяются.
  ///
  /// Их применяет `_applyDamage` на каждом тике дота — как и всему
  /// остальному урону. Пока они стояли в обоих местах, «+% к урону»
  /// умножался на себя: дот от сборки с +150 % бил в 6.25 раза сильнее
  /// базового вместо 2.5.
  double _dotDps(CombatContext ctx, double fraction, {required bool spell}) {
    final stats = ctx.hero.stats;
    // Атака бьёт оружием и потому считает скорость атаки. Чары от замаха не
    // зависят: иначе быстрый кинжал усиливал бы горение от посоха, и «+% к
    // скорости атаки» стал бы обязательным аффиксом любой сборки.
    final perSecond = spell
        ? stats.spellPower * Tuning.spellReferenceRate
        : stats.attackDamage * stats.effectiveAttackSpeed;
    return perSecond * fraction;
  }

  /// Основа урона способности: сила чар или урон оружия, помноженная на
  /// множитель из контента.
  ///
  /// Единственная точка, где выбирается ось. Пока их было две — обе от урона
  /// оружия, — снаряжение невозможно было подобрать под способности: любая
  /// вещь одинаково годилась любой сборке, и живой прогон назвал это «выбор
  /// без выбора».
  static double _sourceBase(CombatContext ctx, AbilityDef def) {
    final stats = ctx.hero.stats;
    final source = def.isSpell ? stats.spellPower : stats.attackDamage;
    return source * def.params.dbl('weaponMultiplier');
  }

  static EnemyInstance? _firstAlive(CombatContext ctx) {
    for (final enemy in ctx.enemies) {
      if (enemy.alive) return enemy;
    }
    return null;
  }
}

/// Какую долю запаса маны держат занятой ауры лоадаута.
///
/// Считается по лоадауту, а не по слотам: реликт, выключающий активки,
/// оставляет ауры на месте, и резерв обязан считаться от того, что реально
/// работает в бою.
double auraReservation(List<AbilityDef> loadout) {
  var sum = 0.0;
  for (final def in loadout) {
    if (def.isAura) sum += def.manaReserve;
  }
  // Полный резерв означал бы ноль доступной маны — то есть выключенные
  // активки. Оставляем щель: способности должны хотя бы иногда срабатывать.
  return sum > 0.9 ? 0.9 : sum;
}

/// Свёртка пассивных статовых способностей в блок героя.
///
/// Отдельной функцией, а не методом рантайма: агрегат билда собирается вне
/// боя (`HeroProfile.aggregate`), и тащить туда боевой объект незачем.
StatBlock applyPassiveAbilities(StatBlock stats, List<AbilityDef> loadout) {
  final f = AbilityRuntime.passiveFractions(loadout);

  var out = stats;
  if (f.armorPct != 0.0) out = out.withFractions(armorPct: f.armorPct);
  if (f.attackSpeedPct != 0.0) {
    out = out + StatBlock(increasedAttackSpeed: f.attackSpeedPct);
  }

  // Ауры: стат — сразу в блок, резерв — вычетом из запаса маны.
  //
  // Резерв уходит именно в `maxMana`, а не считается отдельным числом в бою:
  // тогда всё — полоска, цена каста, регенерация — само работает с тем
  // запасом, который у героя РЕАЛЬНО есть. Отдельное число пришлось бы
  // помнить в каждой из этих точек, и одна из них рано или поздно забыла бы.
  out = out + _auraStats(out, loadout);

  final reserved = auraReservation(loadout);
  if (reserved <= 0.0) return out;

  // Резерв забирает и запас, и его восстановление.
  //
  // Иначе аура не стоила бы почти ничего: регенерация плоская, и полный
  // резерв оставлял бы герою тот же приток маны — активки продолжали бы
  // кастоваться в прежнем ритме, просто без запаса на всплеск. Резерв — это
  // «часть твоей маны занята», а не «часть твоего ведра».
  return out +
      StatBlock(
        maxMana: -out.maxMana * reserved,
        manaRegen: -out.manaRegen * reserved,
      );
}

/// Прибавки статов от аур. Доли считаются от блока ДО аур: иначе две ауры
/// на один стат зависели бы от порядка в слотах.
StatBlock _auraStats(StatBlock base, List<AbilityDef> loadout) {
  var out = StatBlock.zero;

  // «+% к силе Аур» с вещей и дерева. Читается из блока ДО аур — иначе аура,
  // дающая этот же множитель, усиливала бы сама себя.
  final power = 1.0 + (base.tagDamage[Tag.aura] ?? 0.0);

  for (final def in loadout) {
    if (def.kind != AbilityKind.auraStat) continue;

    final name = def.params.str('stat');
    final value = def.params.dbl('value') * power;
    for (final key in StatKey.values) {
      if (key.name != name) continue;
      out = out +
          switch (key) {
            StatKey.increasedDamage => StatBlock(increasedDamage: value),
            StatKey.increasedAttackSpeed =>
              StatBlock(increasedAttackSpeed: value),
            StatKey.armorPct => StatBlock(armor: base.armor * value),
            StatKey.maxHpPct => StatBlock(maxHp: base.maxHp * value),
            StatKey.leech => StatBlock(leech: value),
            StatKey.critChance => StatBlock(critChance: value),
            StatKey.critMulti => StatBlock(critMulti: value),
            StatKey.hpRegen => StatBlock(hpRegen: value),
            StatKey.attackDamage => StatBlock(attackDamage: value),
            StatKey.spellPower => StatBlock(spellPower: value),
            StatKey.manaRegen => StatBlock(manaRegen: value),
            StatKey.cooldownReduction =>
              StatBlock(cooldownReduction: value),
            StatKey.resistFire ||
            StatKey.resistCold ||
            StatKey.resistLightning ||
            StatKey.resistVoid =>
              StatBlock(
                resistFire: value,
                resistCold: value,
                resistLightning: value,
                resistVoid: value,
              ),
            // Стат, которого свёртка не умеет, валится валидатором контента:
            // молча ничего не давать здесь нельзя.
            _ => StatBlock.zero,
          };
    }
  }
  return out;
}

/// Стартовый набор способностей нового аккаунта (GDD §10).
List<String> starterAbilityIds() => [
      for (final def in ContentPack.current.abilities)
        if (def.isStarter) def.id,
    ].take(Tuning.abilitySlots).toList();
