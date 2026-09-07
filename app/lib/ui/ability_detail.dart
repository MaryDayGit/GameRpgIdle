import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';

import 'format.dart';
import 'strings.dart';

/// Подробная карточка способности.
///
/// Существует ради одного вопроса, на который в игре негде было получить
/// ответ: **от чего это умение растёт и сколько оно бьёт ИМЕННО У МЕНЯ.**
///
/// Строка «Актив · 3 с · 10 маны · ×2.9 урона» отвечает на него только для
/// того, кто уже знает устройство игры. Игрок видит «×2.9 урона» и не может
/// узнать — урона чего, от какого стата, и почему найденный «+18 % к урону
/// Огнём» на эту способность не действует.
///
/// Поэтому здесь не описание, а РАЗБОР: каждая строка расчёта названа своим
/// именем и подставлена настоящим числом из сборки. Число, которое игрок
/// может проверить глазами, объясняет систему лучше любого абзаца.
class AbilityDetailSheet extends StatelessWidget {
  const AbilityDetailSheet({
    super.key,
    required this.def,
    required this.stats,
  });

  final AbilityDef def;

  /// Характеристики собранного наёмника. Разбор считается по ним, а не по
  /// эталонным: «сколько это бьёт вообще» — вопрос, которого игрок не задаёт.
  final StatBlock stats;

