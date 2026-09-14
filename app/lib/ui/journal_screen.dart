import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';

import '../state/game_controller.dart';
import 'coach_mark.dart';
import 'format.dart';
import 'gear_grid.dart';
import 'gear_icons.dart';
import 'onboarding.dart';
import 'strings.dart';
import 'tutorial_host.dart';
import 'theme.dart';

/// Журнал отсутствия (GDD §9.3).
///
/// Единственный экран, где игрок узнаёт, что происходило, пока его не было.
/// Поэтому здесь не сводка цифр, а рассказ: докуда дошёл, что нашёл, где чуть
/// не погиб и от чего погиб в итоге.
///
/// Порядок разделов — порядок вопросов, которые игрок задаёт сам себе,
/// открывая приложение: «докуда?», «что принёс?», «как так вышло?».
class JournalScreen extends StatelessWidget {
  const JournalScreen({
    super.key,
    required this.contract,
    required this.onCollect,
    this.controller,
  });

  final Contract contract;
  final VoidCallback onCollect;

  /// Нужен только обучению: экран сам по себе читает контракт, а не игру.
  /// `null` — журнал показывают без обучения (тесты, повтор из истории).
  final GameController? controller;

  RunResult get result => contract.result!;

  @override
  Widget build(BuildContext context) {
    final merc = contract.mercenary;
    final haul = result.haul;

    final screen = Scaffold(
      appBar: AppBar(title: Text(S.journalTitle(merc.name))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Outcome(contract: contract, result: result),
          const SizedBox(height: 24),

          _SectionTitle(S.journalFinds(haul.itemCount, haul.capacity)),
          if (haul.items.isEmpty)
            Text(S.journalNothingNew,
                style: const TextStyle(fontSize: 14.5, color: RiftColors.inkMuted))
          else
            for (final item in haul.items) _ShowcaseItem(item: item),


          if (haul.salvagedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              S.journalOverflow(haul.salvagedCount, money(haul.salvagedGold),
                  haul.shards.length),
              style: const TextStyle(fontSize: 13.5, color: RiftColors.inkFaint),
            ),
          ],

          const SizedBox(height: 24),
          _SectionTitle(S.journalOnTheWay),
          for (final event in _events(result, merc.gender))
            _EventRow(event: event),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TutorialAnchor(
            id: Onboarding.anchorJournalCollect,
            child: FilledButton(
              onPressed: onCollect,
              child: Text(S.journalCollect(money(haul.totalGold), result.echo)),
            ),
          ),
        ),
      ),
    );

    final c = controller;
    if (c == null) return screen;

    return TutorialHost(
      controller: c,
      screen: TutorialScreen.journal,
      child: screen,
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.contract, required this.result});

  final Contract contract;
  final RunResult result;

  @override
  Widget build(BuildContext context) {
    final from = result.floors.isEmpty ? 1 : result.floors.first.depth;
    final gained = result.maxDepth - from + 1;

    // Исход согласован с наёмником: половина имён в пуле женские, и
    // «Мирена Последняя погиб» читается как ошибка. Слово «жив» —
    // из той же оперы.
    final she = contract.mercenary.gender == Gender.feminine;
    final tail = switch (result.ending) {
      RunEnding.death => S.journalOutcomeDeath(
          she: she, floor: result.maxDepth + 1, killedBy: result.killedBy),
      RunEnding.stalled =>
        S.journalOutcomeStalled(she: she, floor: result.maxDepth + 1),
      RunEnding.timeCap => S.journalOutcomeTimeCap(she: she),
      RunEnding.floorCap => S.journalOutcomeFloorCap(she: she),
      // Журнал открытого спуска: наёмник ещё идёт, и последняя строка — не
      // итог, а место, где он сейчас.
      RunEnding.atFork => S.journalOutcomeAtFork(result.maxDepth + 1),
      RunEnding.recalled =>
        S.journalOutcomeRecalled(she: she, floor: result.maxDepth + 1),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.journalFloors(from, result.maxDepth, gained),
          style: RiftText.display,
        ),
        const SizedBox(height: 6),
        Text(
          "${contract.mercenary.rank.forGender(contract.mercenary.gender)} · "
          "${contract.mercenary.trait.forGender(contract.mercenary.gender)} · "
          "${S.journalInAbyss(clock(result.totalSeconds))}",
          style: const TextStyle(fontSize: 13.5, color: RiftColors.inkMuted),
        ),
        const SizedBox(height: 12),
        // Исход — плашкой своего цвета. Гибель красная, отзыв зелёный: это
        // разные концы, и в первую секунду журнала должно быть видно, какой.
        Builder(builder: (context) {
          final tone = switch (result.ending) {
            RunEnding.death => RiftColors.bad,
            RunEnding.recalled => RiftColors.good,
            _ => RiftColors.warn,
          };
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(RiftSize.radiusSmall + 2),
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            ),
            child: Text(tail, style: RiftText.body.copyWith(color: tone)),
          );
        }),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: RiftText.overline),
      );
}

