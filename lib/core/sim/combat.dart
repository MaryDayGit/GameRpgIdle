import '../balance/tuning.dart';
import '../model/damage.dart';
import '../model/enemy.dart';
import '../model/hero.dart';
import '../model/tags.dart';
import 'abilities.dart';
import 'combat_feed.dart';
import 'events.dart';
import 'passive_rules.dart';
import 'relics.dart';
import 'rng.dart';
import 'triggers.dart';

class WaveOutcome {
  WaveOutcome({
    required this.heroAlive,
    required this.seconds,
    required this.damageTaken,
    required this.damageDealt,
    required this.damageByType,
    required this.kills,
    required this.timedOut,
    required this.lowestHpFraction,
    this.killer,
  });

  final bool heroAlive;
  final double seconds;
  final double damageTaken;
  final double damageDealt;

  /// Нанесённый урон в разбивке по типу. Индекс — `DamageType.index`.
  ///
  /// Список, а не карта: он складывается на каждом ударе, а бой — самое
  /// горячее место симуляции. Пять чисел в массиве стоят ровно ничего,
  /// карта с аллокацией на промах — заметно дороже.
  ///
  /// Нужен заданиям: «пройдите спуск, нанеся половину урона Молнией» — это
  /// единственный способ поставить игроку цель про БИЛД, а не про глубину.
  final List<double> damageByType;

  final int kills;

  /// Бой упёрся в таймаут: герой не тянет волну в принципе.
  /// Для офлайн-модели это отдельный исход, не то же самое, что смерть.
  final bool timedOut;

  /// Насколько низко проседало здоровье. Журнал отсутствия рассказывает
  /// не только чем кончилось, но и где было страшно (GDD §9.3).
  final double lowestHpFraction;

  /// Кто нанёс последний удар. `null`, если герой выжил.
  final EnemyArchetype? killer;
}

/// Бой одной волны, пошагово. Фиксированный тик 100 мс, отвязанный от рендера.
///
/// Пошаговость — не удобство, а требование двух режимов сразу. Балансировщику
/// и офлайн-расчёту нужен бой, посчитанный целиком и мгновенно; экрану — тот
/// же бой, идущий на глазах игрока, с паузой и ускорением. Две реализации
/// одной математики разъехались бы в первый же месяц, поэтому реализация одна:
/// [WaveCombat.run] — это `while (!finished) tick()` и ничего больше.
///
/// Ускорение x2/x4 в игре — это больше тиков за кадр, а не изменение dt:
/// изменение dt ломает детерминизм, а вместе с ним сверку офлайна.
class WaveRunner implements CombatContext {
  WaveRunner({
    required this.bus,
    required this.depth,
    required this.hero,
    required this.enemies,
    required this.rng,
    AbilityRuntime? abilities,
    this.triggers,
    this.rules = RelicRules.none,
    this.passives = PassiveRules.none,
    this.feed,
  })  : abilities = abilities ?? AbilityRuntime.empty,
        mods = abilities?.mods ?? CombatModifiers(),
        _remaining = enemies.length,
        _totalWaveHp = enemies.fold<double>(0.0, (sum, e) => sum + e.maxHp) {
    // Привязка ДО onWaveStart: триггер «Авангард» подписан именно на это
    // событие, и без привязки он выстрелил бы в пустоту.
    triggers?.bind(this);

    // «Печать тысячи глаз»: проклятие переходит на новую волну. Иначе правило
    // «проклятия не спадают до конца этажа» кончалось бы на первом же убитом.
    if (rules.eternalCurse && mods.carriedCurse > 0.0) {
      for (final enemy in this.enemies) {
        enemy.applyCurse(mods.carriedCurse, 1e9);
      }
    }

    // «Первый удар» дерева пассивок взводится на каждой новой волне. Тот же
    // механизм, что у триггера «Авангард», и складываться они не должны:
    // берётся большее, иначе два источника одного правила давали бы
    // произведение, которого никто не обещал.
    if (passives.firstStrike > 0.0) {
      mods.firstHitPending = true;
      if (passives.firstStrike > mods.firstHitBonus) {
        mods.firstHitBonus = passives.firstStrike;
      }
    }

    // «Перчатка первой крови» пользуется тем же механизмом, что и «Авангард»,
    // и по тому же правилу: берётся большее, а не произведение.
    if (rules.firstStrikeMultiplier > 1.0) {
      mods.firstHitPending = true;
      final bonus = rules.firstStrikeMultiplier - 1.0;
      if (bonus > mods.firstHitBonus) mods.firstHitBonus = bonus;
    }

    bus.emit(EventContext(GameEventType.onWaveStart, source: hero));
    feed?.add(CombatBeat(BeatKind.waveStarted,
        amount: this.enemies.length.toDouble()));
  }

