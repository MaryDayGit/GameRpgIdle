import 'package:flutter/material.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/quest_def.dart';
import 'package:rift/core/model/quest_log.dart';

import '../state/game_controller.dart';
import 'mercenary_screen.dart' show TagChips;

/// Журнал заданий.
///
/// Idle живёт вложенными целями: игрок в любой момент должен знать, ради чего
/// сделает следующий шаг. Цель, названная вслух, держит лучше, чем цель, о
/// которой он догадывается сам.
///
/// Экран показывает ТРИ вещи и ничего больше: что делать сейчас, сколько
/// осталось и что за это дадут. Выполненное уезжает вниз — оно уже не цель, а
/// история; но и стереть его нельзя, иначе исчезает ощущение пройденного пути.
class QuestsScreen extends StatelessWidget {
  const QuestsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final facts = profile.questFacts();
        final log = profile.quests;

        final all = ContentPack.current.quests;
        final open = [
          for (final q in all)
            if (!log.isDone(q.id) && log.isVisible(q)) q,
        ];
        final done = [
          for (final q in all)
            if (log.isDone(q.id)) q,
        ];
        final hidden = all.length - open.length - done.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Задания'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Выполнено ${done.length} из ${all.length} · '
                    'каждое открывает умение',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (open.isEmpty && done.isEmpty)
                const _Empty()
              else ...[
                if (open.isNotEmpty) ...[
                  const _Header('Сейчас'),
                  for (final chain in _chainsOf(open))
                    _Chain(
                      title: _chainNames[chain] ?? chain,
                      quests: [
                        for (final q in open) if (q.chain == chain) q,
                      ],
                      log: log,
                      facts: facts,
                      done: false,
                    ),
                ],
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text(
                      'Ещё $hidden открывается дальше по цепочкам.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white30),
                    ),
                  ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const _Header('Выполнено'),
                  for (final quest in done)
                    _QuestRow(
                        quest: quest, log: log, facts: facts, done: true),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Порядок цепей — порядок контента: пролог первым, дальше как написано.
  /// Сортировать по алфавиту значило бы переставить «Пепел» перед прологом.
  static List<String> _chainsOf(List<QuestDef> quests) {
    final out = <String>[];
    for (final quest in quests) {
      if (!out.contains(quest.chain)) out.add(quest.chain);
    }
    return out;
  }
}

const _chainNames = {
  'prologue': 'Начало',
  'ember': 'Пепел · Огонь',
  'frost': 'Наледь · Холод',
  'storm': 'Гроза · Молния',
  'abyss': 'Провал · Пустота',
  'war': 'Ремесло войны',
  'guard': 'Стойкость',
  'auras': 'Знамёна',
};

class _Chain extends StatelessWidget {
  const _Chain({
    required this.title,
    required this.quests,
    required this.log,
    required this.facts,
    required this.done,
  });

  final String title;
  final List<QuestDef> quests;
  final QuestLog log;
  final QuestFacts facts;
  final bool done;

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  letterSpacing: 0.4)),
        ),
        for (final quest in quests)
          _QuestRow(quest: quest, log: log, facts: facts, done: done),
      ],
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({
    required this.quest,
    required this.log,
    required this.facts,
    required this.done,
  });

  final QuestDef quest;
  final QuestLog log;
  final QuestFacts facts;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final reward = ContentPack.current.ability(quest.rewardAbility);
    final progress = done ? null : log.progressOf(quest, facts);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle_outline : Icons.flag_outlined,
                  size: 16,
                  color: done ? Colors.greenAccent : Colors.white54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    quest.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: done ? Colors.white54 : null,
                    ),
                  ),
                ),
              ],
            ),
            if (!done) ...[
              const SizedBox(height: 4),
              Text(quest.text,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white60, height: 1.3)),
            ],

            // Полоска только там, где есть что копить. У целей про один спуск
            // накопления нет, и «3 из 10» о них соврало бы.
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.$2 <= 0 ? 0 : progress.$1 / progress.$2,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_num(progress.$1)} из ${_num(progress.$2)}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],

            if (reward != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      size: 14,
                      color: done ? Colors.white24 : Colors.amberAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      done
                          ? 'Открыто: ${reward.name}'
                          : 'Награда: ${reward.name}'
                              '${quest.rewardEcho > 0 ? ' · ${quest.rewardEcho} Эха' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: done ? Colors.white24 : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              if (!done) ...[
                const SizedBox(height: 6),
                TagChips(tags: reward.tags),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _num(double v) {
    final rounded = v.roundToDouble();
    return (v - rounded).abs() < 0.005
        ? rounded.toStringAsFixed(0)
        : v.toStringAsFixed(1);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'Заданий пока нет. Отправьте наёмника вниз — первая цель придёт '
          'вместе с первой добычей.',
          style: TextStyle(fontSize: 13, color: Colors.white38, height: 1.4),
        ),
      );
}
