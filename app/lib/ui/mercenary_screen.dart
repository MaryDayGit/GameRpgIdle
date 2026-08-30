import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/model/build_power.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';

import '../state/game_controller.dart';
import 'ability_detail.dart';
import 'mercenary_stats.dart';
import 'format.dart';
import 'gear_grid.dart';
import 'help_screen.dart';

/// Сборка билда: девять слотов снаряжения и четыре слота способностей.
///
/// Это пятый рычаг из GDD §1 и единственное место, где игрок принимает
/// решения о бою. Всё остальное за него делает наёмник.
class MercenaryScreen extends StatefulWidget {
  const MercenaryScreen({
    super.key,
    required this.controller,
    required this.mercenary,
  });

  final GameController controller;
  final Mercenary mercenary;

  @override
  State<MercenaryScreen> createState() => _MercenaryScreenState();
}

class _MercenaryScreenState extends State<MercenaryScreen> {
  GameController get c => widget.controller;
  Mercenary get m => widget.mercenary;

  /// Глубина, на которой сравниваются предметы. Рекорд игрока — честнее, чем
  /// первый этаж: сравнивать броню на глубине 1 бессмысленно, там её вклад
  /// почти нулевой.
  int get _depth =>
      c.profile.maxDepthEver < 10 ? 10 : c.profile.maxDepthEver;