  @override
  final EventBus bus;
  @override
  final int depth;
  @override
  final HeroState hero;
  @override
  final List<EnemyInstance> enemies;
  @override
  final Rng rng;

  final AbilityRuntime abilities;
  final TriggerRuntime? triggers;

  /// Поправки, которые выставляют триггеры. Общий объект с рантаймами.
  final CombatModifiers mods;

  /// Правила от надетых реликтов.
  final RelicRules rules;

  /// Боевые правила от дерева пассивок. Отдельно от [rules]: источники
  /// разные, и путать их нельзя — реликт теряется со снаряжением, дерево
  /// принадлежит игроку.
  final PassiveRules passives;

  /// Канал наблюдения. `null` — бой считается молча: офлайн и балансировщик
  /// не платят за анимацию, которую никто не смотрит.
  @override
  final CombatFeed? feed;

  double _time = 0.0;
  double _damageTaken = 0.0;
  double _damageDealt = 0.0;
  final List<double> _damageByType =
      List<double>.filled(DamageType.values.length, 0.0);
  int _kills = 0;
  int _remaining;
  bool _done = false;

  final double _totalWaveHp;
  double _lowestHpFraction = 1.0;
  EnemyArchetype? _killer;
  double _damageAtWindowStart = 0.0;
  double _nextStallCheck = Tuning.stallCheckSeconds;

  bool get finished => _done;

  double get seconds => _time;
  int get kills => _kills;
  int get remaining => _remaining;

  /// Доля волны, которую герой уже снёс, — то, что рисует полоска прогресса.
  double get waveProgress =>
      _totalWaveHp > 0.0 ? (_damageDealt / _totalWaveHp).clamp(0.0, 1.0) : 1.0;

  WaveOutcome get outcome => WaveOutcome(
        heroAlive: hero.alive,
        seconds: _time,
        damageTaken: _damageTaken,
        damageDealt: _damageDealt,
        damageByType: _damageByType,
        kills: _kills,
        timedOut: hero.alive && _remaining > 0,
        lowestHpFraction: _lowestHpFraction,
        killer: hero.alive ? null : _killer,
      );

