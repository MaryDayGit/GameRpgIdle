import 'package:flutter/material.dart';

import 'help_content.dart';

/// Справка: оглавление и разделы.
///
/// Существует по замечанию с телефона: «крафт не интуитивно понятный»,
/// «непонятно, как менять билд». Часть этого лечится экранами — подсказка в
/// нужном месте всегда лучше страницы текста. Но правила, которые нельзя
/// уместить в строку под кнопкой, должны лежать там, где их можно ПРОЧИТАТЬ,
/// а не выясняться опытным путём.
///
/// Открывается и с оглавления, и сразу на нужном разделе: в Кузницу игрок
/// приходит с вопросом про крафт, а не про цикл игры.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.sectionId});

  /// Раздел, на котором открыть справку. `null` — оглавление.
  final String? sectionId;

  @override
  Widget build(BuildContext context) {
    final section = sectionId == null
        ? null
        : helpSections.where((s) => s.id == sectionId).firstOrNull;

    if (section != null) return _SectionScreen(section: section);

    return Scaffold(
      appBar: AppBar(title: const Text('Справка')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        itemCount: helpSections.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Colors.white10),
        itemBuilder: (context, i) {
          final section = helpSections[i];
          return ListTile(
            title: Text(section.title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Text(section.summary,
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            trailing:
                const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _SectionScreen(section: section),
            )),
          );
        },
      ),
    );
  }
}

class _SectionScreen extends StatelessWidget {
  const _SectionScreen({required this.section});

  final HelpSection section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          for (final block in section.blocks) ...[
            if (block.heading.isNotEmpty) ...[
              Text(
                block.heading,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE0A87A),
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (final line in block.lines) ...[
              Text(
                line,
                style: const TextStyle(
                    fontSize: 14, height: 1.45, color: Colors.white70),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// Открывает справку — с оглавления или сразу на разделе.
Future<void> openHelp(BuildContext context, {String? section}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HelpScreen(sectionId: section),
    ));