/// Находка. Триггерный аффикс подсвечивается: ради него читают лут (GDD §9.3).
class _ShowcaseItem extends StatelessWidget {
  const _ShowcaseItem({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final trigger = item.triggerAffixId == null
        ? null
        : ContentPack.current.triggerAffix(item.triggerAffixId!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ItemPlaque(item: item),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ItemText.title(item),
                    style: RiftText.heading.copyWith(
                        fontSize: 15, color: colorFor(item.rarity))),
              ),
              if (item.isRelic)
                _Badge(text: S.relicMark, color: RiftColors.ember),
              if (trigger != null)
                _Badge(text: S.triggerMark, color: RiftColors.info),
            ],
          ),
          for (final line in ItemText.lines(item))
            Text(line, style: RiftText.small),
        ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

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

/// Строчная только первая буква: `toLowerCase` на всей строке превращает
/// «Восстановление HP» в «восстановление hp».
String _lowerFirst(String text) => text.isEmpty
    ? text
    : text[0].toLowerCase() + text.substring(1);

/// Событие спуска для ленты.
class _Event {
  const _Event(this.depth, this.text, {this.warning = false});

  final int depth;
  final String text;
  final bool warning;
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final _Event event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text('${event.depth}',
                  style: RiftText.number.copyWith(
                    color: event.warning
                        ? RiftColors.bad
                        : RiftColors.inkFaint,
                  )),
            ),
            if (event.warning) ...[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.warning_amber_rounded,
                    size: 16, color: RiftColors.bad),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                event.text,
                style: RiftText.body.copyWith(
                  fontSize: 14.5,
                  color: event.warning ? RiftColors.bad : RiftColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Ключевые события спуска.
///
/// Отбираются, а не перечисляются: сорок строк «этаж пройден» — это не журнал,
/// а лог. Показываем то, что игрок мог бы пересказать словами: боссы, выбранные
/// пути, этажи, где чуть не погиб, и заметное замедление перед стеной.
List<_Event> _events(RunResult result, Gender gender) {
  final events = <_Event>[];
  String? lastModifier;

  final floors = result.floors;
  if (floors.isEmpty) return events;

  // Замедление считается от начала спуска: время этажа растёт по кривой, и
  // «вдвое дольше первых» — это тот самый видимый признак приближения стены.
  final head = floors.take(3).toList();
  final baseline = head.fold<double>(0, (a, f) => a + f.seconds) / head.length;

  var slowdownReported = false;

  for (final floor in floors) {
    if (floor.modifierId != null && floor.modifierId != lastModifier) {
      lastModifier = floor.modifierId;
      final def = ContentPack.current.floorModifier(floor.modifierId!);
      if (def != null) {
        // Первый модификатор спуска приходит не с развилки: так входит разлом
        // дня, который действует с первого этажа. Назвать его развилкой
        // значило бы сослать игрока искать выбор, которого он не делал.
        final label =
            ForkChooser.isForkFloor(floor.depth)
                ? S.journalFork
                : S.journalRift;
        // У смелого пути платы нет вовсе, и «но платы нет» звучало бы как
        // оговорка там, где это и есть награда за присутствие.
        events.add(_Event(
            floor.depth,
            def.penalties.isEmpty
                ? '$label: ${def.name} — ${def.plus}'
                : '$label: ${def.name} — ${def.plus}, '
                    '${S.journalButCost(_lowerFirst(def.minus))}'));
      }
    }

    final boss = Bestiary.bossFor(floor.depth);
    if (boss != null && floor.survived) {
      events.add(_Event(
        floor.depth,
        S.journalBossDown(boss.name,
            she: boss.gender == Gender.feminine),


      ));
    }

    if (floor.survived && floor.lowestHpFraction < 0.35) {
      // Половина имён в пуле женские, и «Тала Слепая чуть не погиб» читается
      // как ошибка — ровно та же причина, что и у строки исхода.
      events.add(_Event(
        floor.depth,
        S.journalNearlyDied(
            she: gender == Gender.feminine,
            left: percent(floor.lowestHpFraction)),

        warning: true,
      ));
    }

    if (!slowdownReported &&
        baseline > 0 &&
        floor.seconds > baseline * 2 &&
        floor.survived) {
      slowdownReported = true;
      events.add(_Event(floor.depth,
          S.journalSlowing, warning: true));
    }
  }

  if (result.ending == RunEnding.death) {
    events.add(_Event(
      result.maxDepth + 1,
      S.journalEndedHere(result.killedBy),
      warning: true,
    ));
  }

  return events;
}

/// Сколько предметов помещается в витрину. Правило витрины (GDD §4.5) режет
/// добычу до вместимости рюкзака ещё в симуляции, так что здесь остаётся
/// только показать всё, что донесли.
int get showcaseLimit => Tuning.gearSlots + 3;

/// Пути развилки на этаже — для будущего экрана выбора.
bool isForkFloor(int depth) => ForkChooser.isForkFloor(depth);

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
