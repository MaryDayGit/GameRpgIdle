import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift_app/dev/live_descent_panel.dart';

/// Пошаговый драйвер обязан жить в кадровом цикле Flutter: если он крутится
/// только в тестах ядра, «живой бой на экране» остаётся теорией.
void main() {
  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    ContentPack.parse(raw).apply();
  });

  testWidgets('спуск идёт по кадрам и переживает уход с экрана',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LiveDescentPanel())),
    );
    expect(find.text('Спуск не начат.'), findsOneWidget);

    await tester.tap(find.text('Новый спуск'));
    await tester.pump();

    // Ускорение x20, чтобы за десяток кадров успело произойти заметное.
    await tester.tap(find.text('×20'));
    await tester.pump();

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Этаж'), findsOneWidget);
    expect(find.textContaining('мин'), findsOneWidget);

    // Уход с экрана на середине рана не должен падать ассертом тикера.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
  });
}
