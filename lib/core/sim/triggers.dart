import '../content/affix_def.dart';
import '../content/content_pack.dart';
import '../model/enemy.dart';
import '../model/stat_key.dart';
import '../model/tags.dart';
import 'abilities.dart';
import 'events.dart';
import 'relics.dart';

/// Поправки к бою: что выставили триггеры и модификатор этажа.
///
/// Общий изменяемый объект вместо запросов «а что там у триггеров» из десяти
/// мест боя. Пишут триггеры и спуск, читают бой и способности — и никто не
/// знает друг о друге больше необходимого.
class CombatModifiers {
  /// Долевая прибавка к урону из мультипликативной корзины.
  double moreDamage = 0.0;

  /// Доля, на которую срезана броня героя.
  double lessArmor = 0.0;

  /// Следующая способность бьёт дважды.
  bool doubleNextCast = false;

  /// Прибавки к баффам от способностей с тегом Тотем.
  double totemDurationBonus = 0.0;
  double totemValueBonus = 0.0;

  // --- От модификатора этажа (GDD §2.7) --------------------------------------
  // Выставляются на входе на этаж и держатся до следующего. Флагами, а не
  // статами: «реген не работает» невыразимо прибавкой к блоку статов.

  bool regenDisabled = false;
  bool aurasDisabled = false;

  // --- От древа Эха ----------------------------------------------------------

  /// Узел «Порог»: раз за СПУСК смертельный удар оставляет 1 HP.
  ///
  /// Живёт здесь, а не в волне, потому что «раз за спуск» — это про весь ран:
  /// сброс на каждой волне превратил бы узел в бессмертие.
  bool deathThreshold = false;
  bool deathThresholdUsed = false;

  /// Сработал ли порог: журналу нужно сказать, что наёмник выжил не сам.
  bool deathThresholdTriggered = false;

  /// Доля к урону АВТОАТАК — способности этот бонус не получают.
  double autoAttackDamage = 0.0;

  /// Сила проклятия, переносимая на следующие волны. Работает только с
  /// «Печатью тысячи глаз»; обнуляется на новом этаже.
  double carriedCurse = 0.0;

  void resetFloor() {
    regenDisabled = false;
    aurasDisabled = false;
    autoAttackDamage = 0.0;
    carriedCurse = 0.0;
  }

  /// Первый удар по новой волне усилен.
  bool firstHitPending = false;
  double firstHitBonus = 0.0;

  /// «Перчатка первой крови»: первый удар по волне уже сделан.
  ///
  /// Отдельно от [firstHitPending]: тот принадлежит триггерным аффиксам и
  /// гасится ими, а реликту нужно знать про волну — «все удары после первого»
  /// ослаблены до её конца.
  bool firstStrikeUsed = false;

  /// «Клятый договор»: сколько ударов уже принято за волну.
  ///
  /// Живёт в модификаторах, а не в герое, потому что обнуляется ВОЛНОЙ:
  /// накопленное за прошлую пачку не должно переезжать в следующую.
  int painStacks = 0;

  void resetWave() {
    firstHitPending = false;
    doubleNextCast = false;
    // Право на первый удар и накопленная боль принадлежат ПАЧКЕ, а не этажу:
    // перенести их в следующую волну значило бы дать реликту вдвое больше,
    // чем обещано.
    firstStrikeUsed = false;
    painStacks = 0;
  }
}

/// Рантайм триггерных аффиксов.
///
/// Триггеры — это подписки на шину событий, и именно поэтому у шины стоят
/// предохранители: «при крите сбросить кулдаун» плюс «крит накладывает
/// горение» плюс критующее горение образуют петлю, которая при невезучем сиде
/// вешает не тик, а открытие приложения (`docs/01-ANALYSIS.md` §6).
///
/// Отсюда же правило: урон, нанесённый триггером, идёт молча — без событий.
/// Цепочка «триггер ударил → сработал триггер → ударил снова» невозможна не по
/// договорённости, а по устройству.
class TriggerRuntime {
  TriggerRuntime({
    required this.bus,
    required this.abilities,
    required this.mods,
  });

  final EventBus bus;
  AbilityRuntime abilities;
  final CombatModifiers mods;

  /// Правила от реликтов. Меняются вместе со снаряжением.
  RelicRules rules = RelicRules.none;