  void tick() {
    if (_done) return;

    if (_time >= Tuning.waveTimeoutSeconds) {
      _done = true;
      return;
    }

    final dt = Tuning.tickSeconds;
    bus.beginTick();

    // --- Черты живых мобов ---------------------------------------------------
    // Ни одна не стакается: пачка из трёх Ледяных стражей замедляет ровно так
    // же, как один. Иначе один архетип в пачке решает исход этажа сильнее,
    // чем вся кривая сложности.
    var slowed = false;
    var shredded = false;
    for (final e in enemies) {
      if (!e.alive) continue;
      if (e.archetype.has(EnemyTrait.slowsHero)) slowed = true;
      if (e.archetype.has(EnemyTrait.shredResists)) shredded = true;
    }
    final slowMult = slowed ? 1.0 - Tuning.slowFraction : 1.0;
    final shredMult = shredded ? 1.0 - Tuning.shredFraction : 1.0;

    // --- Аура замедления -----------------------------------------------------
    // Аура обновляет обычный эффект замедления, а не живёт отдельной сущностью:
    // тогда «бонус по замедленным» и «ледяная цепь» видят её так же, как любой
    // другой источник, и правил становится одно вместо двух.
    final aura =
        mods.aurasDisabled ? 0.0 : abilities.auraSlowFor(hero.stats);
    if (aura > 0.0) {
      for (final e in enemies) {
        if (e.alive) e.applySlow(aura, dt * 2.0);
      }
    }

    // --- Способности ---------------------------------------------------------
    abilities.tick(dt, this);

    // --- Герой бьёт ----------------------------------------------------------
    final attackSpeed = hero.stats.attackSpeed *
        (1.0 + hero.stats.increasedAttackSpeed + abilities.buffAttackSpeed);
    hero.attackAccumulator += attackSpeed * slowMult * dt;

    while (hero.attackAccumulator >= 1.0 && _remaining > 0) {
      hero.attackAccumulator -= 1.0;
      if (!_autoAttack()) break;

      // Повтор автоатаки («Эхо клинка») — не второй удар по кулдауну, а копия
      // этого же: он видит тот же баф, то же проклятие и тот же крит-шанс.
      final repeat = abilities.repeatAttackChance;
      if (repeat > 0.0 && _remaining > 0 && rng.chance(repeat)) {
        _autoAttack();
      }
    }

    if (_remaining <= 0) {
      _time += dt;
      _done = true;
      return;
    }

    // --- Доты ----------------------------------------------------------------
    // Доты не критуют и не порождают событий (`docs/02-TECH.md` §2.3): иначе
    // горение, накладываемое критом, замыкает шину саму на себя.
    for (final e in enemies) {
      if (!e.alive || e.dotRemaining <= 0.0) continue;
      _applyDamage(
        e,
        base: e.dotDamagePerSecond * dt,
        type: e.dotType,
        // Теги источника, а не пустой список: горение от огненной способности
        // усиливается огненными аффиксами так же, как её прямой урон.
        tags: e.dotTags,
        // «Пепельный завет» разрешает горению критовать. События дот всё равно
        // не порождает: критующее горение, поднимающее шину, — это тот самый
        // каскад, от которого стоят предохранители.
        canCrit: rules.burnCanCrit && e.dotType == DamageType.fire,
        silent: true,
        isDot: true,
      );
    }

    if (_remaining <= 0) {
      _time += dt;
      _done = true;
      return;
    }

    // --- Мобы бьют -----------------------------------------------------------
    for (final e in enemies) {
      if (!e.alive) continue;
      e.waveSeconds += dt;

      // «Ревун» лечит соседей, пока жив. Себя не лечит: иначе один ревун в
      // пачке был бы бессмертен, а это уже не повадка, а стена.
      if (e.archetype.has(EnemyTrait.healsAllies)) {
        final heal = Tuning.allyHealPerSecond * dt;
        for (final ally in enemies) {
          if (!ally.alive || identical(ally, e)) continue;
          ally.hp += ally.maxHp * heal;
          if (ally.hp > ally.maxHp) ally.hp = ally.maxHp;
        }
      }

      // Разгон — множитель к урону, а не к скорости атаки: скорость сдвинула
      // бы момент удара и сделала бы бой чувствительным к длине тика.
      final ramp = e.archetype.has(EnemyTrait.rampUp)
          ? 1.0 +
              (Tuning.rampPerSecond * e.waveSeconds).clamp(0.0, Tuning.rampCap)
          : 1.0;

      final slowedBy = e.slowed ? e.slowFraction.clamp(0.0, 0.9) : 0.0;
      e.attackAccumulator += e.attackSpeed * (1.0 - slowedBy) * dt;

      while (e.attackAccumulator >= 1.0) {
        e.attackAccumulator -= 1.0;

        final result = DamageCalc.compute(
          base: e.damagePerHit * ramp,
          type: e.archetype.damageType,
          rng: rng,
          // Прибавка ко всем сопротивлениям от «Шкуры призм» и вычет по
          // своей стихии от «Проводника»: реликт даёт силу и тут же делает
          // героя уязвимым ровно к тому, чем бьёт.
          targetResist: (hero.stats.resistFor(e.archetype.damageType) +
                  rules.bonusResistAll -
                  (rules.conduitType == e.archetype.damageType
                      ? rules.conduitResistPenalty
                      : 0.0)) *
              shredMult,
          // «Шкура призм» отменяет броню целиком: не срезает, а выключает.
          targetArmor: rules.armorDisabled
              ? 0.0
              : hero.stats.armor * (1.0 - mods.lessArmor),
          depth: depth,
          canCrit: false,
        );

        // «Разрядник» снимает ману ударом. Повадка, которая РАЗЛИЧАЕТ
        // сборки: живущему автоатакой она не мешает вовсе, а тому, кто
        // держится на активках, стоит следующего каста.
        if (e.archetype.has(EnemyTrait.drainsMana)) {
          hero.pay(Tuning.manaDrainPerHit);
        }

        // Защита на низком здоровье («Последний рубеж») режет урон до того,
        // как он снят: иначе она спасала бы уже мёртвого.
        final taken = result.amount * abilities.damageTakenMultiplier(hero);

        hero.hp -= taken;
        _damageTaken += taken;

        // «Клятый договор»: каждый принятый удар копит урон до конца волны.
        if (rules.painPerHit > 0.0 && mods.painStacks < rules.painMaxStacks) {
          mods.painStacks++;
        }

        // Шипы: часть полученного возвращается ударившему. Без крита и без
        // событий — это отражение, а не удар героя, и цепочка «шипы убили ->
        // взрыв трупа -> шипы…» была бы тем самым каскадом, от которого
        // стоят предохранители шины.
        final thorns = abilities.thornsFraction;
        if (thorns > 0.0 && e.alive) {
          dealDamage(
            e,
            base: taken * thorns,
            type: DamageType.physical,
            tags: const [],
            canCrit: false,
          );
        }

        // Узел древа «Порог»: один раз за спуск смертельный удар оставляет
        // 1 HP. Проверка здесь, а не в конце тика: между ударом и концом тика
        // герой успел бы «умереть» для всего остального кода.
        if (!hero.alive && mods.deathThreshold && !mods.deathThresholdUsed) {
          mods
            ..deathThresholdUsed = true
            ..deathThresholdTriggered = true;
          hero.hp = 1.0;
        }

        if (!hero.alive) _killer = e.archetype;
        // Ниже нуля здоровье не бывает: добивающий удар обычно бьёт с
        // перехлёстом, и «−0.3 % HP» в журнале выглядело бы опечаткой.
        final fraction = hero.hpFraction.clamp(0.0, 1.0);
        if (fraction < _lowestHpFraction) _lowestHpFraction = fraction;
        if (e.archetype.has(EnemyTrait.lifesteal)) {
          e.heal(taken * Tuning.lifestealFraction);
        }
        bus.emit(EventContext(GameEventType.onDamageTaken,
            source: e, target: hero, amount: taken));

        if (feed != null) {
          feed!.add(CombatBeat(BeatKind.heroHurt,
              index: enemies.indexOf(e), amount: taken));
          if (!hero.alive) feed!.add(const CombatBeat(BeatKind.heroDied));
        }

        if (!hero.alive) break;
      }
      if (!hero.alive) break;
    }

    // --- Реген, эффекты, тик -------------------------------------------------
    // Мана восстанавливается всегда, в том числе там, где запрещена
    // регенерация HP: «этаж без регенерации» — модификатор про выживание,
    // и молча выключать им ещё и способности значило бы штрафовать дважды.
    if (hero.alive && hero.stats.manaRegen > 0.0) {
      hero.restoreMana(hero.stats.manaRegen * dt);
    }

    if (hero.alive && !mods.regenDisabled && hero.stats.hpRegen > 0.0) {
      // «Кровавый обет»: лечит только вампиризм. Регенерация выключена не
      // числом, а правилом — иначе реликт был бы просто «−100 % регена».
      if (!rules.healOnlyByLeech) hero.heal(hero.stats.hpRegen * dt);
    }
    for (final e in enemies) {
      if (e.alive) e.tickEffects(dt);
    }

    bus.emit(EventContext(GameEventType.onTick, source: hero, amount: dt));
    _time += dt;

    if (!hero.alive) {
      _done = true;
      return;
    }

    // Безнадёжность определяется отсутствием прогресса, а не временем:
    // абсолютный таймаут против экспоненциальных кривых рано или поздно
    // становится тем, что обрывает ран вместо смерти героя.
    if (_time >= _nextStallCheck) {
      final progressed = (_damageDealt - _damageAtWindowStart) / _totalWaveHp;
      if (progressed < Tuning.stallProgressThreshold) {
        _done = true;
        return;
      }
      _damageAtWindowStart = _damageDealt;
      _nextStallCheck += Tuning.stallCheckSeconds;
    }
  }

