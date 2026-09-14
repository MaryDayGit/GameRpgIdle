import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';

import '../state/game_controller.dart';
import 'coach_mark.dart';
import 'format.dart';
import 'gear_grid.dart';
import 'gear_icons.dart';
import 'onboarding.dart';
import 'strings.dart';
import 'tutorial_host.dart';
import 'help_screen.dart';
import 'theme.dart';

/// Разбор добычи: что из принесённого достойно места в сундуке.
///
/// Существует потому, что рюкзак наёмника стал бесконечным, а сундук — нет.
/// Раньше выбор «что оставить» делали два автомата: наёмник выбрасывал из
/// рюкзака худшее по уровню, а сундук переплавлял всё, что не влезло. Оба
/// правила разумны и оба ошибались одинаково — они не знают, какая вещь нужна
/// СБОРКЕ. Единственная вещь с нужным тегом вполне может быть худшей по
/// уровню.
///
/// Теперь наёмник несёт наверх всё, а решает игрок. Это и есть то место, где
/// добыча превращается в замысел.
class LootSortScreen extends StatefulWidget {
  const LootSortScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<LootSortScreen> createState() => _LootSortScreenState();
}

class _LootSortScreenState extends State<LootSortScreen> {
  GameController get c => widget.controller;

  /// Показывать только то, что влезет в сборку по виду снаряжения.
  GearKind? _filter;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final loot = c.profile.pendingLoot;
        final room = c.profile.stashRoom;

        final kinds = {for (final item in loot) item.kind};
        // Разобрав последнюю вещь своего вида, фильтр остаётся без строчки в
        // ряду — и экран становится пустым без объяснения, с непонятно чем
        // выбранным. Возвращаемся ко «Всему»: пустой список тут значит
        // «разобрано», а не «отфильтровано».
        final filter = kinds.contains(_filter) ? _filter : null;
        final shown = filter == null
            ? loot
            : [for (final item in loot) if (item.kind == filter) item];

        final scaffold = Scaffold(
          appBar: AppBar(
            title: Text(S.lootSortTitle),
            actions: [
              IconButton(
                tooltip: S.howItWorks,
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => openHelp(context, section: 'loot'),
              ),
            ],
          ),
          body: Column(
            children: [
              _Summary(pending: loot.length, room: room),
              if (kinds.length > 1)
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _Chip(
                        label: S.filterAll,
                        selected: filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final kind in GearKind.values)
                        if (kinds.contains(kind))
                          _Chip(
                            label: kind.title,
                            selected: filter == kind,
                            onTap: () => setState(() => _filter = kind),
                          ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final row = _LootRow(
                      item: shown[i],
                      // Место в сундуке кончилось — «оставить» перестаёт быть
                      // доступным, и это надо показать до нажатия, а не после.
                      canKeep: room > 0,
                      salvage: c.profile.salvageValue(shown[i]),
                      onKeep: () => setState(() => c.keepLoot(shown[i])),
                      onMelt: () => setState(() => c.meltLoot(shown[i])),
                      onSell: () => setState(() => c.sellLoot(shown[i])),
                    );
                    // Обучение указывает на первую находку: три кнопки под
                    // ней и есть весь разбор, объяснять их по второй строке
                    // нечего.
                    return i == 0
                        ? TutorialAnchor(
                            id: Onboarding.anchorLootRow, child: row)
                        : row;
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              // Экран закрывается кнопкой, а не сам.
              //
              // Первая версия закрывалась сама, как только разбирать станет
              // нечего. Закрытие вешалось на пост-кадровый вызов при каждой
              // перерисовке — а перерисовок после разбора две (setState и
              // оповещение контроллера), и второе закрытие снимало уже
              // следующий экран: окно с наградой за задание.
              child: loot.isEmpty
                  ? FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(S.done),
                    )
                  : OutlinedButton(
                      onPressed: () => setState(c.autoSortLoot),
                      child: Text(
                        S.lootSortRest(loot.length),

                      ),
                    ),
            ),
          ),
        );

        return TutorialHost(
          controller: c,
          screen: TutorialScreen.loot,
          child: scaffold,
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.pending, required this.room});

  final int pending;
  final int room;

  @override
  Widget build(BuildContext context) {
    final tight = room <= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.lootBrought(pending, room, tight: tight),
            style: RiftText.heading,
          ),
          const SizedBox(height: 2),
          Text(
            tight
                ? S.lootSortTight
                : S.lootSortAbout,

            style: TextStyle(
              fontSize: 13.5,
              color: tight ? RiftColors.bad : RiftColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? RiftColors.ember : RiftColors.inkMuted,
            )),
        onPressed: onTap,
        backgroundColor: selected
            ? RiftColors.ember.withValues(alpha: 0.12)
            : RiftColors.raised,
        side: BorderSide(
          color: selected ? RiftColors.ember : RiftColors.line,
        ),
      ),
    );
  }
}

/// Одна находка и три решения.
class _LootRow extends StatelessWidget {
  const _LootRow({
    required this.item,
    required this.canKeep,
    required this.salvage,
    required this.onKeep,
    required this.onMelt,
    required this.onSell,
  });

  final Item item;
  final bool canKeep;

  /// Сколько золота даст переплавка. Продажа даёт больше на [Tuning.sellBonus].
  final double salvage;

  final VoidCallback onKeep;
  final VoidCallback onMelt;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final trigger = item.triggerAffixId == null
        ? null
        : ContentPack.current.triggerAffix(item.triggerAffixId!);

    // Каждая находка — карточкой: три кнопки под списком свойств без рамки
    // читались продолжением соседней вещи, и «Оставить» нажимали не той.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: RiftColors.surface,
        borderRadius: BorderRadius.circular(RiftSize.radius),
        border: Border.all(color: RiftColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ItemPlaque(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ItemText.title(item),
                  style: RiftText.heading.copyWith(
                      fontSize: 15, color: colorFor(item.rarity)),
                ),
              ),
              if (item.isRelic)
                _Tag(text: S.relicMark, color: RiftColors.ember),
              if (trigger != null)
                _Tag(text: S.triggerMark, color: RiftColors.info),
            ],
          ),
          const SizedBox(height: 8),
          // Строки предмета целиком: решение принимается по ним, и прятать их
          // за нажатием значит просить игрока выбирать вслепую.
          for (final line in ItemText.lines(item))
            Text(line, style: RiftText.small),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: canKeep ? onKeep : null,
                  child: Text(S.keep),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onMelt,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RiftColors.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text(S.salvageFull(money(salvage)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSell,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RiftColors.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text(
                    S.sellFor(money(salvage * Tuning.sellBonus)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}

/// Иконка вещи в плашке цвета редкости — тот же вид, что в сундуке.
class _ItemPlaque extends StatelessWidget {
  const _ItemPlaque({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final color = colorFor(item.rarity);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(RiftSize.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: GearIcon(kind: item.kind, size: 24, color: color),
    );
  }
}