  CombatContext? _ctx;
  List<TriggerAffixDef> _defs = const [];

  /// Счётчики отдельных триггеров. Живут на уровне рана: «каждый пятый удар»
  /// не должен обнуляться со сменой волны, иначе на коротких волнах он не
  /// сработает никогда.
  final Set<String> _subscribed = {};
  final Map<String, double> _counters = {};
  final Map<String, double> _timers = {};

  List<TriggerAffixDef> get defs => _defs;

  /// Пересобирает подписки под текущий набор надетых триггеров.
  ///
  /// Вызывается при смене снаряжения — в том числе в середине спуска, когда
  /// наёмник надел найденное. Снимаются только СВОИ подписки: шина общая, и
  /// сносить чужие ради удобства — это отказ, который проявится через полгода
  /// у второго подписчика.
  void configure(List<String> triggerIds) {
    final pack = ContentPack.current;
    _defs = [
      for (final id in triggerIds)
        pack.triggerAffix(id) ?? (throw StateError('Нет триггера «$id»')),
    ];

    for (final label in _subscribed) {
      bus.unsubscribe(label);
    }
    _subscribed.clear();
    mods.totemDurationBonus = 0.0;
    mods.totemValueBonus = 0.0;

    for (final def in _defs) {
      // Резонанс тотемов — не событие, а постоянная поправка: бафф создаётся
      // ВНУТРИ каста, а `onAbilityCast` приходит уже после него, и подписка
      // опоздала бы ровно на тот баф, который должна усилить.
      if (def.kind == TriggerKind.totemBoost) {
        mods.totemDurationBonus += def.params.dbl('duration');
        mods.totemValueBonus += def.params.dbl('rate');
        continue;
      }
      bus.subscribe(def.event, (ctx) => _handle(def, ctx), def.id);
      _subscribed.add(def.id);
    }
  }

  /// Привязывает рантайм к текущей волне.
  void bind(CombatContext ctx) {
    _ctx = ctx;
    mods.resetWave();
  }

  void _handle(TriggerAffixDef def, EventContext event) {
    final ctx = _ctx;
    if (ctx == null) return;

    switch (def.kind) {
      case TriggerKind.everyNthHit:
        _everyNthHit(def, event, ctx);
      case TriggerKind.resetRandomCooldown:
        if (ctx.rng.chance(def.params.dbl('chance'))) {
          abilities.resetRandomCooldown(ctx.rng);
        }
      case TriggerKind.stackingBuff:
        _stackingBuff(def);
      case TriggerKind.applyDotOnTaggedAbility:
        _dotOnTaggedAbility(def, event, ctx);
      case TriggerKind.lowHpTradeoff:
        _lowHpTradeoff(def, ctx);
      case TriggerKind.periodicDoubleCast:
        _periodicDoubleCast(def, event);
      case TriggerKind.curseSpread:
        _curseSpread(event, ctx);
      case TriggerKind.reflect:
        _reflect(def, event, ctx);
      case TriggerKind.firstHitBonus:
        mods.firstHitPending = true;
        mods.firstHitBonus = def.params.dbl('moreDamage');
      case TriggerKind.healOnCursedKill:
        _healOnCursedKill(def, event, ctx);
      case TriggerKind.frostChain:
        _frostChain(def, event, ctx);
      case TriggerKind.totemBoost:
        break; // постоянная поправка, выставлена в configure
    }
  }

  // --- Реализации ------------------------------------------------------------

  void _everyNthHit(TriggerAffixDef def, EventContext event, CombatContext ctx) {
    final target = event.target;
    if (target is! EnemyInstance) return;

    final n = def.params.integer('n', 1);
    if (n <= 0) return;

    // «Счётчик мгновений» ускоряет именно счётчики: каждый удар засчитывается
    // за несколько. Проще и честнее, чем множить срабатывания задним числом.
    final progress = (_counters[def.id] ?? 0.0) + rules.counterRate;
    if (progress < n) {
      _counters[def.id] = progress;
      return;
    }
    _counters[def.id] = progress - n;

    // Множитель 2.0 означает «двойной урон», то есть плюс ещё один такой же.
    ctx.dealRawDamage(target, event.amount * (def.params.dbl('multiplier', 1.0) - 1.0));
  }

