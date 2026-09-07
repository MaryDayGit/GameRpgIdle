import 'package:flutter/material.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/shard.dart';
import 'package:rift/core/sim/crafting.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'strings.dart';
import 'gear_grid.dart';
import 'help_screen.dart';
import 'gear_icons.dart';

/// Кузница: сундук, осколки и всё, что с ними делают.
///
/// Крафт — единственная часть игры, которая не устаревает вместе с предметами
/// (GDD §5.3), и потому он должен быть виден как отдельное место, а не как
/// пункт меню внутри инвентаря.
class ForgeScreen extends StatefulWidget {
  const ForgeScreen({super.key, required this.controller, this.focus});

  final GameController controller;

  /// Вещь, с которой игрок сюда пришёл. Кузница открывается сразу на ней:
  /// путь «нашёл вещь → хочу её улучшить» не должен упираться в список
  /// операций, среди которых надо ещё найти свою вещь.
  final Item? focus;

  @override
  State<ForgeScreen> createState() => _ForgeScreenState();
}

class _ForgeScreenState extends State<ForgeScreen> {
  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Игрок пришёл с вещью — открываем её, а не список. Первым кадром: до
    // него нет ни контекста для листа, ни собранного экрана под ним.
    final focus = widget.focus;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.profile.stash.contains(focus)) _openItem(focus);
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Предпросмотр перед оплатой.
  ///
  /// Крафт был непонятен ровно потому, что игрок платил, не зная, что
  /// получит: четыре операции с непрозрачными названиями и цена. Теперь любая
  /// операция сперва показывает «сейчас → станет» и только потом берёт деньги.
  Future<bool> _confirm({
    required String title,
    required String what,
    List<String> before = const [],
    List<String> after = const [],
    String? warning,
    double? cost,
    required String action,
  }) async {
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                what,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              if (before.isNotEmpty) ...[
                Text(
                  S.forgeNow,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                for (final line in before)
                  Text(line, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (after.isNotEmpty) ...[
                Text(
                  S.forgeBecomes,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                for (final line in after)
                  Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7FB069),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (warning != null) ...[
                Text(
                  warning,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD98F4E),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: cost != null && !c.canAfford(cost)
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: Text(cost == null ? action : '$action · ${money(cost)}'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(S.cancel),
              ),
            ],
          ),
        ),
      ),
    );
    return agreed ?? false;
  }

  /// Строка аффикса так, как её увидит игрок, — но с ДРУГИМ значением.
  ///
  /// Предпросмотр обязан говорить теми же словами, что и сама вещь: своё
  /// форматирование разошлось бы с настоящим, и «станет» показывало бы не то,
  /// что потом появится в карточке.
  String _affixLine(Item item, int index, AffixRoll roll) {
    final affixes = [...item.affixes]..[index] = roll;
    final lines = ItemText.lines(item.copyWith(affixes: affixes));
    return lines[index + (item.implicit == null ? 0 : 1)];
  }

  /// Перекат: единственная операция, у которой нет точного «станет».
  /// Показываются границы — и то, что нижняя может быть хуже нынешнего.
  Future<void> _reroll(Item item, int index) async {
    final floor = c.profile.outpost.rerollFloorPercentile;
    final range = Crafting.rerollRange(item, index, floorPercentile: floor);
    if (range == null) return;

    final current = item.affixes[index];
    final risky = range.worst.value < current.value;

    final ok = await _confirm(
      title: S.rerollTitle,
      what: S.rerollAbout,


      before: [
        _affixLine(item, index, current),
        S.qualityOutOf((current.percentile * 100).round()),
      ],
      after: [
        S.rerollNoWorse(_affixLine(item, index, range.worst)),
        S.rerollNoBetter(_affixLine(item, index, range.best)),
      ],
      warning: risky
          ? S.rerollRisk

          : S.rerollSafe,

      cost: Crafting.rerollCost(item, index),
      action: S.reroll,
    );
    if (!ok || !mounted) return;

    final result = c.rerollAffix(item, index);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result == null) {
      _toast(S.notEnoughGoldShort);
      return;
    }
    // Открываем ту же вещь заново: игрок пришёл смотреть, что выпало.
    await _openItem(result);
  }

  Future<void> _extract(Item item, int index) async {
    final shard = Crafting.extract(item, index);

    final ok = await _confirm(
      title: S.extractTitle,
      what: S.extractAbout,




      before: [_affixLine(item, index, item.affixes[index])],
      after: [S.shardOfQuality(shard.quality)],
      warning: S.extractLoseRest,
      action: S.extract,
    );
    if (!ok || !mounted) return;

    final result = c.extractShard(item, index);
    if (!mounted) return;
    Navigator.of(context).pop();
    _toast(
      result == null
          ? S.shardStorageFull
          : S.shardReady(result.quality),
    );
  }

  Future<void> _deepen(Item item) async {
    final next = Crafting.deepen(item, c.profile.maxDepthEver);

    final ok = await _confirm(
      title: S.deepenTitle,
      what: S.deepenAbout(next.ilvl),



      before: ItemText.lines(item),
      after: ItemText.lines(next),
      cost: Crafting.deepenCost(item),
      action: S.deepen,
    );
    if (!ok || !mounted) return;

    final result = c.deepenRelic(item);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result == null) {
      _toast(S.notEnoughGoldShort);
      return;
    }
    await _openItem(result);
  }

  Future<void> _openItem(Item item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ItemSheet(
        controller: c,
        item: item,
        onExtract: (index) => _extract(item, index),
        onReroll: (index) => _reroll(item, index),
        onDeepen: () => _deepen(item),
      ),
    );
    setState(() {});
  }

  Future<void> _openShard(Shard shard) async {
    final targets = [
      for (final item in c.profile.stash)
        if (Crafting.canImprint(item, shard)) item,
    ]..sort((a, b) => b.ilvl.compareTo(a.ilvl));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ShardSheet(
        shard: shard,
        targets: targets,
        onPick: (item) async {
          Navigator.of(context).pop();
          await _imprintInto(item, shard);
        },
      ),
    );
    setState(() {});
  }

  Future<void> _imprintInto(Item item, Shard shard) async {
    if (Crafting.hasFreeSlot(item)) {
      // Осколок хранит перцентиль, а не число, и под уровень новой вещи
      // пересчитывается. Показать это до впечатывания важнее всего: именно
      // здесь видно, зачем осколок вообще носили через раны.
      final preview = Crafting.imprint(item, shard);
      final added = preview.item.affixes.last;

      final ok = await _confirm(
        title: S.imprintTitle,
        what: S.imprintAbout,


        before: [
          ItemText.title(item),
          S.shardQualityShort(shard.quality),
        ],
        after: [
          ItemText.lines(preview.item)[preview.item.affixes.length -
              1 +
              (item.implicit == null ? 0 : 1)],
        ],
        action: S.imprint,
      );
      if (!ok || !mounted) return;

      final result = c.imprintShard(item, shard);
      _toast(
        result == null
            ? S.didNotFit
            : S.imprinted((added.percentile * 100).round()),
      );
      setState(() {});
      return;
    }

    // Свободных слотов нет — значит перезапись, и выбирает игрок. Молча
    // затереть первый попавшийся аффикс нельзя: это его вещь.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OverwriteSheet(
        item: item,
        shard: shard,
        onPick: (index) async {
          Navigator.of(context).pop();
          await _overwrite(item, shard, index);
        },
      ),
    );
    setState(() {});
  }

  /// Перезапись — самая опасная операция крафта: аффикс исчезает навсегда,
  /// и шанс его спасти даёт только Верстак. Поэтому здесь показывается и то,
  /// что появится, и то, что пропадёт.
  Future<void> _overwrite(Item item, Shard shard, int index) async {
    final preview = Crafting.imprint(item, shard, slotIndex: index);
    final offset = item.implicit == null ? 0 : 1;
    final chance = c.profile.outpost.shardSalvageOnOverwrite;

    final ok = await _confirm(
      title: S.replaceTitle,
      what: S.replaceNoRoom,
      before: [_affixLine(item, index, item.affixes[index])],
      after: [ItemText.lines(preview.item)[index + offset]],
      warning: chance > 0
          ? S.replaceSaveChance((chance * 100).round())
  
          : S.replaceNoChance,
  
      action: S.replace,
    );
    if (!ok || !mounted) return;

    final result = c.imprintShard(item, shard, slotIndex: index);
    _toast(result == null ? S.didNotFit : S.propertyReplaced);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final profile = c.profile;
        final stash = [...profile.stash]
          ..sort((a, b) => b.ilvl.compareTo(a.ilvl));

        return Scaffold(
          appBar: AppBar(
            title: Text(S.forgeTitle),
            actions: [
              // Справка открывается сразу на крафте: в Кузницу приходят с
              // вопросом про перекат, а не про цикл игры.
              IconButton(
                tooltip: S.howItWorks,
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => openHelp(context, section: 'craft'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                S.goldAmount(money(profile.gold)),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              _Header(
                S.shardsHeader(profile.shards.length,
                    profile.outpost.shardCapacity),

              ),
              if (profile.shards.isEmpty)
                Text(
                  S.shardsEmptyAbout,



                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                )
              else
                for (final shard in profile.shards)
                  _ShardRow(shard: shard, onTap: () => _openShard(shard)),

              const SizedBox(height: 24),
              _Header(
                S.stashHeader(stash.length, profile.outpost.stashSlots),

              ),
              if (stash.isEmpty)
                Text(
                  S.stashEmptyForge,
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                )
              else
                for (final item in stash)
                  _ItemRow(item: item, onTap: () => _openItem(item)),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        color: Colors.white54,
      ),
    ),
  );
}

class _ShardRow extends StatelessWidget {
  const _ShardRow({required this.shard, required this.onTap});

  final Shard shard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final def = ContentPack.current.statAffix(shard.affixId);
    // Значение осколка зависит от предмета, в который его впечатают, поэтому
    // на месте числа стоит многоточие. Вырезать число совсем было хуже:
    // строки читались обрывками — «к урону», «вампиризма».
    final title = def == null
        ? shard.stat.label
        : def.template
              .replaceAll('{value:%}', '… %')
              .replaceAll('{value}', '…')
              .replaceAll('{tag}', shard.tag?.title ?? '');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Quality(shard.quality),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Перцентиль — то, чем осколок ценен. Показывается крупно и всегда.
class _Quality extends StatelessWidget {
  const _Quality(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    final good = value >= 90;
    return Container(
      width: 40,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (good ? const Color(0xFFC7643F) : const Color(0xFF4F8FC7))
            .withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: good ? const Color(0xFFE0A183) : const Color(0xFF8FB8DC),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            GearIcon(kind: item.kind, size: 20, color: colorFor(item.rarity)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ItemText.title(item),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    S.propertyCount(Crafting.usedSlots(item),
                        Crafting.affixCapacity(item),
                        relic: item.isRelic),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
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

class _ItemSheet extends StatelessWidget {
  const _ItemSheet({
    required this.controller,
    required this.item,
    required this.onExtract,
    required this.onReroll,
    required this.onDeepen,
  });

  final GameController controller;
  final Item item;
  final void Function(int index) onExtract;
  final void Function(int index) onReroll;
  final VoidCallback onDeepen;

  @override
  Widget build(BuildContext context) {
    final lines = ItemText.lines(item);
    final offset = item.implicit == null ? 0 : 1;
    final canDeepen = Crafting.canDeepen(item, controller.profile.maxDepthEver);

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
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (item.implicit != null) ...[
              const SizedBox(height: 6),
              Text(
                lines.first,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
            const SizedBox(height: 16),

            for (var i = 0; i < item.affixes.length; i++) ...[
              Text(lines[i + offset], style: const TextStyle(fontSize: 13)),
              Text(
                S.affixQuality((item.affixes[i].percentile * 100).round(),
                    item.affixes[i].rerolls),
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton(
                    // Без цены: цену показывает предпросмотр операции, и
                    // одно и то же число на двух кнопках подряд читается как
                    // «я уже заплатил».
                    onPressed: () => onReroll(i),
                    child: Text(S.reroll),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => onExtract(i),
                    child: Text(S.toShard),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (canDeepen)
              FilledButton(
                onPressed: onDeepen,
                child: Text(S.deepenTo(item.ilvl + 10)),
              ),
            if (item.isRelic && !canDeepen)
              Text(
                S.deepenGate,
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShardSheet extends StatelessWidget {
  const _ShardSheet({
    required this.shard,
    required this.targets,
    required this.onPick,
  });

  final Shard shard;
  final List<Item> targets;
  final void Function(Item) onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              S.shardOfQuality(shard.quality),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              S.shardRecomputeNote,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),
            if (targets.isEmpty)
              Text(
                S.noSuitableItems,
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              )
            else
              for (final item in targets)
                InkWell(
                  onTap: () => onPick(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        GearIcon(
                          kind: item.kind,
                          size: 18,
                          color: colorFor(item.rarity),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ItemText.title(item),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          Crafting.hasFreeSlot(item)
                              ? S.freeSlot
                              : S.overwrite,
                          style: TextStyle(
                            fontSize: 11,
                            color: Crafting.hasFreeSlot(item)
                                ? const Color(0xFF7FB069)
                                : Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _OverwriteSheet extends StatelessWidget {
  const _OverwriteSheet({
    required this.item,
    required this.shard,
    required this.onPick,
  });

  final Item item;
  final Shard shard;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final lines = ItemText.lines(item);
    final offset = item.implicit == null ? 0 : 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.whatToErase,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              S.replaceNoRoomAny,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            for (var i = 0; i < item.affixes.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  lines[i + offset],
                  style: const TextStyle(fontSize: 13),
                ),
                // Каждая строка показывает не только что пропадёт, но и что
                // встанет на это место: выбирать «что стереть», не видя, на
                // что меняешь, — это выбор вслепую.
                subtitle: Text(
                  S.becomes(ItemText.lines(
                      Crafting.imprint(item, shard, slotIndex: i)
                          .item)[i + offset]),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7FB069),
                  ),
                ),
                onTap: () => onPick(i),
              ),
          ],
        ),
      ),
    );
  }
}
