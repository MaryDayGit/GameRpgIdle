import 'package:flutter/material.dart';

import 'help_content.dart';
import 'strings.dart';
import 'theme.dart';

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
      appBar: AppBar(title: Text(S.helpTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        itemCount: helpSections.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: RiftColors.line),
        itemBuilder: (context, i) {
          final section = helpSections[i];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            title: Text(section.title, style: RiftText.heading),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(section.summary, style: RiftText.small),
            ),
            trailing:
                const Icon(Icons.chevron_right, size: 22, color: RiftColors.inkFaint),
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
                style: RiftText.title.copyWith(
                  fontSize: 17,
                  color: RiftColors.ember,
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (final line in block.lines) ...[
              Text(
                line,
                style: RiftText.body.copyWith(fontSize: 15.5, height: 1.5),
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