  void _stackingBuff(TriggerAffixDef def) {
    final name = def.params.str('stat');
    final stat = StatKey.values.where((s) => s.name == name);
    if (stat.isEmpty) return;

    abilities.addStackingBuff(
      sourceId: def.id,
      stat: stat.first,
      value: def.params.dbl('value'),
      duration: def.params.dbl('duration'),
      maxStacks: def.params.integer('maxStacks', 1),
    );
  }

  void _dotOnTaggedAbility(
      TriggerAffixDef def, EventContext event, CombatContext ctx) {
    final ability = event.source;
    if (ability is! TaggedSource) return;

    final wanted = def.params.str('tag');
    if (!ability.tags.any((t) => t.name == wanted)) return;

    for (final enemy in ctx.enemies) {
      if (!enemy.alive) continue;
      enemy.applyDot(
        // Горение считается по той же оси, что и способность, которая его
        // подожгла: чарам — по силе чар. Иначе аффикс «поджигает Чарами»
        // молча требовал бы вложений в оружие.
        abilities.dotDpsFor(ctx, def.params.dbl('dpsFraction'),
            spell: ability.tags.contains(Tag.spell)),
        def.params.dbl('duration'),
        DamageType.fire,
        tags: [Tag.fire, Tag.duration, ...ability.tags.where(Tag.forms.contains)],
      );
      return;
    }
  }

  void _lowHpTradeoff(TriggerAffixDef def, CombatContext ctx) {
    // Выставляется каждый тик и потому сам себя снимает, когда герой
    // подлечился. Флага «включено» нет намеренно: он бы рассинхронизировался
    // с реальным HP ровно в тот момент, когда это важнее всего.
    // «Кожа отчаяния» держит порог включённым постоянно — это её правило.
    final low = rules.permanentLowLife ||
        ctx.hero.hpFraction <= def.params.dbl('threshold');
    mods.moreDamage = low ? def.params.dbl('moreDamage') : 0.0;
    mods.lessArmor = low ? def.params.dbl('lessArmor') : 0.0;
  }

  void _periodicDoubleCast(TriggerAffixDef def, EventContext event) {
    final period = def.params.dbl('period');
    if (period <= 0.0) return;

    final elapsed = (_timers[def.id] ?? 0.0) + event.amount * rules.counterRate;
    if (elapsed >= period) {
      _timers[def.id] = elapsed - period;
      mods.doubleNextCast = true;
    } else {
      _timers[def.id] = elapsed;
    }
  }

  void _curseSpread(EventContext event, CombatContext ctx) {
    final ability = event.source;
    if (ability is! TaggedSource) return;
    if (!ability.tags.contains(Tag.curse)) return;

    EnemyInstance? origin;
    for (final enemy in ctx.enemies) {
      if (enemy.alive && enemy.cursed) {
        origin = enemy;
        break;
      }
    }
    if (origin == null) return;

    for (final enemy in ctx.enemies) {
      if (!enemy.alive || identical(enemy, origin)) continue;
      enemy.applyCurse(origin.curseIncrease, origin.curseRemaining);
    }
  }

  void _reflect(TriggerAffixDef def, EventContext event, CombatContext ctx) {
    final attacker = event.source;
    if (attacker is! EnemyInstance || !attacker.alive) return;
    if (!ctx.rng.chance(def.params.dbl('chance'))) return;

    ctx.dealDamage(
      attacker,
      base: ctx.hero.stats.armor * def.params.dbl('armorFraction'),
      type: DamageType.voidType,
      tags: const [],
      canCrit: false,
    );
  }

  void _healOnCursedKill(
      TriggerAffixDef def, EventContext event, CombatContext ctx) {
    final target = event.target;
    if (target is! EnemyInstance || !target.cursed) return;
    ctx.hero.heal(ctx.hero.stats.maxHp * def.params.dbl('fraction'));
  }

  void _frostChain(
      TriggerAffixDef def, EventContext event, CombatContext ctx) {
    final target = event.target;
    if (target is! EnemyInstance || !target.slowed) return;

    for (final enemy in ctx.enemies) {
      if (!enemy.alive || identical(enemy, target)) continue;
      enemy.applySlow(def.params.dbl('slow'), def.params.dbl('duration'));
    }
  }
}