  bool _autoAttack() {
    final target = _firstAlive(enemies);
    if (target == null) return false;

    feed?.add(CombatBeat(BeatKind.heroSwing, index: enemies.indexOf(target)));

    _applyDamage(
      target,
      // Модификатор «Тишина» усиливает именно автоатаки: способности этой
      // прибавки не получают, иначе плюс перестал бы компенсировать минус.
      base: hero.stats.attackDamage *
          (1.0 + mods.autoAttackDamage) *
          (1.0 + abilities.autoAttackMore),
      // Пропитка меняет и стихию, и теги: пропитанный клинок бьёт огнём, и
      // «+% к урону Огнём» с вещей начинает работать на том, чем наёмник
      // наносит львиную долю урона. Без этого моста огненная сборка на
      // оружии была невозможна в принципе.
      //
      // Автоатака и без пропитки не безтеговая: «Атака», «Удар»,
      // «Физический». Иначе у сборки вокруг оружия не было бы ни одного
      // аффикса, который усиливает именно её.
      type: abilities.autoAttackType,
      tags: abilities.autoAttackTags,
      leech: true,
    );
    return true;
  }

  @override
  double dealDamage(
    EnemyInstance target, {
    required double base,
    required DamageType type,
    required List<Tag> tags,
    bool canCrit = true,
  }) =>
      _applyDamage(
        target,
        base: base,
        type: type,
        tags: tags,
        canCrit: canCrit,
      );