  static Future<void> show(
    BuildContext context, {
    required AbilityDef def,
    required StatBlock stats,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => AbilityDetailSheet(def: def, stats: stats),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(def.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 4),
              Text(_kindLine(def),
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 10),
              Text(
                TextTemplate.render(def.text, _params(def)),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 20),

              ..._scaling(context),
              ..._damageType(context),
              ..._cost(context),
              ..._tags(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- От чего растёт --------------------------------------------------------

  /// Разбор урона по шагам.
  ///
  /// Порядок строк повторяет порядок формулы: стат сборки, множитель
  /// способности, основа удара, увеличения, итог. Так видно не только
  /// «сколько», но и «где именно моя вещь вошла в это число».
  List<Widget> _scaling(BuildContext context) {
    final rows = <Widget>[];

    final multiplier = def.params.dbl('weaponMultiplier');
    final increased = _increasedFraction();

    if (multiplier > 0.0) {
      final source = def.isSpell ? stats.spellPower : stats.attackDamage;
      final base = source * multiplier;
      final hit = base * (1.0 + increased);

      rows.addAll([
        _row(
          def.isSpell ? S.statSpellPower : S.statWeaponDamage,
          money(source),
          def.isSpell
              ? S.abYourStatWeaponOnly
              : S.abYourStatSpellOnly,
        ),
        _row(S.abMultiplier, '×${_num(multiplier)}',
            S.abMultiplierAbout),
        _row(S.abHitBase, money(base), null, strong: true),
        _row(S.abIncreases, '+${(increased * 100).round()} %',
            _increasedBreakdown()),
        _row(S.abDamagePerHit, money(hit), null, strong: true),
      ]);

      final targets = def.params.integer('targets', 1);
      if (targets > 1) {
        rows.add(_row(
            S.abTargetsAtOnce, targets >= 99 ? S.abWholeWave : '$targets',
            S.abTargetsAbout));
      }

      if (def.kind == AbilityKind.execute) {
        final bonus = def.params.dbl('bonusBelow');
        final threshold = def.params.dbl('threshold');
        rows.add(_row(
          S.abVsWounded,
          money(hit * (1.0 + bonus)),
          S.abVsWoundedAbout((threshold * 100).round()),
        ));
      }
      if (def.kind == AbilityKind.chainDamage) {
        final falloff = def.params.dbl('falloff');
        rows.add(_row(S.abChainFalloff, '−${(falloff * 100).round()} %',
            S.abChainFalloffAbout));
      }
      if (def.params.dbl('bonusVsSlowed') > 0.0) {
        final bonus = def.params.dbl('bonusVsSlowed');
        rows.add(_row(S.abVsSlowed, money(hit * (1.0 + bonus)),
            S.abVsSlowedAbout));
      }
    }

    // Доты считаются не от удара, а от вашего урона в секунду.
    if (def.params.has('dpsFraction')) {
      final fraction = def.params.dbl('dpsFraction');
      final duration = def.params.dbl('duration');
      final perSecond = def.isSpell
          ? stats.spellPower * Tuning.spellReferenceRate
          : stats.attackDamage * stats.effectiveAttackSpeed;
      final dps = perSecond * fraction * (1.0 + increased);

      if (multiplier <= 0.0) {
        rows.addAll([
          _row(
            def.isSpell ? S.statSpellPower : S.statWeaponDamage,
            money(def.isSpell ? stats.spellPower : stats.attackDamage),
            def.isSpell
                ? S.abYourStatWeaponShort

                : S.abYourStatSpellShort,
          ),
          _row(S.abIncreases, '+${(increased * 100).round()} %',
              _increasedBreakdown()),
        ]);
      }
      rows.addAll([
        _row(S.abDot, S.perSecond(money(dps)),
            S.abDotAbout((fraction * 100).round())),
        _row(S.abHolds, TextTemplate.seconds(duration), null),
        _row(S.abTotalPerCast, money(dps * duration), null, strong: true),
      ]);
    }

    if (def.kind == AbilityKind.summonTotem) {
      final interval = def.params.dbl('interval');
      final duration = def.params.dbl('duration');
      rows.add(_row(S.abStrikesEvery, TextTemplate.seconds(interval),
          S.abTotemAbout(_num(duration))));


    }

    if (def.kind == AbilityKind.heal) {
      final fraction = def.params.dbl('fractionOfMaxHp');
      rows.add(_row(S.abRestores, money(stats.maxHp * fraction),
          S.abHealAbout((fraction * 100).round())));

    }

    if (def.kind == AbilityKind.infusion) {
      rows.add(_row(
        S.abAutoAttackDeals,
        def.damageType.title,
        S.abInfusionAbout(def.damageType.tag.title),
      ));
      final more = def.params.dbl('moreDamage');
      if (more > 0.0) {
        rows.add(_row(S.abAndHarder, '+${(more * 100).round()} %',
            S.abAndHarderAbout));
      }
    }

    if (def.kind == AbilityKind.auraStat) {
      rows.add(_row(S.abGivesAlways, _statLine(),
          S.abGivesAlwaysAbout));
    }

    if (def.kind == AbilityKind.buff) {
      rows.add(_row(S.abGivesFor(_num(def.params.dbl('duration'))),
          _statLine(), null));
    }

    if (def.kind == AbilityKind.repeatAttack) {
      rows.add(_row(S.abDoubleHitChance,
          '${(def.params.dbl('chance') * 100).round()} %',
          S.abDoubleHitAbout));
    }
    if (def.kind == AbilityKind.repeatSpell) {
      rows.add(_row(S.abDoubleCastChance,
          '${(def.params.dbl('chance') * 100).round()} %',
          S.abDoubleCastAbout));
    }
    if (def.kind == AbilityKind.thorns) {
      rows.add(_row(S.abReturnsToAttacker,
          '${(def.params.dbl('fractionReturned') * 100).round()} %',
          S.abReturnsAbout));

    }
    if (def.kind == AbilityKind.lowLifeGuard) {
      rows.add(_row(
          S.abBelowThresholdDamage(
              (def.params.dbl('threshold') * 100).round(),
              (def.params.dbl('lessDamageTaken') * 100).round()),
          '',

          S.abLessDamageAbout));
    }
    if (def.kind == AbilityKind.conditionalLeech) {
      rows.add(_row(
          S.abBelowThresholdLeech(
              (def.params.dbl('threshold') * 100).round(),
              _num(def.params.dbl('leechMultiplier'))),
          '',
          S.abLeechMultiAbout));
    }
    if (def.kind == AbilityKind.statTradeoff) {
      rows.add(_row(S.abTradeoff, _tradeoffLine(),
          S.abTradeoffAbout));
    }
    if (def.kind == AbilityKind.auraSlow) {
      rows.add(_row(S.abSlowsAttackers,
          '−${(def.params.dbl('slow') * 100).round()} %',
          S.abSlowsAbout));

    }
    if (def.kind == AbilityKind.corpseExplosion) {
      rows.add(_row(
          S.abCorpseBurst(
              (def.params.dbl('fractionOfMaxHp') * 100).round()),
          '',

          S.abCorpseBurstAbout));

    }
    if (def.kind == AbilityKind.curse) {
      rows.add(_row(S.abTargetTakesMore,
          '+${(def.params.dbl('damageTakenIncrease') * 100).round()} %',
          S.abBrandAbout(_num(def.params.dbl('duration')))));


    }
    if (def.kind == AbilityKind.critApplyDot) {
      rows.add(_row(
          S.abOnCrit(
              '${(stats.critChance * 100).toStringAsFixed(1)} %'),
          '',

          S.abOnCritAbout));
    }

    // Итог в секунду — только там, где он честно считается.
    final perSecond = _damagePerSecond(increased);
    if (perSecond != null) {
      rows.add(const SizedBox(height: 4));
      rows.add(_row(S.abPerSecondTotal, money(perSecond),
          S.abPerSecondAbout,

          strong: true));
    }

    if (rows.isEmpty) return const [];
    return [_header(S.abScalesFrom), ...rows, const SizedBox(height: 20)];
  }

  /// Урон в секунду, если его можно посчитать без вранья.
  double? _damagePerSecond(double increased) {
    final cooldown = _effectiveCooldown();
    final multiplier = def.params.dbl('weaponMultiplier');

    if (def.kind == AbilityKind.summonTotem) {
      final source = def.isSpell ? stats.spellPower : stats.attackDamage;
      final interval = def.params.dbl('interval');
      if (interval <= 0.0) return null;
      final targets = def.params.integer('targets', 1);
      return source * multiplier * targets * (1.0 + increased) / interval;
    }

    if (!def.isActive || cooldown <= 0.0 || multiplier <= 0.0) return null;

    final source = def.isSpell ? stats.spellPower : stats.attackDamage;
    final targets = def.params.integer('targets', 1).clamp(1, 4);
    return source * multiplier * targets * (1.0 + increased) / cooldown;
  }

  double _effectiveCooldown() =>
      def.cooldown * (1.0 - stats.cooldownReduction).clamp(0.1, 1.0);

  // --- Тип урона -------------------------------------------------------------

  List<Widget> _damageType(BuildContext context) {
    if (!_dealsDamage) return const [];

    return [
      _header(S.abDamageType),
      _row(def.damageType.title, '', _resistNote()),
      const SizedBox(height: 20),
    ];
  }

  String _resistNote() => switch (def.damageType) {
        DamageType.physical =>
          S.abPhysicalAbout,

        _ => S.abElementalAbout(def.damageType.title),


      };

  bool get _dealsDamage =>
      def.params.has('weaponMultiplier') ||
      def.params.has('dpsFraction') ||
      def.kind == AbilityKind.corpseExplosion ||
      def.kind == AbilityKind.thorns ||
      def.kind == AbilityKind.infusion;

  // --- Цена ------------------------------------------------------------------

  List<Widget> _cost(BuildContext context) {
    final rows = <Widget>[];

    if (def.isActive) {
      rows.add(_row(
          S.abCooldown, TextTemplate.seconds(_effectiveCooldown()),
          stats.cooldownReduction > 0.0
              ? S.abCooldownBreakdown(_num(def.cooldown),
                  '−${(stats.cooldownReduction * 100).round()} %')

              : S.abCooldownAbout));

      rows.add(_row(S.abManaCost, money(def.manaCost),
          S.abManaCostAbout(money(stats.maxMana), _num(stats.manaRegen))));


      final drain = _effectiveCooldown() > 0.0
          ? def.manaCost / _effectiveCooldown()
          : 0.0;
      rows.add(_row(S.abDrain, S.abManaPerSecond(_num(drain)),
          S.abDrainAbout));

    } else if (def.isAura) {
      rows.add(_row(
          S.abReserves, S.abReservesPercent((def.manaReserve * 100).round()),
          S.abReservesAbout(money(stats.maxMana),
              money(stats.maxMana * (1.0 - def.manaReserve)))));


    } else {
      rows.add(_row(S.abCostsWord, S.abOneSlot,
          S.abPassiveAbout));

    }

    return [_header(S.abPrice), ...rows, const SizedBox(height: 20)];
  }

  // --- Теги ------------------------------------------------------------------

  List<Widget> _tags(BuildContext context) {
    if (def.tags.isEmpty) return const [];

    return [
      _header(S.abTags),
      Text(
        S.abTagsAbout,


        style: const TextStyle(
            fontSize: 12, color: Colors.white38, height: 1.35),
      ),
      const SizedBox(height: 10),
      for (final tag in def.tags) _tagRow(tag),
    ];
  }

  Widget _tagRow(Tag tag) {
    final value = stats.tagDamage[tag] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Доли, а не фиксированные ширины: «Длительность» при крупном
          // системном шрифте шире ста четырёх точек, и колонка обрезала бы
          // ровно название тега — то, ради чего строку и читают.
          Expanded(
            flex: 4,
            child: Text(tag.title,
                style: const TextStyle(fontSize: 13, height: 1.3)),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text(
              value > 0.0 ? '+${(value * 100).round()} %' : '—',
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: value > 0.0 ? FontWeight.w600 : FontWeight.w400,
                color: value > 0.0 ? Colors.white : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 7,
            child: Text(
              _tagMeaning(tag),
              style: const TextStyle(
                  fontSize: 11, color: Colors.white38, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  static String _tagMeaning(Tag tag) => switch (tag) {
        Tag.fire ||
        Tag.cold ||
        Tag.lightning ||
        Tag.voidTag ||
        Tag.physical =>
          S.abTagElement(tag.title),

        Tag.attack => S.abTagAttack,
        Tag.spell => S.abTagSpell,
        Tag.projectile => S.abTagProjectile,
        Tag.area => S.abTagArea,
        Tag.duration => S.abTagDuration,
        Tag.curse => S.abTagCurse,

        Tag.aura => S.abTagAura,
        Tag.totem => S.abTagTotem,
        Tag.strike => S.abTagStrike,
        Tag.blood => S.abTagBlood,
      };

  // --- Вспомогательное -------------------------------------------------------

  double _increasedFraction() {
    var v = stats.increasedDamage;
    for (final tag in def.tags) {
      v += stats.tagDamage[tag] ?? 0.0;
    }
    return v;
  }

  /// Из чего сложились увеличения. Без разбивки строка «+45 %» ничего не
  /// объясняет: игрок не может понять, какая его вещь сюда вошла.
  String _increasedBreakdown() {
    final parts = <String>[];
    if (stats.increasedDamage > 0.0) {
      parts.add(S.abIncreaseGeneral((stats.increasedDamage * 100).round()));
    }
    for (final tag in def.tags) {
      final v = stats.tagDamage[tag] ?? 0.0;
      if (v > 0.0) parts.add('${tag.title} +${(v * 100).round()} %');
    }
    if (parts.isEmpty) {
      return S.abNoIncreases;

    }
    return S.abIncreasesFrom(parts.join(', '));
  }

  String _statLine() {
    final name = def.params.str('stat');
    final value = def.params.dbl('value');
    final key = StatKeyText.byName(name);
    return key == null
        ? '$name $value'
        : '${key.percent ? '+${(value * 100).round()} %' : '+${_num(value)}'} '
            '${key.title}';
  }

  String _tradeoffLine() {
    final armor = def.params.dbl('armorPct');
    final speed = def.params.dbl('attackSpeedPct');
    String part(double v, String what) =>
        '${v >= 0 ? '+' : '−'}${(v.abs() * 100).round()} % $what';
    return '${part(armor, S.statArmor.toLowerCase())}, '
        '${part(speed, S.statAttackSpeed.toLowerCase())}';
  }

  static String _kindLine(AbilityDef def) => def.isActive
      ? S.abKindActive
      : def.isAura
          ? S.abKindAura
          : S.abKindPassive;

  static Map<String, double> _params(AbilityDef def) => {
        for (final entry in def.params.raw.entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      };

  static String _num(double v) {
    final rounded = v.roundToDouble();
    return (v - rounded).abs() < 0.005
        ? rounded.toStringAsFixed(0)
        : v.toStringAsFixed(v.abs() < 1.0 ? 2 : 1);
  }

  static Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
      );

  static Widget _row(String label, String value, String? note,
          {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        color: strong ? Colors.white : Colors.white70,
                        fontWeight:
                            strong ? FontWeight.w600 : FontWeight.w400,
                      )),
                ),
                const SizedBox(width: 8),
                // Значение тоже гибкое: «3.3 маны в секунду» рядом с длинной
                // подписью не влезает, и без этого строка уезжала за край.
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white38, height: 1.3)),
            ],
          ],
        ),
      );
}

/// Название стата по имени из контента.
///
/// Отдельно от `StatKey.title`, потому что там формулировки для строки аффикса
/// («% к урону»), а здесь нужен именительный падеж после числа.
class StatKeyText {
  const StatKeyText(this._label, {this.percent = false});