  Future<void> _pickItem(int slot) async {
    final kind = Equipment.slotKinds[slot];
    final options = [
      for (final item in c.profile.stash)
        if (item.kind == kind) item,
    ]..sort((a, b) => _gain(b).compareTo(_gain(a)));

    final worn = m.gear.at(slot);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SlotSheet(
        title: kind.ru,
        worn: worn,
        options: options,
        gainOf: _gain,
        onEquip: (item) {
          c.equip(m, slot, item);
          Navigator.of(context).pop();
        },
        onUnequip: worn == null
            ? null
            : () {
                c.unequip(m, slot);
                Navigator.of(context).pop();
              },
      ),
    );
    setState(() {});
  }

  double _gain(Item item) =>
      m.gear.gainFrom(item, base: Tuning.heroBase, depth: _depth);

  Future<void> _pickAbility(int slot) async {
    final current = slot < m.abilities.length ? m.abilities[slot] : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AbilitySheet(
        // Не весь контент, а то, что открыто древом Эха: узлы «Отголоски»
        // иначе были бы текстом — список и так показывал всё.
        abilities: c.profile.availableAbilities,
        selected: m.abilities,
        current: current,
        stats: c.profile.heroProfileFor(m).aggregate(),
        // Теги, в которые сборка уже вложилась: отбор показывает их точкой,
        // и способность, попадающая во вложенное, видна сразу.
        highlight: {
          for (final e
              in c.profile.heroProfileFor(m).aggregate().tagDamage.entries)
            if (e.value > 0.001) e.key,
        },
        // Причина считается по сборке БЕЗ этого слота: заменяя активное
        // умение под «Венцом», игрок не должен упираться в самого себя.
        blockedReason: (def) => c.profile.abilityBlockedReason(
          m,
          def,
          loadout: [
            for (var i = 0; i < m.abilities.length; i++)
              if (i != slot) m.abilities[i],
          ],
        ),
        onPick: (id) {
          c.setAbility(m, slot, id);
          Navigator.of(context).pop();
        },
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final editable = c.canEdit(m);
        // Профиль собирает ПРОФИЛЬ ИГРОКА, а не экран: иначе «сила билда»
        // считается без обоих деревьев, и игрок сравнивает предметы по
        // числам, с которыми наёмник вниз не пойдёт.
        final stats = c.profile.heroProfileFor(m).aggregate();

        return Scaffold(
          appBar: AppBar(
            title: Text(m.name),
            actions: [
              // Справка открывается на разделе про сборку: игрок пришёл
              // собирать билд, а не читать про экономику Заставы.
              // Полный лист характеристик. Пять чисел в шапке отвечают на
              // «стало лучше или хуже», а перед спуском игрок спрашивает
              // другое: хватит ли брони, чем его убило в прошлый раз, куда
              // ушла мана.
              IconButton(
                tooltip: 'Характеристики',
                icon: const Icon(Icons.bar_chart_outlined),
                onPressed: () => MercenaryStatsSheet.show(
                  context,
                  mercenary: m,
                  profile: c.profile.heroProfileFor(m),
                  depth: _depth,
                ),
              ),
              IconButton(
                tooltip: 'Как это работает',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => openHelp(context, section: 'build'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                '${m.rank.forGender(m.gender)} · ${m.trait.forGender(m.gender)} · '
                'рюкзак ${m.backpackSlots}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 4),
              Text(
                m.trait.description,
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 16),

              // По строке статов тянет нажать — пусть она и открывает
              // полный лист, а не остаётся картинкой.
              InkWell(
                onTap: () => MercenaryStatsSheet.show(
                  context,
                  mercenary: m,
                  profile: c.profile.heroProfileFor(m),
                  depth: _depth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _StatsRow(
                    power: BuildPower.of(stats, _depth,
                        loadout: BuildPower.loadoutOf(m.abilities)),
                    hp: stats.maxHp,
                    damage: stats.attackDamage,
                    spellPower: stats.spellPower,
                    armor: stats.armor,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Нажмите, чтобы посмотреть сопротивления, ману и остальное',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 8),
              if (!editable)
                const Text(
                  'Наёмник в бездне — сборка заперта до конца контракта.',
                  style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                ),
              const SizedBox(height: 16),

              const _Header('Снаряжение'),
              Text(
                editable
                    ? 'Нажмите на слот, чтобы надеть предмет из сундука '
                        '(${c.profile.stash.length}). Что наденете — то и '
                        'уйдёт вниз; пустые слоты наёмник заполнит сам.'
                    : 'Наёмник ушёл с этим набором.',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 8),
              GearGrid(
                equipment: m.gear,
                onTapSlot: editable ? _pickItem : null,
              ),
              const SizedBox(height: 20),

              const _Header('Умения'),
              // Правило реликта — строкой над списком, а не сюрпризом при
              // нажатии: игрок должен понимать ограничение до того, как
              // упрётся в него.
              if (c.profile.abilityRuleNote(m) case final note?) ...[
                Text(
                  note,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.orangeAccent),
                ),
                const SizedBox(height: 8),
              ],
              _ManaBudget(profile: c.profile.heroProfileFor(m), mercenary: m),
              for (var slot = 0; slot < c.profile.abilitySlotsFor(m); slot++)
                _AbilityRow(
                  index: slot,
                  def: slot < m.abilities.length
                      ? ContentPack.current.ability(m.abilities[slot])
                      : null,
                  stats: stats,
                  onTap: editable ? () => _pickAbility(slot) : null,
                  highlight: {
                    for (final e in stats.tagDamage.entries)
                      if (e.value > 0.001) e.key,
                  },
                ),

              const SizedBox(height: 16),
              _TagPower(stats: stats, loadout: m.abilities),

              const SizedBox(height: 20),
              const _Header('Приказ на развилку'),
              _ForkOrder(
                policy: m.forkPolicy,
                onPick: editable
                    ? (policy) => c.setForkPolicy(m, policy)
                    : null,
              ),

              const SizedBox(height: 20),
              const _Header('Что надето'),
              for (var slot = 0; slot < Equipment.slotCount; slot++)
                _GearRow(
                  slot: slot,
                  item: m.gear.at(slot),
                  blocked: slot == 1 && !m.gear.offhandUsable,
                  onTap: editable ? () => _pickItem(slot) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.power,
    required this.hp,
    required this.damage,
    required this.spellPower,
    required this.armor,
  });

  final double power;
  final double hp;
  final double damage;

  /// Вторая ось силы. Стоит рядом с уроном оружия, а не прячется в списке
  /// аффиксов: от того, какая из двух больше, зависит, какие способности
  /// имеет смысл ставить в слоты.
  final double spellPower;
  final double armor;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white54)),
              Text(value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    return Row(
      children: [
        cell('Сила сборки', money(power)),
        cell('HP', money(hp)),
        cell('Урон', money(damage)),
        cell('Чары', money(spellPower)),
        cell('Броня', money(armor)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
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

class _AbilityRow extends StatelessWidget {
  const _AbilityRow({
    required this.index,
    required this.def,
    required this.stats,
    this.onTap,
    this.highlight = const {},
  });

  final int index;
  final AbilityDef? def;

  /// Статы сборки — для разбора в карточке способности.
  final StatBlock stats;

  final VoidCallback? onTap;

  /// Теги, по которым у сборки есть множитель.
  final Set<Tag> highlight;

  @override
  Widget build(BuildContext context) {
    final ability = def;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _SlotBadge(label: '${index + 1}'),
      title: Text(ability?.name ?? 'Пустой слот',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: ability == null ? Colors.white38 : null,
          )),
      subtitle: ability == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _abilityLine(ability),
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 4),
                TagChips(tags: ability.tags, highlight: highlight),
              ],
            ),
      // Две разные кнопки, а не одна: нажатие на строку меняет способность,
      // «i» — объясняет ту, что уже стоит. Смешать их значило бы заставить
      // игрока открывать список, чтобы прочитать про своё же умение.
      trailing: ability == null
          ? (onTap == null ? null : const Icon(Icons.chevron_right, size: 18))
          : IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              tooltip: 'Подробно',
              visualDensity: VisualDensity.compact,
              onPressed: () => AbilityDetailSheet.show(context,
                  def: ability, stats: stats),
            ),
      onTap: onTap,
    );
  }
}

/// Бюджет маны сборки: запас, восстановление и во что это обходится.
///
/// Мана — единственное, что связывает выбранные активки между собой:
/// поодиночке каждую ограничивает свой кулдаун, а вместе — общий бюджет.
/// Поэтому число тут не «сколько маны», а «хватает ли на то, что выбрано».
class _ManaBudget extends StatelessWidget {
  const _ManaBudget({required this.profile, required this.mercenary});

  final HeroProfile profile;
  final Mercenary mercenary;

  @override
  Widget build(BuildContext context) {
    final stats = profile.aggregate();

    // Расход в секунду по выбранным активкам: цена, делённая на перезарядку.
    var drain = 0.0;
    for (final def in profile.loadout) {
      if (def.isActive && def.cooldown > 0) {
        drain += def.manaCost / def.cooldown;
      }
    }

    // Резерв аур уже вычтен из собранного билда, поэтому запас показывается
    // и до, и после: иначе «мана 40» при базе 100 читается как потеря.
    final reserved = auraReservation(profile.loadout);
    final full = reserved <= 0.0 ? stats.maxMana : stats.maxMana / (1 - reserved);
    final ok = drain <= stats.manaRegen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reserved <= 0.0
                ? 'Мана ${stats.maxMana.toStringAsFixed(0)} · '
                    'восстановление ${stats.manaRegen.toStringAsFixed(1)}/с · '
                    'расход ${drain.toStringAsFixed(1)}/с'
                : 'Мана ${stats.maxMana.toStringAsFixed(0)} '
                    'из ${full.toStringAsFixed(0)} '
                    '(ауры держат ${(reserved * 100).round()} %) · '
                    'восстановление ${stats.manaRegen.toStringAsFixed(1)}/с · '
                    'расход ${drain.toStringAsFixed(1)}/с',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          Text(
            ok
                ? 'Маны хватает: умения не будут простаивать.'
                : 'Расход выше восстановления — в долгом бою умения '
                    'начнут простаивать. Запас маны держит первые секунды.',
            style: TextStyle(
              fontSize: 11,
              color: ok ? const Color(0xFF7FB069) : const Color(0xFFD98F4E),
            ),
          ),
        ],
      ),
    );
  }
}

String _abilityLine(AbilityDef def) {
  // Цена каста стоит рядом с кулдауном: это два ограничения одной и той же
  // способности, «как часто» и «сколько их сразу», и выбирать приходится по
  // обоим сразу.
  final kind = def.isActive
      ? 'Активное · ${def.cooldown.toStringAsFixed(0)} с · '
          '${def.manaCost.toStringAsFixed(0)} маны'
      : def.isAura
          // Резерв — главная цена ауры, и он обязан стоять там же, где у
          // активки стоит цена каста: игрок сравнивает их в одном месте.
          ? 'Аура · держит ${(def.manaReserve * 100).round()} % маны'
          : 'Пассивное';
  final text = TextTemplate.render(def.text, _params(def));
  return '$kind\n$text';
}

/// Теги способности — чипами, а не строкой через запятую.
///
/// Тег это то, за что цепляется снаряжение, и игрок читает его как ответ на
/// вопрос «что мне теперь искать в сундуке». Строка «Огонь, Чары, Область»
/// среди прочего текста таким ответом не выглядит.
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tags, this.highlight = const {}});

  final List<Tag> tags;

  /// Теги, по которым у сборки уже есть множитель. Они выделены: именно так
  /// видно, что способность попадает в то, во что игрок уже вложился.
  final Set<Tag> highlight;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: highlight.contains(tag)
                  ? tagColor(tag).withValues(alpha: 0.28)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: highlight.contains(tag)
                    ? tagColor(tag)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Text(
              tag.ru,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.2,
                color: highlight.contains(tag)
                    ? tagColor(tag)
                    : Colors.white54,
              ),
            ),
          ),
      ],
    );
  }
}

