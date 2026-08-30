import 'package:flutter/material.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/sim/crafting.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/mercenary.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'forge_screen.dart';
import 'gear_grid.dart';
import 'gear_icons.dart';

/// Сундук Заставы — всё, что наёмники донесли.
///
/// До этого экрана вещи было видно только изнутри Кузницы и изнутри сборки
/// билда, то есть только тогда, когда игрок уже пришёл что-то с ними делать.
/// Посмотреть, что у тебя вообще есть, было негде — а это первое, что игрок
/// хочет сделать после спуска.
///
/// Экран отвечает на три вопроса подряд: что у меня есть → что это за вещь →
/// что я могу с ней сделать. Действия живут в карточке вещи, а не отдельным
/// списком операций: игрок приходит с вещью, а не с намерением «перекатать».
class StashScreen extends StatefulWidget {
  const StashScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<StashScreen> createState() => _StashScreenState();
}

class _StashScreenState extends State<StashScreen> {
  GameController get c => widget.controller;

  /// Показывать только вещи под этот слот. `null` — все.
  GearKind? _filter;

  /// Вещи в порядке чтения: сперва то, что лучше.
  ///
  /// Сортировка по уровню, а не по времени находки: сундук — это склад, и
  /// игрок ищет в нём лучшее, а не последнее.
  List<Item> get _items {
    final items = [
      for (final item in c.profile.stash)
        if (_filter == null || item.kind == _filter) item,
    ];
    items.sort((a, b) {
      final byRarity = b.rarity.index.compareTo(a.rarity.index);
      return byRarity != 0 ? byRarity : b.ilvl.compareTo(a.ilvl);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final items = _items;
        final total = c.profile.stash.length;
        final slots = c.profile.outpost.stashSlots;

        return Scaffold(
          appBar: AppBar(title: Text('Сундук · $total из $slots')),
          body: Column(
            children: [
              _Filters(
                current: _filter,
                kinds: {for (final item in c.profile.stash) item.kind},
                onPick: (kind) => setState(() => _filter = kind),
              ),
              if (total >= slots)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Сундук полон: лишнее с новой добычи уйдёт в золото. '
                    'Переплавьте ненужное или поднимите Хранилище.',
                    style: TextStyle(fontSize: 11, color: Color(0xFFD98F4E)),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Пусто. Вещи приносят наёмники.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, i) => _StashRow(
                          item: items[i],
                          onTap: () => _open(items[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(Item item) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => ItemSheet(
          item: item,
          controller: c,
          onEquip: (merc) => _equip(merc, item),
          onSalvage: () => _salvage(item),
          onForge: () {
            Navigator.of(context).pop();
            Navigator.of(this.context).push(MaterialPageRoute<void>(
              builder: (_) => ForgeScreen(controller: c, focus: item),
            ));
          },
        ),
      );

  void _equip(Mercenary merc, Item item) {
    // Свободный слот, если он есть: иначе надевание молча вытеснило бы уже
    // надетое, хотя рядом пустует второе кольцо.
    final slots = merc.gear.slotsFor(item.kind);
    final free = slots.where((s) => merc.gear.at(s) == null);
    final slot = free.isNotEmpty
        ? free.first
        : (slots.isEmpty ? null : slots.first);
    final ok = slot != null && c.equip(merc, slot, item);

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          // Двоеточие вместо согласования: «надето Перчатки» —
          // несогласованная строка, а «Надето: Перчатки» верна для
          // любого типа вещи.
          ? 'Надето: ${item.kind.ru} · ${merc.name}'
          : 'Не встало: ${merc.name} не может это надеть'),
    ));
  }

  void _salvage(Item item) {
    final gold = c.salvage(item);
    Navigator.of(context).pop();
    if (gold == null) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Переплавлено: ${item.kind.ru} · ${money(gold)}'),
    ));
  }
}

/// Полоса фильтров по типу вещи.
///
/// Появляется только тогда, когда типов больше одного: на первой добыче
/// фильтровать нечего, и пустой рычаг там был бы шумом.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.current,
    required this.kinds,
    required this.onPick,
  });

  final GearKind? current;
  final Set<GearKind> kinds;
  final void Function(GearKind?) onPick;

  @override
  Widget build(BuildContext context) {
    if (kinds.length < 2) return const SizedBox.shrink();

    final ordered = [
      for (final kind in GearKind.values)
        if (kinds.contains(kind)) kind,
    ];

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Chip(
            label: 'Всё',
            selected: current == null,
            onTap: () => onPick(null),
          ),
          for (final kind in ordered)
            _Chip(
              label: kind.ru,
              selected: current == kind,
              onTap: () => onPick(kind),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Строка сундука: что это, насколько хорошее, чем занято.
class _StashRow extends StatelessWidget {
  const _StashRow({required this.item, required this.onTap});

  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorFor(item.rarity);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            GearIcon(kind: item.kind, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.kind.ru,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: color),
                  ),
                  Text(
                    '${item.ilvl} ур. · ${item.rarity.ru} · свойств '
                    '${Crafting.usedSlots(item)} из '
                    '${Crafting.affixCapacity(item)}'
                    '${item.isRelic ? " · реликт" : ""}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Карточка вещи: аффиксы и что с ней можно сделать.
///
/// Общая для сундука и для всего, что покажет вещь дальше: два описания
/// одного предмета разошлись бы, и игрок увидел бы разные цифры в разных
/// местах.
class ItemSheet extends StatelessWidget {
  const ItemSheet({
    super.key,
    required this.item,
    required this.controller,
    this.onEquip,
    this.onSalvage,
    this.onForge,
  });

  final Item item;
  final GameController controller;
  final void Function(Mercenary merc)? onEquip;
  final VoidCallback? onSalvage;
  final VoidCallback? onForge;

  @override
  Widget build(BuildContext context) {
    final lines = ItemText.lines(item);
    final offset = item.implicit == null ? 0 : 1;
    // Надеть можно только на того, кто ещё на Заставе: лоадаут заперт с
    // момента отправки и до гибели.
    final wearers = controller.profile.roster.reserve;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              ItemText.title(item),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorFor(item.rarity),
              ),
            ),
            const SizedBox(height: 14),

            // Аффиксы — то, ради чего вещь и открывают.
            if (item.implicit != null) ...[
              Text(lines.first,
                  style: const TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < item.affixes.length; i++) ...[
              Text(lines[i + offset], style: const TextStyle(fontSize: 14)),
              Text(
                'качество ${(item.affixes[i].percentile * 100).round()}'
                '${item.affixes[i].rerolls > 0 ? " · перебросов ${item.affixes[i].rerolls}" : ""}',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 8),
            ],
            for (final line in lines.skip(offset + item.affixes.length)) ...[
              Text(line,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF9AA7D0))),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 8),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),

            if (onEquip != null)
              if (wearers.isEmpty)
                const Text(
                  'Надеть некому: наёмник в бездне, и снаряжение заперто до '
                  'его гибели.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                )
              else
                Wrap(
                  spacing: 8,
                  children: [
                    for (final merc in wearers)
                      FilledButton(
                        onPressed: () => onEquip!(merc),
                        child: Text(wearers.length == 1
                            ? 'Надеть'
                            : 'Надеть · ${merc.name}'),
                      ),
                  ],
                ),

            const SizedBox(height: 10),
            Row(
              children: [
                if (onForge != null)
                  OutlinedButton(
                    onPressed: onForge,
                    child: const Text('В Кузницу'),
                  ),
                const SizedBox(width: 8),
                if (onSalvage != null)
                  OutlinedButton(
                    onPressed: onSalvage,
                    child: Text('Переплавить · '
                        '${money(controller.profile.salvageValue(item))}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Переплавка уничтожает вещь и возвращает золото. Сколько '
              'именно — зависит от Алтаря.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
