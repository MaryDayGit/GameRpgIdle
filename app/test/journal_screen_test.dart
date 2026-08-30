import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/ui/journal_screen.dart';

/// Журнал — единственный экран, где про наёмника говорят В ПРОШЕДШЕМ ВРЕМЕНИ,
/// а в русском прошедшее время согласуется с родом. Половина имён в пуле
/// женские, и «Тала Слепая чуть не погиб» читается как ошибка игры, а не как
/// огрех перевода.
///
/// Проверка нужна потому, что род здесь забывали трижды: в исходе спуска, в
/// строке «чуть не погиб» и в приписке про добычу при отзыве. Каждый раз
/// правка была на одну строку, и каждый раз следующая строка оставалась
/// мужской.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  /// Все строки экрана одним списком: искать приходится не конкретную фразу,
  /// а МУЖСКУЮ форму где угодно.
  List<String> texts(WidgetTester tester) => [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data ?? '',
      ];

  Future<List<String>> journalOf(WidgetTester tester, Mercenary merc) async {
    final profile = PlayerProfile(gold: 50000)..roster.reserve.add(merc);
    // Сид выбран так, чтобы спуск ЗАВЕДОМО прошёл через опасный этаж:
    // иначе строка «чуть не погибла» не появится и проверять будет нечего.
    final contract = profile.deploy(merc, seed: 3);
    profile.refreshContracts(
        DateTime.now().toUtc().add(const Duration(days: 1)));

    // Журнал — длинный список, и Flutter строит только видимую его часть.
    // На телефонном экране строка «чуть не погибла» осталась бы за кадром, и
    // проверка прошла бы, ничего не увидев.
    tester.view.physicalSize = const Size(1200, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: JournalScreen(contract: contract, onCollect: () {}),
    ));
    await tester.pump();

    final lines = texts(tester);
    await tester.pumpWidget(const SizedBox());
    return lines;
  }

  Mercenary merc(String id, String name) => Mercenary(
        id: id,
        name: name,
        rank: MercRank.veteran,
        trait: MercTrait.swift,
      );

  testWidgets('про наёмницу говорят в женском роде', (tester) async {
    // «Тала» — женское имя в пуле игры, род выводится из него.
    final lines = await journalOf(tester, merc('f', 'Тала Слепая'));

    expect(lines.any((l) => l.contains('Погибла')), isTrue,
        reason: 'исход спуска обязан согласоваться с именем');
    expect(lines.any((l) => l.contains('Погиб ')), isFalse);
    expect(lines.any((l) => l.contains('Чуть не погибла —')), isTrue,
        reason: 'на этом сиде спуск обязан пройти через опасный этаж — иначе '
            'проверка ниже ничего не проверяет');
    expect(lines.any((l) => l.contains('Чуть не погиб —')), isFalse,
        reason: 'мужская форма в строке «чуть не погиб»');
  });

  testWidgets('про наёмника — в мужском', (tester) async {
    // Обратная проверка: женские формы не должны стать новым умолчанием.
    final lines = await journalOf(tester, merc('m', 'Корвин Ржавый'));

    expect(lines.any((l) => l.contains('Погиб')), isTrue);
    expect(lines.any((l) => l.contains('Погибла')), isFalse);
    expect(lines.any((l) => l.contains('Чуть не погибла')), isFalse);
  });
}