  /// Урон, посчитанный кем-то другим: триггер «этот удар бьёт вдвое».
  ///
  /// Молча и без формулы — иначе броня применилась бы второй раз, а события
  /// от добавки замкнули бы шину на себя.
  @override
  void dealRawDamage(EnemyInstance target, double amount,
      {DamageType type = DamageType.physical}) {
    if (!target.alive || amount <= 0.0) return;

    _damageDealt += amount;
    // Тип называет тот, кто нанёс: иначе «перескок» Молнии считался бы
    // физическим и задание «нанесите половину урона Молнией» врало бы ровно
    // на ту долю, которую даёт узел дерева.
    _damageByType[type.index] += amount;
    final watched = feed != null ? enemies.indexOf(target) : -1;
    feed?.add(CombatBeat(BeatKind.enemyHit, index: watched, amount: amount));

    if (target.takeDamage(amount)) {
      feed?.add(CombatBeat(BeatKind.enemyDied,
          index: watched,
          name: target.archetype.name,
          gender: target.archetype.gender));
      _kills++;
      _remaining--;
      _healOnKill();
      _explodeIfNeeded(target);
      abilities.onKill(target, this);
    }
  }

  /// «Головня» взрывается при смерти.
  ///
  /// Одним методом на оба пути убийства — обычный удар и «сырой» урон от
  /// триггера. Первая версия жила только во втором, и замер честно показал
  /// ноль: обычные смерти взрыва не давали вовсе.
  ///
  /// Урон считается от УДАРА погибшего, а не от его запаса прочности: иначе
  /// толстый взрывался бы сильнее злого, и повадка читалась бы как «толстые
  /// опаснее», а не как «за площадной удар по пачке придётся заплатить».
  ///
  /// Событий не порождает: цепочка «взрыв убил -> взрыв -> …» была бы тем
  /// самым каскадом, от которого стоят предохранители шины.
  void _explodeIfNeeded(EnemyInstance target) {
    if (!target.archetype.has(EnemyTrait.explodesOnDeath)) return;
    final blast = target.damagePerHit * Tuning.explosionFraction;
    hero.hp -= blast;
    _damageTaken += blast;
  }

