import 'package:flutter/material.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/abilities.dart';

import 'format.dart';
import 'strings.dart';
import 'mercenary_screen.dart' show TagChips, tagColor;
import 'theme.dart';

/// Полный лист характеристик наёмника.
///
/// Существует потому, что на экране сборки помещается пять чисел, а решений
/// перед спуском принимается больше: «хватит ли брони», «не мороз ли меня
/// убил», «сколько маны съели ауры». Раньше эти числа были только внутри
/// симуляции, и игрок сравнивал предметы по тем пяти, которые видел.
///
/// Главное здесь не сами числа, а то, ЧТО ОНИ ЗНАЧАТ. «Броня 340» не говорит
/// ничего; «броня 340 — физический урон меньше на 28 % на глубине 60»
/// говорит всё. Голое число заставляет игрока строить свою модель игры и
/// почти всегда неверную.
class MercenaryStatsSheet extends StatelessWidget {
  const MercenaryStatsSheet({
    super.key,
    required this.mercenary,
    required this.profile,
    required this.depth,
  });

  final Mercenary mercenary;
  final HeroProfile profile;

  /// Глубина, для которой расшифровываются броня и сопротивления. Рекорд
  /// игрока: на первом этаже вклад брони почти нулевой, и расшифровка на нём
  /// вводила бы в заблуждение сильнее, чем её отсутствие.
  final int depth;

