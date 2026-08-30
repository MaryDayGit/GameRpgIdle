import 'package:flutter/material.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';

import 'gear_icons.dart';

/// Снаряжение героя одной картинкой.
///
/// Девять слотов списком читаются как таблица: чтобы понять, чего не хватает,
/// приходится прочитать девять строк. Сетка отвечает на этот вопрос взглядом —
/// пустой слот виден сразу, а редкость читается по цвету рамки.
class GearGrid extends StatelessWidget {
  const GearGrid({
    super.key,
    required this.equipment,
    this.onTapSlot,
    this.compact = false,
  });

  final Equipment equipment;

  /// `null` — сетка только для просмотра (карточка наёмника).
  final void Function(int slot)? onTapSlot;

  final bool compact;

  /// Расстановка по трём колонкам: руки по краям, тело в середине.
  /// Порядок в [Equipment.slotKinds] другой — он про сейв, а не про глаз.
  static const List<List<int>> layout = [
    [0, 2, 1],
    [4, 3, 5],
    [6, 8, 7],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in layout)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (final slot in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _Cell(
                        slot: slot,
                        item: equipment.at(slot),
                        blocked: slot == 1 && !equipment.offhandUsable,
                        compact: compact,
                        onTap: onTapSlot == null ? null : () => onTapSlot!(slot),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Иконка типа предмета. Своя, а не из системного набора: рядом с плоскими
/// силуэтами боя контурные глифы Material выглядели вставкой из другой игры
/// (см. `gear_icons.dart`).

/// Цвет редкости. Единственный способ отличить находки друг от друга взглядом,
/// пока иконки одинаковые для всего слота.
Color colorFor(Rarity rarity) => switch (rarity) {
      Rarity.common => const Color(0xFF8A7F77),
      Rarity.uncommon => const Color(0xFF7FB069),
      Rarity.rare => const Color(0xFF4F8FC7),
      Rarity.relic => const Color(0xFFC7643F),
    };

class _Cell extends StatelessWidget {
  const _Cell({
    required this.slot,
    required this.item,
    required this.blocked,
    required this.compact,
    this.onTap,
  });

  final int slot;
  final Item? item;
  final bool blocked;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = Equipment.slotKinds[slot];
    final worn = item;
    final accent = worn == null ? const Color(0xFF3A312D) : colorFor(worn.rarity);
    final size = compact ? 44.0 : 62.0;

    return InkWell(
      onTap: blocked ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: worn == null ? 0.02 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withValues(alpha: worn == null ? 0.5 : 0.9),
            width: worn == null ? 1 : 1.5,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: blocked
                  ? _BlockedSlot(size: compact ? 18 : 24)
                  : GearIcon(
                      kind: kind,
                      size: compact ? 20 : 28,
                      color: worn == null ? Colors.white24 : accent,
                    ),
            ),
            // Пустой слот, на который можно нажать, помечен плюсом. Одна
            // иконка типа слота выглядит картинкой, а не кнопкой: игрок не
            // догадывался, что по клеткам вообще жмут.
            if (worn == null && !blocked && onTap != null)
              Positioned(
                right: 4,
                bottom: 2,
                child: Icon(Icons.add,
                    size: compact ? 12 : 16, color: Colors.white38),
              ),
            if (worn != null)
              Positioned(
                right: 4,
                bottom: 2,
                child: Text(
                  '${worn.ilvl}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (worn?.twoHanded ?? false)
              const Positioned(
                left: 4,
                bottom: 2,
                child: Text('2H',
                    style: TextStyle(fontSize: 9, color: Colors.white38)),
              ),
            if (worn?.triggerAffixId != null)
              Positioned(
                left: 4,
                top: 3,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4F8FC7),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Слот, недоступный из-за двуручника. Своя форма, а не системный «запрет»:
/// перечёркнутый круг Material выбивался из ряда сильнее всех.
class _BlockedSlot extends StatelessWidget {
  const _BlockedSlot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BlockedPainter()),
      );
}

class _BlockedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintBlockedSlot(
        canvas: canvas,
        size: size.shortestSide,
        color: const Color(0x33FFFFFF),
      );

  @override
  bool shouldRepaint(_BlockedPainter oldDelegate) => false;
}
