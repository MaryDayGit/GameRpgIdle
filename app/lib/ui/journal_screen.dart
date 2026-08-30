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

import 'format.dart';

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
  });

  final Contract contract;
  final VoidCallback onCollect;

  RunResult get result => contract.result!;

  @override
  Widget build(BuildContext context) {
    final merc = contract.mercenary;
    final haul = result.haul;

    return Scaffold(
      appBar: AppBar(title: Text('Спуск: ${merc.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Outcome(contract: contract, result: result),
          const SizedBox(height: 24),

          _SectionTitle('Находки · ${haul.itemCount} из ${haul.capacity}'),
          if (haul.items.isEmpty)
            const Text('Наёмник не донёс ничего нового.',
                style: TextStyle(fontSize: 13, color: Colors.white54))
          else
            for (final item in haul.items) _ShowcaseItem(item: item),


          if (haul.salvagedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${haul.salvagedCount} не влезло в рюкзак → '
              '${money(haul.salvagedGold)} золота'
              '${haul.shards.isEmpty ? "" : " и "
                  "${plural(haul.shards.length, "осколок", "осколка", "осколков")}"}',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],

          const SizedBox(height: 24),
          const _SectionTitle('Что было по дороге'),
          for (final event in _events(result, merc.gender))
            _EventRow(event: event),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: onCollect,
            child: Text('Забрать всё · ${money(haul.totalGold)} золота, '
                '${result.echo} Эха'),
          ),
        ),
      ),
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
      RunEnding.death => result.killedBy == null
          ? '${she ? "Погибла" : "Погиб"} на этаже ${result.maxDepth + 1}.'
          : '${she ? "Погибла" : "Погиб"} на этаже ${result.maxDepth + 1}: '
              '${result.killedBy}.',
      RunEnding.stalled => '${she ? "Упёрлась" : "Упёрся"} в стену на этаже '
          '${result.maxDepth + 1} — волна не убивается.',
      RunEnding.timeCap => she ? 'Отозвана по времени.' : 'Отозван по времени.',
      RunEnding.floorCap =>
        she ? 'Дошла до предела.' : 'Дошёл до предела.',
      // Журнал открытого спуска: наёмник ещё идёт, и последняя строка — не
      // итог, а место, где он сейчас.
      RunEnding.atFork =>
        'Стоит на развилке у этажа ${result.maxDepth + 1}.',
      RunEnding.recalled => '${she ? "Отозвана" : "Отозван"} с этажа '
          '${result.maxDepth + 1}, не закончив его. '
          '${she ? "Жива, добыча при ней." : "Жив, добыча при нём."}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Этажи $from → ${result.maxDepth}  (+$gained)',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '${contract.mercenary.rank.forGender(contract.mercenary.gender)} · '
          '${contract.mercenary.trait.forGender(contract.mercenary.gender)} · '
          'в бездне ${clock(result.totalSeconds)}',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 10),
        Text(tail,
            style: const TextStyle(fontSize: 14, color: Colors.orangeAccent)),
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
        child: Text(text,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Colors.white54,
            )),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ItemText.title(item),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (item.isRelic)
                const _Badge(text: 'реликт', color: Color(0xFFC7643F)),
              if (trigger != null)
                const _Badge(text: 'триггер', color: Color(0xFF4F8FC7)),
            ],
          ),
          for (final line in ItemText.lines(item))
            Text(line,
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 1))),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white38,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ),
            Expanded(
              child: Text(
                event.text,
                style: TextStyle(
                  fontSize: 13,
                  color: event.warning ? Colors.orangeAccent : Colors.white70,
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
            ForkChooser.isForkFloor(floor.depth) ? 'Развилка' : 'Разлом';
        // У смелого пути платы нет вовсе, и «но платы нет» звучало бы как
        // оговорка там, где это и есть награда за присутствие.
        events.add(_Event(
            floor.depth,
            def.penalties.isEmpty
                ? '$label: ${def.name} — ${def.plus}'
                : '$label: ${def.name} — ${def.plus}, '
                    'но ${_lowerFirst(def.minus)}'));
      }
    }

    final boss = Bestiary.bossFor(floor.depth);
    if (boss != null && floor.survived) {
      events.add(_Event(
        floor.depth,
        boss.gender == Gender.feminine
            ? '${boss.name} повержена'
            : '${boss.name} повержен',
      ));
    }

    if (floor.survived && floor.lowestHpFraction < 0.35) {
      // Половина имён в пуле женские, и «Тала Слепая чуть не погиб» читается
      // как ошибка — ровно та же причина, что и у строки исхода.
      events.add(_Event(
        floor.depth,
        'Чуть не ${gender == Gender.feminine ? "погибла" : "погиб"} — '
        'оставалось ${percent(floor.lowestHpFraction)} здоровья',
        warning: true,
      ));
    }

    if (!slowdownReported &&
        baseline > 0 &&
        floor.seconds > baseline * 2 &&
        floor.survived) {
      slowdownReported = true;
      events.add(_Event(floor.depth,
          'Этажи пошли вдвое медленнее — стена близко', warning: true));
    }
  }

  if (result.ending == RunEnding.death) {
    events.add(_Event(
      result.maxDepth + 1,
      result.killedBy == null
          ? 'Здесь всё и кончилось'
          : 'Здесь всё и кончилось: ${result.killedBy}',
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