  static Future<void> show(
    BuildContext context, {
    required Mercenary mercenary,
    required HeroProfile profile,
    required int depth,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => MercenaryStatsSheet(
          mercenary: mercenary,
          profile: profile,
          depth: depth,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final stats = profile.aggregate();
    final reserved = auraReservation(profile.loadout);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(S.statsTitle, style: RiftText.title.copyWith(fontSize: 20)),
            const SizedBox(height: 2),
            Text(
              S.statsAbout(mercenary.name, depth,
                  she: mercenary.gender == Gender.feminine),


              style: RiftText.small,
            ),
            const SizedBox(height: 18),

            _Group(S.statsGroupSurvival, [
              _Line(S.statMaxHp, money(stats.maxHp)),
              _Line(S.statHpRegen,
                  S.perSecond(precise(stats.hpRegen)),
                  hint: stats.hpRegen <= 0.0
                      ? S.statsRestNote
                      : null),
              _Line(
                S.statArmor,
                money(stats.armor),
                hint: _armorHint(stats.armor),
              ),
            ]),

            _Group(S.statsGroupResists, [
              for (final (name, value, tag) in [
                (S.resistFire, stats.resistFire, Tag.fire),
                (S.resistCold, stats.resistCold, Tag.cold),
                (S.resistLightning, stats.resistLightning, Tag.lightning),
                (S.resistVoid, stats.resistVoid, Tag.voidTag),
              ])
                _Line(name, money(value), hint: _resistHint(value), tag: tag),
            ], note: S.resistsAbout(balance.Curves.resistCap.round())),


            _Group(S.statsGroupDamage, [
              _Line(S.statWeaponDamage, money(stats.attackDamage),
                  hint: S.statWeaponDamageAbout),
              _Line(S.statSpellPower, money(stats.spellPower),
                  hint: S.statSpellPowerAbout),
              _Line(S.statIncreasedDamage, percent(stats.increasedDamage)),
              // Поправка может быть и отрицательной — черта «Погорелица»
              // забирает скорость. «база 1.20 и -10 % сверху» читалось как
              // опечатка, поэтому знак называется словом.
              _Line(S.statAttackSpeed,
                  S.hitsPerSecond(stats.effectiveAttackSpeed.toStringAsFixed(2)),
                  hint: stats.increasedAttackSpeed == 0.0
                      ? null
                      : S.attackSpeedBreakdown(
                          stats.attackSpeed.toStringAsFixed(2),
                          percent(stats.increasedAttackSpeed.abs()),
                          positive: stats.increasedAttackSpeed > 0)),


              _Line(S.statCritChance, percent(stats.critChance)),
              _Line(S.statCritMulti,
                  '×${(1.0 + stats.critMulti).toStringAsFixed(2)}',
                  hint: _critHint(stats)),
            ]),

            _Group(S.statsGroupAbilities, [
              _Line(S.statMana, money(stats.maxMana),
                  hint: reserved <= 0.0
                      ? null
                      : S.manaReserved(percent(reserved))),
              _Line(S.statManaRegen,
                  S.perSecond(precise(stats.manaRegen))),
              _Line(S.statCooldown, percent(-stats.cooldownReduction),
                  hint: stats.cooldownReduction <= 0.0
                      ? S.statCooldownAbout
                      : null),
              _Line(S.statLeech, percent(stats.leech),
                  hint: stats.leech <= 0.0
                      ? null
                      : S.statLeechAbout),
            ]),

            _Group(S.statsGroupLoot, [
              _Line(S.statLootQuality, percent(stats.lootQuality),
                  hint: S.statLootQualityAbout),
              _Line(S.statLootQuantity, percent(stats.lootQuantity)),
              _Line(S.statGoldFind, percent(stats.goldFind)),
            ]),

            if (stats.tagDamage.entries.any((e) => e.value.abs() > 0.001)) ...[
              const SizedBox(height: 4),
              _GroupTitle(S.statsGroupTags),
              const SizedBox(height: 6),
              Text(
                S.statsTagsAbout,
                style: TextStyle(fontSize: 13.5, color: RiftColors.inkFaint),
              ),
              const SizedBox(height: 10),
              for (final e in _sortedTags(stats))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: TagChips(tags: [e.key])),
                      Text(
                        percent(e.value),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<MapEntry<Tag, double>> _sortedTags(StatBlock stats) => [
        for (final e in stats.tagDamage.entries)
          if (e.value.abs() > 0.001) e,
      ]..sort((a, b) => b.value.compareTo(a.value));

  String? _armorHint(double armor) {
    if (armor <= 0.0) return S.statsNoArmor;
    final cut = balance.Curves.armorMitigation(armor, depth);
    final capped = cut >= balance.Curves.armorDrCap - 1e-9;
    return S.statsPhysicalCut(percent(cut), capped: capped);
  }

  String? _resistHint(double value) {
    if (value <= 0.0) return null;
    final capped = value >= balance.Curves.resistCap;
    final applied = capped ? balance.Curves.resistCap : value;
    return S.statsDamageCut(percent(applied / 100.0), capped: capped);
  }

  String? _critHint(StatBlock stats) {
    if (stats.critChance <= 0.0) return S.statsNoCrits;
    final average = 1.0 + stats.critChance * stats.critMulti;
    return S.statsAverageCrit(average.toStringAsFixed(2));
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.lines, {this.note});

  final String title;
  final List<_Line> lines;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupTitle(title),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            decoration: BoxDecoration(
              color: RiftColors.raised,
              borderRadius: BorderRadius.circular(RiftSize.radiusSmall + 2),
              border: Border.all(color: RiftColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
          if (note case final text?) ...[
            const SizedBox(height: 6),
            Text(text, style: RiftText.caption),
          ],
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: RiftText.overline,
      );
}

/// Строка «название — значение», под ней при необходимости расшифровка.
///
/// Название и значение стоят в одной строке и оба переносятся: при крупном
/// системном шрифте «Восстановление маны» и число иначе выдавили бы друг
/// друга за край.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.hint, this.tag});

  final String label;
  final String value;
  final String? hint;
  final Tag? tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(label, style: RiftText.body.copyWith(fontSize: 14.5)),
              ),
              const SizedBox(width: 12),
              // Значение гибкое: строки стоят в карточке с внутренним отступом,
              // и на узком экране с крупным шрифтом «4.00 удара в секунду»
              // выдавливало подпись за край.
              Expanded(
                flex: 2,
                child: Text(
                value,
                textAlign: TextAlign.right,
                style: RiftText.number.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: tag == null ? RiftColors.ink : tagColor(tag!),
                ),
              ),
              ),
            ],
          ),
          if (hint case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(text, style: RiftText.caption),
            ),
        ],
      ),
    );
  }
}
