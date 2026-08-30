import 'package:flutter/material.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/abilities.dart';

import 'format.dart';
import 'mercenary_screen.dart' show TagChips, tagColor;

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
            Text('Характеристики',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${mercenary.name} · всё, с чем '
              '${mercenary.gender == Gender.feminine ? 'она' : 'он'} '
              'уйдёт вниз. Проценты посчитаны для глубины $depth.',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 18),

            _Group('Живучесть', [
              _Line('Максимум HP', money(stats.maxHp)),
              _Line('Восстановление HP',
                  '${precise(stats.hpRegen)} в секунду',
                  hint: stats.hpRegen <= 0.0
                      ? 'Между этажами наёмник всё равно отдыхает'
                      : null),
              _Line(
                'Броня',
                money(stats.armor),
                hint: _armorHint(stats.armor),
              ),
            ]),

            _Group('Сопротивления', [
              for (final (name, value, tag) in [
                ('Огню', stats.resistFire, Tag.fire),
                ('Холоду', stats.resistCold, Tag.cold),
                ('Молнии', stats.resistLightning, Tag.lightning),
                ('Пустоте', stats.resistVoid, Tag.voidTag),
              ])
                _Line(name, money(value), hint: _resistHint(value), tag: tag),
            ], note: 'Физический урон режет броня, стихийный — сопротивления. '
                'Потолок сопротивления — ${balance.Curves.resistCap.round()}.'),

            _Group('Урон', [
              _Line('Урон оружия', money(stats.attackDamage),
                  hint: 'От него растут умения с тегом «Атака» и автоатака'),
              _Line('Сила чар', money(stats.spellPower),
                  hint: 'От неё растут умения с тегом «Чары». Автоатака — нет'),
              _Line('Увеличение урона', percent(stats.increasedDamage)),
              // Поправка может быть и отрицательной — черта «Погорелица»
              // забирает скорость. «база 1.20 и -10 % сверху» читалось как
              // опечатка, поэтому знак называется словом.
              _Line('Скорость атаки',
                  '${stats.effectiveAttackSpeed.toStringAsFixed(2)} уд/с',
                  hint: stats.increasedAttackSpeed == 0.0
                      ? null
                      : 'база ${stats.attackSpeed.toStringAsFixed(2)}, '
                          '${stats.increasedAttackSpeed > 0 ? "сверху" : "минус"} '
                          '${percent(stats.increasedAttackSpeed.abs())}'),
              _Line('Шанс крита', percent(stats.critChance)),
              _Line('Множитель крита', '×${(1.0 + stats.critMulti).toStringAsFixed(2)}',
                  hint: _critHint(stats)),
            ]),

            _Group('Способности', [
              _Line('Запас маны', money(stats.maxMana),
                  hint: reserved <= 0.0
                      ? null
                      : 'ауры держат занятыми ${percent(reserved)}'),
              _Line('Восстановление маны',
                  '${precise(stats.manaRegen)} в секунду'),
              _Line('Перезарядка', percent(-stats.cooldownReduction),
                  hint: stats.cooldownReduction <= 0.0
                      ? 'Умения перезаряжаются за своё время'
                      : null),
              _Line('Вампиризм', percent(stats.leech),
                  hint: stats.leech <= 0.0
                      ? null
                      : 'доля нанесённого урона возвращается здоровьем'),
            ]),

            _Group('Добыча', [
              _Line('Качество добычи', percent(stats.lootQuality),
                  hint: 'Сдвигает выпадение к старшим редкостям'),
              _Line('Количество добычи', percent(stats.lootQuantity)),
              _Line('Находимое золото', percent(stats.goldFind)),
            ]),

            if (stats.tagDamage.entries.any((e) => e.value.abs() > 0.001)) ...[
              const SizedBox(height: 4),
              const _GroupTitle('Множители по тегам'),
              const SizedBox(height: 6),
              const Text(
                'Работают только на умениях с этим тегом — и на автоатаке, '
                'если её тег совпал.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
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
                          fontSize: 13,
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
    if (armor <= 0.0) return 'Брони нет — физический урон приходит целиком';
    final cut = balance.Curves.armorMitigation(armor, depth);
    final capped = cut >= balance.Curves.armorDrCap - 1e-9;
    return 'Физический урон меньше на ${percent(cut)}'
        '${capped ? ' — это потолок' : ''}';
  }

  String? _resistHint(double value) {
    if (value <= 0.0) return null;
    final capped = value >= balance.Curves.resistCap;
    final applied = capped ? balance.Curves.resistCap : value;
    return 'Урон меньше на ${percent(applied / 100.0)}'
        '${capped ? ' — выше потолка не считается' : ''}';
  }

  String? _critHint(StatBlock stats) {
    if (stats.critChance <= 0.0) return 'Критов нет — множитель ни на что';
    final average = 1.0 + stats.critChance * stats.critMulti;
    return 'В среднем ×${average.toStringAsFixed(2)} по всему урону';
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupTitle(title),
          const SizedBox(height: 8),
          ...lines,
          if (note case final text?) ...[
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
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
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          color: Colors.white54,
          fontWeight: FontWeight.w600,
        ),
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
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tag == null ? Colors.white : tagColor(tag!),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (hint case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}
