import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/trailer/demo_profile.dart';
import 'package:rift_app/trailer/trailer_app.dart';
import 'package:rift_app/ui/echo_tree_screen.dart';
import 'package:rift_app/ui/forge_screen.dart';
import 'package:rift_app/ui/journal_screen.dart';
import 'package:rift_app/ui/loot_sort_screen.dart';
import 'package:rift_app/ui/mercenary_screen.dart';
import 'package:rift_app/ui/passive_tree_screen.dart';
import 'package:rift_app/ui/quests_screen.dart';
import 'package:rift_app/ui/stash_screen.dart';

/// Трейлер — инструмент, а не игра, и всё-таки он тут проверяется.
///
/// Причина простая: сломанный трейлер обнаруживается на съёмке, когда телефон
/// уже в штативе, а свет уже поставлен. Дешевле узнать здесь.
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

  test('демо-профиль: Застава, в которой уже жили', () {
    final p = DemoProfile.build();

    // Пустая Застава в кадре показывает не игру, а её первую минуту.
    expect(p.maxDepthEver, greaterThan(20),
        reason: 'глубина рекорда должна быть похожа на прожитую игру');
    expect(p.stash, isNotEmpty, reason: 'сундук в кадре не должен быть пуст');
    expect(p.roster.reserve.length, greaterThanOrEqualTo(2),
        reason: 'отправку надо показать на ком-то, и список должен быть списком');
    expect(p.tree.bought, isNotEmpty, reason: 'древо Эха должно быть начато');
  });

  test('демо-профиль повторим: второй дубль показывает ту же Заставу', () {
    final a = DemoProfile.build();
    final b = DemoProfile.build();

    // Без этого неудачный кусок нельзя переснять — только перемонтировать
    // весь ролик.
    expect(a.maxDepthEver, b.maxDepthEver);
    expect(a.gold, b.gold);
    expect(a.stash.length, b.stash.length);
  });

  testWidgets('круг проходится целиком и заходит во все разделы',
      (tester) async {
    // Вертикальный кадр телефона, а не стандартные 800×600 теста: подписи и
    // наезды рассчитаны на 9:16.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('rift_trailer_test');
    // Windows держит файл автосохранения открытым дольше, чем живёт тест, и
    // уборка временного каталога иногда не проходит. Это не повод ронять тест.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // пусть остаётся системе
      }
    });

    var passes = 0;
    await tester.pumpWidget(TrailerApp(
      content: content,
      store: SaveStore(dir),
      onPass: () => passes++,
    ));

    final seen = <Type>{};
    const screens = [
      MercenaryScreen,
      JournalScreen,
      LootSortScreen,
      EchoTreeScreen,
      PassiveTreeScreen,
      ForgeScreen,
      StashScreen,
      QuestsScreen,
    ];

    // Шаг крупный. Кадр трейлера — это вся Застава плюс наезд камеры, и
    // мелкий шаг тратит минуты на плавность, которой в тесте никто не видит.
    for (var i = 0; i < 400 && passes == 0; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      for (final screen in screens) {
        if (find.byType(screen).evaluate().isNotEmpty) seen.add(screen);
      }
    }

    expect(tester.takeException(), isNull);
    expect(passes, greaterThan(0), reason: 'сценарий должен дойти до конца');
    expect(seen, containsAll(screens),
        reason: 'трейлер обязан показать всю игру, а не половину');

    // Снимаем дерево: контроллер держит таймер часов и автосохранения, и без
    // этого тест падает на «A Timer is still pending».
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