  final Phrase _label;
  final bool percent;

  String get title => _label.text;

  static StatKeyText? byName(String name) => switch (name) {
        'increasedDamage' =>
          const StatKeyText(Phrase('к урону', 'increased damage'),
              percent: true),
        'increasedAttackSpeed' => const StatKeyText(
            Phrase('к скорости атаки', 'increased attack speed'),
            percent: true),
        'armorPct' =>
          const StatKeyText(Phrase('к броне', 'armor'), percent: true),
        'maxHpPct' => const StatKeyText(
            Phrase('к максимуму HP', 'maximum HP'),
            percent: true),
        'leech' =>
          const StatKeyText(Phrase('вампиризма', 'life leech'), percent: true),
        'critChance' => const StatKeyText(
            Phrase('к шансу критического удара', 'critical strike chance'),
            percent: true),
        'critMulti' => const StatKeyText(
            Phrase('к множителю крита', 'critical strike multiplier'),
            percent: true),
        'cooldownReduction' => const StatKeyText(
            Phrase('ко времени перезарядки', 'cooldown reduction'),
            percent: true),
        'hpRegen' => const StatKeyText(
            Phrase('восстановления HP в секунду', 'HP regeneration per second')),
        'manaRegen' => const StatKeyText(Phrase(
            'восстановления маны в секунду', 'mana regeneration per second')),
        'attackDamage' =>
          const StatKeyText(Phrase('к урону оружия', 'weapon damage')),
        'spellPower' => const StatKeyText(Phrase('к силе чар', 'spell power')),
        'resistFire' ||
        'resistCold' ||
        'resistLightning' ||
        'resistVoid' =>
          const StatKeyText(
              Phrase('ко всем сопротивлениям', 'to all resistances')),
        _ => null,
      };
}
