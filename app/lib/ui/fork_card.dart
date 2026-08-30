import 'package:flutter/material.dart';
import 'package:rift/core/content/floor_modifier_def.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/fork_cost.dart';

import '../state/game_controller.dart';
import 'format.dart';

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
        Text(
          // Этаж, на который он ВОЙДЁТ, а не тот, что позади: выбранный
          // путь действует начиная с него. `currentFloorAt` показывал бы
          // пройденный — «остановился у этажа 1», стоя перед третьим.
          '${she ? "Остановилась" : "Остановился"} перед этажом '
          '${contract.result!.maxDepth + 1}. '
          '${left.inSeconds > 0 ? "Ждёт ещё ${duration(left)}" : "Больше не ждёт"}, '
          'потом решит сам${she ? "а" : ""}: ${contract.forkPolicy.ru.toLowerCase()}.',
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 6),
        Text(
          floors.isEmpty
              ? 'Прошлый этаж дался без единой царапины.'
              : worst > 0.7
                  ? 'На прошлом этаже опускал${she ? "ась" : "ся"} до '
                      '${percent(worst)} здоровья — запас есть.'
                  : worst > 0.35
                      ? 'На прошлом этаже опускал${she ? "ась" : "ся"} до '
                          '${percent(worst)} здоровья.'
                      : 'На прошлом этаже ${she ? "была" : "был"} на '
                          '${percent(worst)} здоровья — ещё немного, и всё.',
          style: TextStyle(
            fontSize: 12,
            color: worst > 0.35 ? Colors.white38 : Colors.orangeAccent,
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
        Text(
          // Раньше здесь было «один он на такое не пойдёт»: третий путь
          // задумывался как ставка с двойной платой. Платы у него больше
          // нет — платой служит присутствие, — и подпись обязана говорить
          // именно это.
          'Открыт, только пока вы в игре',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
          ),
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
    final accent = Theme.of(context).colorScheme.primary;

    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: bold ? BorderSide(color: accent) : null,
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
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            modifier.minus,
            style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
          ),
          Text(
            modifier.plus,
            style: const TextStyle(fontSize: 12, color: Colors.lightGreenAccent),
          ),
          if (cost.text case final text?) ...[
            const SizedBox(height: 4),
            Text(
              cost.harmless ? '$text Эта плата вам почти ничего не стоит' : text,
              style: TextStyle(
                fontSize: 11,
                color: cost.harmless
                    ? Colors.lightGreenAccent.withValues(alpha: 0.75)
                    : Colors.white38,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