/// Цвет тега. Стихии красятся так же, как одноимённые лучи дерева пассивок:
/// игрок ищет глазами один и тот же огонь на двух экранах.
Color tagColor(Tag tag) => switch (tag) {
      Tag.fire => const Color(0xFFD9622B),
      Tag.cold => const Color(0xFF6FB6D6),
      Tag.lightning => const Color(0xFFC9A227),
      Tag.voidTag => const Color(0xFF8B5FB0),
      Tag.physical => const Color(0xFFC9C0B0),
      Tag.spell => const Color(0xFF4FA88B),
      Tag.attack => const Color(0xFFE0A87A),
      _ => const Color(0xFFA9A29A),
    };

/// Во что игрок вложился и попадает ли в это его сборка.
///
/// Экран сборки отвечал на вопрос «сколько у меня урона» и не отвечал на
/// вопрос «урона ЧЕМ». Пока теговые множители были не видны, найденный
/// «+18 % к урону Огнём» нечем было соотнести с выбранными умениями — и
/// подбирать снаряжение под способности было не по чему.
class _TagPower extends StatelessWidget {
  const _TagPower({required this.stats, required this.loadout});

  final StatBlock stats;
  final List<String> loadout;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<Tag, double>>[
      for (final e in stats.tagDamage.entries)
        if (e.value.abs() > 0.001) e,
    ]..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const Text(
        'Множителей по тегам пока нет. Они приходят с вещей, из дерева '
        'пассивок и от черты наёмника — и работают только на умениях с этим '
        'тегом.',
        style: TextStyle(fontSize: 12, color: Colors.white38),
      );
    }

    // Теги, которые сборка реально использует. Множитель по тегу, которого
    // нет ни в одной выбранной способности, — потраченный аффикс, и это
    // должно быть видно, а не подразумеваться.
    final used = <Tag>{};
    for (final id in loadout) {
      final def = ContentPack.current.ability(id);
      if (def != null) used.addAll(def.tags);
    }
    // Автоатака есть всегда, и её теги считаются наравне с остальными.
    used.addAll(const [Tag.attack, Tag.strike, Tag.physical]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header('Урон по тегам'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor(e.key)
                      .withValues(alpha: used.contains(e.key) ? 0.22 : 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${e.key.ru} +${(e.value * 100).round()} %',
                  style: TextStyle(
                    fontSize: 12,
                    color: used.contains(e.key)
                        ? tagColor(e.key)
                        : Colors.white30,
                  ),
                ),
              ),
          ],
        ),
        if (entries.any((e) => !used.contains(e.key))) ...[
          const SizedBox(height: 6),
          const Text(
            'Бледные теги не встречаются ни в одном выбранном умении — '
            'эти проценты сейчас ничего не дают.',
            style: TextStyle(fontSize: 11, color: Colors.white30),
          ),
        ],
      ],
    );
  }
}

