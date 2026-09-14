import 'package:flutter/material.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';

import 'gear_icons.dart';
import 'theme.dart';

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
///
/// Обычная вещь была тёмно-серой (`0xFF8A7F77`) — тем же цветом, что и рамка
/// пустого слота. На пробе это и сломалось: беглым взглядом по сетке нельзя
/// было сказать, надет меч или слот пуст. Цвет обычного поднят до светлого
/// пепельного, а «пусто» уведено в цвет фона (см. [_Cell]): разница обязана
/// читаться не вглядыванием, а периферийным зрением.
Color colorFor(Rarity rarity) => switch (rarity) {
      Rarity.common => const Color(0xFFC4B6A8),
      Rarity.uncommon => const Color(0xFF7FB069),
      Rarity.rare => const Color(0xFF4F8FC7),
      Rarity.relic => const Color(0xFFC7643F),
    };

/// Рамка пустого слота: почти фон. Ровно настолько видима, чтобы сетка
/// читалась сеткой, и не настолько, чтобы спорить с надетой вещью.
const _emptyOutline = Color(0x1FFFFFFF);

/// Иконка типа в пустом слоте — призрак.
const _emptyGlyph = Color(0x14FFFFFF);

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
    final accent = worn == null ? _emptyOutline : colorFor(worn.rarity);
    final size = compact ? 44.0 : 62.0;

    return InkWell(
      onTap: blocked ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: size,
        // Занятый слот светится цветом редкости — заливка, рамка в полную
        // силу и иконка тем же цветом; пустой уходит в фон и держится на
        // одной еле заметной линии.
        //
        // Раньше разница была в полтона: рамка одного и того же тёмно-серого
        // при 0.5 и 0.9 прозрачности. Игрок на пробе сказал прямо — «не
        // понятно, есть там что-то в слоте или нет», — и это правда: ради
        // такого различения приходилось останавливаться и всматриваться в
        // каждую из девяти клеток.
        decoration: BoxDecoration(
          color: worn == null
              ? Colors.white.withValues(alpha: 0.015)
              : accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: worn == null ? accent : accent.withValues(alpha: 0.95),
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
                      // Пустой слот показывает тип призраком: это подсказка
                      // «сюда — сапоги», а не вещь. На четверти белого призрак
                      // был ярче, чем надетая обычная вещь, и слоты читались
                      // наоборот.
                      color: worn == null ? _emptyGlyph : accent,
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
                    size: compact ? 12 : 16, color: RiftColors.inkFaint),
              ),
            if (worn != null)
              Positioned(
                right: 4,
                bottom: 2,
                child: Text(
                  '${worn.ilvl}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: RiftColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (worn?.twoHanded ?? false)
              const Positioned(
                left: 4,
                bottom: 2,
                child: Text('2H',
                    style: TextStyle(fontSize: 11, color: RiftColors.inkFaint)),
              ),
            if (worn?.triggerAffixId != null)
              Positioned(
                left: 4,
                top: 3,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: RiftColors.info,
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
