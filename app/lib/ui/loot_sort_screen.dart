import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'help_screen.dart';

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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Разбор добычи'),
            actions: [
              IconButton(
                tooltip: 'Как это работает',
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
                        label: 'Всё',
                        selected: filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final kind in GearKind.values)
                        if (kinds.contains(kind))
                          _Chip(
                            label: kind.ru,
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
                  itemBuilder: (context, i) => _LootRow(
                    item: shown[i],
                    // Место в сундуке кончилось — «оставить» перестаёт быть
                    // доступным, и это надо показать до нажатия, а не после.
                    canKeep: room > 0,
                    salvage: c.profile.salvageValue(shown[i]),
                    onKeep: () => setState(() => c.keepLoot(shown[i])),
                    onMelt: () => setState(() => c.meltLoot(shown[i])),
                    onSell: () => setState(() => c.sellLoot(shown[i])),
                  ),
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
                      child: const Text('Готово'),
                    )
                  : OutlinedButton(
                      onPressed: () => setState(c.autoSortLoot),
                      child: Text(
                        'Разобрать остальное за меня · '
                        '${plural(loot.length, "вещь", "вещи", "вещей")}',
                      ),
                    ),
            ),
          ),
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
            'Наёмник донёс ${plural(pending, "вещь", "вещи", "вещей")}. '
            '${tight ? "Сундук полон" : "В сундуке свободно $room"}.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            tight
                ? 'Освободите место в сундуке или решите судьбу вещей здесь.'
                : 'Переплавка даёт золото и осколок, продажа — только золото, '
                    'но больше.',
            style: TextStyle(
              fontSize: 12,
              color: tight ? Colors.orangeAccent : Colors.white38,
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
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
        side: BorderSide(
          color: selected ? accent : Colors.white24,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ItemText.title(item),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (item.isRelic)
                const _Tag(text: 'реликт', color: Color(0xFFC7643F)),
              if (trigger != null)
                const _Tag(text: 'триггер', color: Color(0xFF4F7FA8)),
            ],
          ),
          const SizedBox(height: 2),
          // Строки предмета целиком: решение принимается по ним, и прятать их
          // за нажатием значит просить игрока выбирать вслепую.
          for (final line in ItemText.lines(item))
            Text(line,
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: canKeep ? onKeep : null,
                  child: const Text('Оставить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onMelt,
                  child: Text('Переплавить\n${money(salvage)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSell,
                  child: Text(
                    'Продать\n${money(salvage * Tuning.sellBonus)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10, color: Colors.white70)),
      );
}