Map<String, double> _params(AbilityDef def) => {
      for (final entry in def.params.raw.entries)
        if (entry.value is num) entry.key: (entry.value as num).toDouble(),
    };

class _GearRow extends StatelessWidget {
  const _GearRow({
    required this.slot,
    required this.item,
    required this.blocked,
    this.onTap,
  });

  final int slot;
  final Item? item;
  final bool blocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = Equipment.slotKinds[slot];
    final worn = item;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _SlotBadge(label: kind.ru.substring(0, 1)),
      title: Text(
        blocked ? '${kind.ru} — занята двуручным' : kind.ru,
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      subtitle: worn == null
          ? Text(blocked ? '—' : 'Пусто',
              style: const TextStyle(fontSize: 13, color: Colors.white38))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ItemText.title(worn),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                for (final line in ItemText.lines(worn))
                  Text(line,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60)),
              ],
            ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 18),
      onTap: blocked ? null : onTap,
    );
  }
}

class _SlotBadge extends StatelessWidget {
  const _SlotBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      );
}

/// Выбор предмета в слот. Список отсортирован по приросту силы билда —
/// это и есть «дельта к надетому» из GDD §4.1: при девяти слотах сравнивать
/// предметы на глаз невозможно.
class _SlotSheet extends StatelessWidget {
  const _SlotSheet({
    required this.title,
    required this.worn,
    required this.options,
    required this.gainOf,
    required this.onEquip,
    this.onUnequip,
  });

