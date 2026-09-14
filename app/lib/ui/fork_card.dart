import 'package:flutter/material.dart';
import 'package:rift/core/content/floor_modifier_def.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/fork_cost.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'strings.dart';
import 'theme.dart';

/// Развилка: где наёмник стоит и куда его послать.
///
/// Живёт отдельным файлом, потому что мест, где этот вопрос задают, ДВА:
/// Застава и экран боя. Наблюдающий за боем — это и есть тот игрок, ради
/// которого развилка спрашивает вживую; отправлять его «назад, там кнопка»
/// значит терять ровно того, кому третий путь и предназначен.
///
/// Панель вокруг рисует вызывающий: на Заставе это карточка с заголовком, на
/// экране боя — то, что заменяет прогноз.
class ForkCard extends StatelessWidget {
  const ForkCard({
    super.key,
    required this.controller,
    required this.contract,
  });

  final GameController controller;
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final fork = contract.pendingFork;
    if (fork == null) return const SizedBox.shrink();

    final now = controller.now;
    final left = controller.forkWaitLeft(contract, now);
    final merc = contract.mercenary;
    final she = merc.gender == Gender.feminine;

    // Сборка, с которой он ушёл вниз. По ней считается, во что обойдётся
    // плата ИМЕННО ему: «−30 сопротивления огню» это тяжело тому, кто его
    // набрал, и ровно ноль тому, у кого его нет.
    final profile = contract.replayProfile();
    final stats = profile.aggregate();
    final loadout = profile.loadout;

    final floors = contract.result!.floors;
    final worst = floors.isEmpty ? 1.0 : floors.last.lowestHpFraction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ожидание — плашкой с часами, и она теплеет к концу. Строкой
        // серого текста оно терялось, а это единственное в карточке, что
        // торопит: не ответите — наёмник решит сам.
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          decoration: BoxDecoration(
            color: (left.inSeconds <= 15 ? RiftColors.warn : RiftColors.info)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(RiftSize.radiusSmall),
            border: Border.all(
              color: (left.inSeconds <= 15 ? RiftColors.warn : RiftColors.info)
                  .withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_bottom_rounded,
                  size: 18,
                  color: left.inSeconds <= 15
                      ? RiftColors.warn
                      : RiftColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // Этаж, на который он ВОЙДЁТ, а не тот, что позади:
                  // выбранный путь действует начиная с него.
                  // `currentFloorAt` показывал бы пройденный — «остановился
                  // у этажа 1», стоя перед третьим.
                  S.forkStanding(
                    she: she,
                    floor: contract.result!.maxDepth + 1,
                    waiting: left.inSeconds > 0
                        ? S.forkWaitsMore(duration(left))
                        : S.forkWaitsNoMore,
                    order: contract.forkPolicy.title.toLowerCase(),
                  ),
                  style: RiftText.small.copyWith(color: RiftColors.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          floors.isEmpty
              ? S.forkHealthUntouched
              : worst > 0.7
                  ? '${S.forkHealth(she: she, left: percent(worst))}'
                      '${S.forkHealthRoomLeft}'
                  : worst > 0.35
                      ? '${S.forkHealth(she: she, left: percent(worst))}.'
                      : '${S.forkHealth(she: she, left: percent(worst))}'
                          '${S.forkHealthNearlyOut(she: she)}',
          style: TextStyle(
            fontSize: 13.5,
            color: worst > 0.35 ? RiftColors.inkFaint : RiftColors.bad,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < fork.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ForkOption(
            modifier: fork.options[i],
            cost: ForkCost.of(fork.options[i], stats, loadout),
            onPick: () => controller.chooseFork(contract, i),
          ),
        ],
        const SizedBox(height: 12),
        // Третий путь стоит отдельно и подписан: он не «ещё один вариант»,
        // а то, чего наёмник не сделает без игрока. Если он выглядит как
        // два соседних, награда за присутствие превращается в третью
        // одинаковую кнопку.
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: RiftColors.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                // Раньше здесь было «один он на такое не пойдёт»: третий путь
                // задумывался как ставка с двойной платой. Платы у него
                // больше нет — платой служит присутствие, — и подпись обязана
                // говорить именно это.
                S.forkBoldOnlyWhilePresent,
                style: RiftText.caption.copyWith(
                  color: RiftColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ForkOption(
          modifier: fork.bold,
          cost: ForkCost.of(fork.bold, stats, loadout),
          bold: true,
          onPick: () => controller.chooseFork(contract, Fork.boldIndex),
        ),
      ],
    );
  }
}

/// Один путь развилки: что он даёт, чего стоит и во что обойдётся ЭТОЙ сборке.
class _ForkOption extends StatelessWidget {
  const _ForkOption({
    required this.modifier,
    required this.cost,
    required this.onPick,
    this.bold = false,
  });

  final FloorModifierDef modifier;

  /// Во что плата обойдётся этой сборке. Это и есть награда за присутствие:
  /// приказ такого не знает, а игрок видит.
  final ForkCost cost;

  final VoidCallback onPick;

  /// Третий путь: обе платы и обе награды.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        // Третий путь — золотой рамкой на тёплой подложке: он не «ещё один
        // вариант», а награда за то, что игрок пришёл.
        backgroundColor: bold
            ? RiftColors.gold.withValues(alpha: 0.08)
            : RiftColors.raised,
        side: BorderSide(
          color: bold
              ? RiftColors.gold.withValues(alpha: 0.75)
              : RiftColors.lineStrong,
          width: bold ? 1.5 : 1,
        ),
        // Прямоугольник со скруглением, а не «стадион» из темы: у стадиона
        // края — полуокружности, и многострочный текст вылезал за них
        // углами. Кнопка в теме рассчитана на одну короткую строку, а здесь
        // их четыре.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            modifier.name,
            style: RiftText.heading.copyWith(
              color: bold ? RiftColors.gold : RiftColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          // Плата первой и со знаком: развилка — это размен, и минус не
          // имеет права читаться мельче плюса.
          // У третьего пути платы нет — и это его награда, а не оговорка:
          // «Платы нет» красным со знаком минус читалось как штраф.
          _Effect(
            icon: modifier.penalties.isEmpty
                ? Icons.check_circle_outline
                : Icons.remove_circle_outline,
            text: modifier.minus,
            color: modifier.penalties.isEmpty ? RiftColors.gold : RiftColors.bad,
          ),
          const SizedBox(height: 2),
          _Effect(
            icon: Icons.add_circle_outline,
            text: modifier.plus,
            color: RiftColors.good,
          ),
          if (cost.text case final text?) ...[
            const SizedBox(height: 4),
            Text(
              cost.harmless ? '$text ${S.forkCostHarmless}' : text,
              style: TextStyle(
                fontSize: 12.5,
                color: cost.harmless
                    ? RiftColors.good.withValues(alpha: 0.75)
                    : RiftColors.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Строка платы или награды: значок и текст одного цвета.
class _Effect extends StatelessWidget {
  const _Effect({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: RiftText.small.copyWith(color: color, height: 1.3),
            ),
          ),
        ],
      );
}
