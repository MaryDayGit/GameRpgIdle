import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift_app/ui/help_content.dart';
import 'package:rift_app/ui/help_screen.dart';

/// Справка: оглавление, разделы и вход сразу на нужный.
///
/// Тесты держат не текст (он будет меняться), а обещания: разделы не пустые,
/// у каждого свой идентификатор, и по идентификатору справка открывается
/// сразу на нём — из Кузницы игрок приходит с вопросом про крафт.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('оглавление перечисляет все разделы', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: HelpScreen(),
    ));
    await tester.pump();

    for (final section in helpSections) {
      await tester.scrollUntilVisible(find.text(section.title), 200);
      expect(find.text(section.title), findsOneWidget);
    }
  });

  testWidgets('раздел открывается сразу, если его назвали', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: HelpScreen(sectionId: 'craft'),
    ));
    await tester.pump();

    final craft = helpSections.firstWhere((s) => s.id == 'craft');
    expect(find.text(craft.title), findsOneWidget);
    expect(find.text(craft.blocks.first.lines.first), findsOneWidget,
        reason: 'открылся раздел, а не оглавление');
  });

  testWidgets('неизвестный раздел показывает оглавление, а не пустоту',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: HelpScreen(sectionId: 'нет такого'),
    ));
    await tester.pump();

    expect(find.text('Справка'), findsOneWidget);
  });

  test('разделы непустые и не повторяются', () {
    final ids = <String>{};
    for (final section in helpSections) {
      expect(ids.add(section.id), isTrue, reason: 'дубль id «${section.id}»');
      expect(section.title, isNotEmpty);
      expect(section.summary, isNotEmpty);
      expect(section.blocks, isNotEmpty, reason: section.title);

      for (final block in section.blocks) {
        expect(block.lines, isNotEmpty, reason: '${section.title}: пустой блок');
        for (final line in block.lines) {
          expect(line.trim(), isNotEmpty);
        }
      }
    }
  });

  test('справка покрывает то, о чём спрашивали', () {
    // Разделы, без которых справка не отвечает на замечания живого прогона:
    // крафт, сборка билда и сам цикл игры.
    final ids = {for (final s in helpSections) s.id};
    expect(
        ids, containsAll(<String>['loop', 'build', 'craft', 'tags', 'quests']));
  });

  test('справка обещает, что вещи не теряются', () {
    // Живой прогон: «вещи, которые ты одеваешь на наёмника, должны
    // оставаться». Обещание, данное кодом, но не сказанное вслух, игрок
    // проверить не может — он видит только сундук до и после.
    final loop = helpSections.firstWhere((s) => s.id == 'loop');
    final text = loop.blocks.expand((b) => b.lines).join(' ');

    expect(text, contains('уходит вниз именно так, как вы '));
    expect(text, contains('возвращается целиком'));
    expect(text, contains('Реликты не берёт'),
        reason: 'иначе непонятно, почему реликт остался в сундуке');
  });

  test('справка объясняет, откуда берутся умения', () {
    // Замечание живого прогона было «умений мало, и они все сразу открыты».
    // Правило поменялось целиком: открывают их теперь задания. Справка —
    // первое, что устаревает при такой правке.
    final quests = helpSections.firstWhere((s) => s.id == 'quests');
    final text = quests.blocks.expand((b) => b.lines).join(' ').toLowerCase();

    expect(text, contains('задани'));
    expect(text, contains('одно задание — одно умение'));
    expect(text, contains('цепочк'));

    // И древо Эха больше не должно обещать того, чего не делает.
    final trees = helpSections.firstWhere((s) => s.id == 'trees');
    final treeText = trees.blocks.expand((b) => b.lines).join(' ');
    expect(treeText, contains('Умения оно НЕ открывает'));
  });

  test('справка объясняет две оси и теги', () {
    // Замечание живого прогона было буквально «на вещах есть модификатор
    // урона к огню, а умений огня нет, строить билд не с чего». Половина
    // ответа — контент, вторая половина — объяснение: связь «умение — тег —
    // вещь» нигде не была написана словами.
    final tags = helpSections.firstWhere((s) => s.id == 'tags');
    final text = tags.blocks.expand((b) => b.lines).join(' ').toLowerCase();

    expect(text, contains('огнём'));
    expect(text, contains('молни'));
    expect(text, contains('пропитк'),
        reason: 'мост между оружием и стихией — то, что нужно объяснить');

    final build = helpSections.firstWhere((s) => s.id == 'build');
    final axes = build.blocks.expand((b) => b.lines).join(' ').toLowerCase();
    expect(axes, contains('сил'));
    expect(axes, contains('чары'));
    expect(axes, contains('атаки'));
  });

  test('справка знает про все три вида умений', () {
    // Ауры добавились последними, и справка — первое, что устаревает при
    // такой правке: игрок открывает её ровно затем, чтобы понять новое.
    final build = helpSections.firstWhere((s) => s.id == 'build');
    final text = build.blocks.expand((b) => b.lines).join(' ').toLowerCase();

    expect(text, contains('активные'));
    expect(text, contains('пассивные'));
    expect(text, contains('ауры'));
    expect(text, contains('резервируют'),
        reason: 'резерв маны — главная цена ауры, и без него аура непонятна');
  });
}