  /// «Жатва»: убийство возвращает долю максимума здоровья.
  ///
  /// Отдельным методом, потому что смертей в бою две точки — прямой урон и
  /// доты, — и правило, забытое в одной из них, работало бы через раз.
  void _healOnKill() {
    if (passives.killHeal <= 0.0 || !hero.alive) return;
    hero.heal(hero.stats.maxHp * passives.killHeal);
  }

  /// Единственная точка нанесения урона по мобу.
  ///
  /// И автоатака, и способности, и доты, и взрывы трупов идут через неё.
  /// Иначе проклятие, вампиризм и учёт убийств пришлось бы повторить в каждой
  /// ветке — и разойтись они успели бы раньше, чем кто-нибудь это заметил.
  double _applyDamage(
    EnemyInstance target, {
    required double base,
    required DamageType type,
    required List<Tag> tags,
    bool canCrit = true,
    bool silent = false,
    bool leech = false,
    bool isDot = false,
  }) {
    if (!target.alive) return 0.0;

    // «Пепельный завет» срезает ПРЯМОЙ урон Огнём — горение под штраф не
    // попадает, в этом и состоит размен.
    var amountBase = base;
    if (!isDot &&
        type == DamageType.fire &&
        rules.directFirePenalty > 0.0) {
      amountBase *= 1.0 - rules.directFirePenalty;
    }

    var increased = hero.stats.increasedDamage + abilities.buffIncreasedDamage;
    for (final tag in tags) {
      increased += hero.stats.tagDamage[tag] ?? 0.0;
    }

    // Первый удар по волне усиливается один раз — флаг снимается здесь, а не
    // по таймеру: «первый» означает первый нанесённый урон, а не первую
    // попытку.
    var firstHit = 1.0;
    if (!silent && mods.firstHitPending) {
      firstHit = 1.0 + mods.firstHitBonus;
      mods.firstHitPending = false;
      mods.firstStrikeUsed = true;
    }

    // «Проводник стихии»: весь урон героя становится одной стихией. Не
    // прибавка, а подмена — и потому же его слабость: сопротивление ей срезано.
    final dealtType = rules.conduitType ?? type;

    final result = DamageCalc.compute(
      base: amountBase,
      type: dealtType,
      rng: rng,
      increased: increased,
      // «Отчаяние»: ниже половины здоровья урон умножается. Множитель, а не
      // прибавка: он и должен ощущаться переломом, а не ещё одним процентом.
      more: hero.moreDamage.product *
          (1.0 + mods.moreDamage) *
          firstHit *
          // Реликты, меняющие сам размер удара: «Маска неизбежности» и
          // «Жатва» его срезают, «Стеклянный венец» поднимает.
          (1.0 + rules.damageBonus + rules.conduitBonus) *
          // «Клятый договор»: каждый полученный удар копит урон до конца
          // волны. Стаки живут в модификаторах — они и обнуляются волной.
          (1.0 + mods.painStacks * rules.painPerHit) *
          // «Перчатка первой крови»: первый удар по волне усилен, остальные
          // ослаблены. Множитель первого живёт в `firstHit` выше, здесь —
          // плата за все последующие.
          (mods.firstStrikeUsed ? 1.0 - rules.afterFirstPenalty : 1.0) *
          (passives.lowLifeMoreDamage > 0.0 && hero.hpFraction < 0.5
              ? 1.0 + passives.lowLifeMoreDamage
              : 1.0) *
          // «Тлеющий след»: длительный урон умножается. Плата за то, что дот
          // бьёт не сразу, — иначе сборка вокруг доти́ков всегда проигрывает
          // прямому урону просто потому, что тот приходит раньше.
          (isDot ? 1.0 + passives.dotMoreDamage : 1.0) *
          // «Печать увядания»: по проклятым бьёт сильнее. Множитель героя, а
          // не долевой модификатор цели, — в отличие от самого проклятия.
          (target.cursed ? 1.0 + passives.curseMoreDamage : 1.0),
      // «Охотник на медленных»: по замедленной цели крит гарантирован.
      // Правило, а не прибавка: шанс не складывается, он заменяется.
      critChance: passives.critVsSlowed && target.slowed
          ? 1.0
          : hero.stats.critChance,
      critMulti: hero.stats.critMulti,
      targetResist: target.archetype.resistFor(dealtType),
      // «Затвердевающий»: броня растёт по ходу боя — зеркало разгона для
      // защиты. Затянуть с ним значит уже не убить.
      targetArmor: target.archetype.has(EnemyTrait.hardens)
          ? target.armor *
              (1.0 +
                  (Tuning.hardenPerSecond * target.waveSeconds)
                      .clamp(0.0, Tuning.hardenCap))
          : target.armor,
      depth: depth,
      // «Маска неизбежности»: крит не шанс, а правило.
      canCrit: (canCrit || rules.alwaysCrit) && !rules.critDisabled,
      forceCrit: rules.alwaysCrit,
    );

    // Проклятие поднимает получаемый урон уже после митигации: это долевой
    // модификатор цели, а не прибавка к урону героя.
    var amount = target.cursed
        ? result.amount * (1.0 + target.curseIncrease)
        : result.amount;

    // «Печать тысячи глаз»: по непроклятым герой бьёт заметно слабее.
    if (!target.cursed && rules.uncursedPenalty > 0.0) {
      amount *= 1.0 - rules.uncursedPenalty;
    }

    _damageDealt += amount;
    _damageByType[dealtType.index] += amount;

    // «Отражатель» возвращает долю полученного. Наказывает частые слабые
    // удары сильнее, чем редкие тяжёлые: доля берётся с КАЖДОГО удара.
    //
    // Доты не отражаются: горение тикает десять раз в секунду, и отражение
    // от него превратило бы повадку в постоянный урон, которого никто не
    // обещал. Событий отражение тоже не порождает — это не удар героя.
    if (!isDot && target.archetype.has(EnemyTrait.reflects)) {
      // Потолок — собственный удар отражателя.
      //
      // Без него повадка росла вместе с силой героя: доля от НАНЕСЁННОГО
      // урона означает, что чем лучше сборка, тем смертельнее отражение.
      // Механика, которая наказывает за силу, — перевёрнутая: замер кампании
      // показал падение со 171 этажа до 61.
      //
      // С потолком правило читается: «бьёт в ответ не сильнее, чем бьёт
      // сам», и остаётся наказанием за частые слабые удары, каким и было
      // задумано.
      final back = (amount * Tuning.reflectFraction)
          .clamp(0.0, target.damagePerHit);
      hero.hp -= back;
      _damageTaken += back;
    }

    // «Жатва»: цель ниже порога здоровья гибнет мгновенно. Правило, а не
    // урон: добить нельзя «почти».
    if (!isDot && rules.executeThreshold > 0.0 && target.alive) {
      final left = (target.hp - amount) / target.maxHp;
      if (left > 0.0 && left <= rules.executeThreshold) {
        amount = target.hp;
      }
    }

    // «Стылая хватка»: удар замедляет цель. Не от дота и не молча: замедление
    // от собственного горения тикало бы десять раз в секунду и держалось бы
    // вечно, а это уже не правило, а выключенная скорость атаки у всей волны.
    if (!isDot && !silent && passives.chillOnHit > 0.0) {
      target.applySlow(passives.chillOnHit, Tuning.chillSeconds);
    }

    // «Перескок»: урон Молнией задевает вторую цель. Уже посчитанной долей,
    // минуя формулу: иначе броня применилась бы второй раз, а событие от
    // добавки замкнуло бы шину на себя.
    if (!isDot &&
        !silent &&
        type == DamageType.lightning &&
        passives.shockSplash > 0.0 &&
        amount > 0.0) {
      for (final other in enemies) {
        if (!other.alive || identical(other, target)) continue;
        dealRawDamage(other, amount * passives.shockSplash,
            type: DamageType.lightning);
        break;
      }
    }

    if (leech && hero.stats.leech > 0.0) {
      hero.heal(amount * hero.stats.leech * abilities.leechMultiplier(hero));
    }

    if (!silent) {
      bus.emit(EventContext(GameEventType.onHit,
          source: hero, target: target, amount: amount));
      if (result.crit) {
        // «Кровь на клинке»: крит возвращает долю здоровья. Здесь, а не в
        // подписчике шины: у неё бюджет срабатываний на тик, и правило
        // дерева не должно его отнимать у чьего-то триггера.
        if (passives.critHeal > 0.0) {
          hero.heal(hero.stats.maxHp * passives.critHeal);
        }
        bus.emit(EventContext(GameEventType.onCrit,
            source: hero, target: target, amount: amount));
        abilities.onCrit(target, this);
      }
    }

    // Показать надо и то, что скрыто от шины: горение не порождает событий
    // механики, но снимает здоровье, и полоска, падающая без причины,
    // читается как ошибка отображения.
    final watched = feed != null ? enemies.indexOf(target) : -1;
    feed?.add(CombatBeat(BeatKind.enemyHit,
        index: watched, amount: amount, crit: result.crit));

    if (target.takeDamage(amount)) {
      feed?.add(CombatBeat(BeatKind.enemyDied,
          index: watched,
          name: target.archetype.name,
          gender: target.archetype.gender));
      _kills++;
      _remaining--;
      _healOnKill();
      _explodeIfNeeded(target);
      if (!silent) {
        bus.emit(
            EventContext(GameEventType.onKill, source: hero, target: target));
      }
      abilities.onKill(target, this);
    }

    return amount;
  }

  static EnemyInstance? _firstAlive(List<EnemyInstance> enemies) {
    for (final e in enemies) {
      if (e.alive) return e;
    }
    return null;
  }
}

/// Батч-обёртка: волна, посчитанная целиком и мгновенно.
///
/// То же самое, что пошаговый прогон, — и это не совпадение, а единственная
/// реализация.
class WaveCombat {
  WaveCombat({required this.bus, required this.depth, this.abilities});

  final EventBus bus;
  final int depth;
  final AbilityRuntime? abilities;

  WaveOutcome run(HeroState hero, List<EnemyInstance> enemies, Rng rng) {
    final runner = WaveRunner(
      bus: bus,
      depth: depth,
      hero: hero,
      enemies: enemies,
      rng: rng,
      abilities: abilities,
    );
    while (!runner.finished) {
      runner.tick();
    }
    return runner.outcome;
  }
}