  final String title;
  final Item? worn;
  final List<Item> options;
  final double Function(Item) gainOf;
  final void Function(Item) onEquip;
  final VoidCallback? onUnequip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (onUnequip != null)
                    TextButton(onPressed: onUnequip, child: const Text('Снять')),
                ],
              ),
            ),
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text('В сундуке нет ничего для этого слота.',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final item = options[i];
                    return _ItemOption(
                      item: item,
                      gain: gainOf(item),
                      onTap: () => onEquip(item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemOption extends StatelessWidget {
  const _ItemOption({
    required this.item,
    required this.gain,
    required this.onTap,
  });

  final Item item;
  final double gain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final better = gain > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ItemText.title(item),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  for (final line in ItemText.lines(item))
                    Text(line,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              better ? '+${money(gain)}' : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: better ? Colors.lightGreenAccent : Colors.white38,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор способности в слот. Активные и пассивные в одном списке — они
/// конкурируют за один пул, и разносить их по вкладкам значило бы прятать
/// сам выбор.
/// Выбор способности в слот.
///
/// Список стал длинным намеренно — способностей пятьдесят пять, — и плоским
/// он быть перестал: без отбора по тегу игрок листает полсотни карточек и
/// собирает не билд, а то, что первым попалось на глаза.
///
/// Отбор именно по ТЕГУ, а не по виду («активные / пассивные»): вид отвечает
/// на вопрос «как оно работает», а тег — на вопрос «во что я вкладываюсь».
/// Второй вопрос и есть сборка билда.
class _AbilitySheet extends StatefulWidget {
  const _AbilitySheet({
    required this.abilities,
    required this.selected,
    required this.current,
    required this.onPick,
    required this.stats,
    this.blockedReason,
    this.highlight = const {},
  });

  final List<AbilityDef> abilities;
  final List<String> selected;
  final String? current;
  final void Function(String?) onPick;

  /// Статы сборки — для разбора в карточке способности.
  final StatBlock stats;

  /// Почему это умение поставить нельзя, или `null`. Причина показывается
  /// строкой в самой карточке: запрет без объяснения игрок читает как
  /// поломку игры — ровно так его и прочитали.
  final String? Function(AbilityDef)? blockedReason;

  /// Теги, по которым у сборки уже есть множитель.
  final Set<Tag> highlight;

  @override
  State<_AbilitySheet> createState() => _AbilitySheetState();
}

class _AbilitySheetState extends State<_AbilitySheet> {
  Tag? _filter;

  /// Теги, ради которых стоит показывать отбор.
  ///
  /// Порядок не алфавитный, а осевой: сперва стихии, потом форма, потом
  /// механика. Так строка чипов читается как «чем бить / чем это растёт /
  /// как оно устроено», а не как список слов.
  static const _order = [
    Tag.fire, Tag.cold, Tag.lightning, Tag.voidTag, Tag.physical,
    Tag.attack, Tag.spell,
    Tag.projectile, Tag.area, Tag.duration, Tag.curse, Tag.totem,
    Tag.aura, Tag.strike, Tag.blood,
  ];

  @override
  Widget build(BuildContext context) {
    final present = {for (final def in widget.abilities) ...def.tags};
    final tags = [for (final tag in _order) if (present.contains(tag)) tag];

    final shown = _filter == null
        ? widget.abilities
        : [for (final d in widget.abilities) if (d.tags.contains(_filter)) d];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Умение',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (widget.current != null)
                    TextButton(
                      onPressed: () => widget.onPick(null),
                      child: const Text('Очистить'),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterChip(
                    label: 'Все',
                    selected: _filter == null,
                    color: Colors.white70,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final tag in tags)
                    _FilterChip(
                      label: tag.ru,
                      selected: _filter == tag,
                      color: tagColor(tag),
                      // Точка у тега, в который игрок уже вложился: отбор
                      // подсказывает, куда сборка уже смотрит.
                      marked: widget.highlight.contains(tag),
                      onTap: () => setState(() => _filter = tag),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'С этим тегом открытых умений пока нет. '
                        'Остальные открывает древо Эха.',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final def = shown[i];
                        final taken = widget.selected.contains(def.id) &&
                            def.id != widget.current;
                        final blocked = widget.blockedReason?.call(def);
                        final locked = taken || blocked != null;

                        return Opacity(
                          opacity: locked ? 0.35 : 1.0,
                          child: InkWell(
                            onTap: locked ? null : () => widget.onPick(def.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(def.name,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      if (def.id == widget.current)
                                        const Icon(Icons.check, size: 16),
                                      // Прочитать разбор, не выбирая: иначе
                                      // сравнить два умения можно только
                                      // поставив каждое по очереди.
                                      IconButton(
                                        icon: const Icon(Icons.info_outline,
                                            size: 16),
                                        tooltip: 'Подробно',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.only(left: 8),
                                        onPressed: () =>
                                            AbilityDetailSheet.show(context,
                                                def: def,
                                                stats: widget.stats),
                                      ),
                                    ],
                                  ),
                                  Text(_abilityLine(def),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white60)),
                                  if (blocked != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      blocked,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.orangeAccent),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  TagChips(
                                    tags: def.tags,
                                    highlight: widget.highlight,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.marked = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.3) : Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (marked) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? color : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Приказ на развилку (GDD §2.6).
///
/// Пятый рычаг рядом с четырьмя остальными: снаряжение, способности, черта
/// наёмника — и то, что он выберет на развилке, пока игрока нет рядом. Стоит
/// здесь, а не в момент отправки: это часть сборки, а не последний вопрос
/// перед прыжком.
class _ForkOrder extends StatelessWidget {
  const _ForkOrder({required this.policy, required this.onPick});

  final ForkPolicy policy;
  final ValueChanged<ForkPolicy>? onPick;

  /// Что каждый приказ означает на деле. Название политики без объяснения
  /// заставляет игрока выбирать вслепую.
  /// Формулировки сверены с замером `sim_cli --forks`, а не придуманы:
  /// обещание «больше добычи», которого нет в цифрах, — это ложь игроку.
  static const _meaning = {
    ForkPolicy.loot: 'Редких предметов и осколков больше, глубина и Эхо ниже',
    ForkPolicy.safety: 'Глубже, больше Эха и золота — но добыча беднее',
    ForkPolicy.echo: 'Гонится за Эхом боссов; где Эха нет — берёт добычу',
    ForkPolicy.random: 'Как повезёт',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in ForkPolicy.values)
          Opacity(
            opacity: onPick == null && option != policy ? 0.4 : 1.0,
            child: InkWell(
              onTap: onPick == null ? null : () => onPick!(option),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      option == policy
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: option == policy
                          ? const Color(0xFF7FB069)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(option.ru,
                              style: const TextStyle(fontSize: 13)),
                          Text(
                            _meaning[option] ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
