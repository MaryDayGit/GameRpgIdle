import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/text_overlay.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';
import 'package:rift_app/ui/outpost_screen.dart';

/// Язык глазами игрока: выбор в настройках, переживший перезапуск, и экран,
/// собранный на выбранном языке.
///
/// Проверяется здесь, а не в ядре, потому что ядро отвечает только за словарь.
/// Вопрос «переключается ли игра целиком» — про клиент: настройки читаются
/// раньше контента, контент перечитывается заново, экраны перестраиваются.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  Map<String, Object?> readRaw() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    return raw;
  }

  /// Пакет на нужном языке из файлов, а не из `rootBundle`: тест экранов
  /// поднимает контроллер напрямую, минуя `boot()`.
  ContentBundle bundle(Lang lang) {
    final raw = readRaw();
    if (lang == Lang.ru) {
      return ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    }

    final overlays = <String, TextOverlay>{};
    for (final name in ContentPack.fileNames) {
      final file = File('assets/content/${lang.code}/$name.json');
      if (!file.existsSync()) continue;
      overlays[name] = TextOverlay.fromJson(jsonDecode(file.readAsStringSync()));
    }
    final translated = TextOverlay.applyAll(raw, overlays);
    return ContentBundle(
      raw: translated,
      pack: ContentPack.parse(translated),
      lang: lang,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_lang_test');
  });

  tearDown(() {
    Lang.current = Lang.ru;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  GameController build({Lang lang = Lang.ru}) {
    final content = bundle(lang);
    content.pack.apply();
    Lang.current = lang;

    final store = SaveStore(dir);
    return GameController(
      content: content,
      store: store,
      settings: SettingsStore(dir),
      initialSettings: AppSettings(lang: lang, tutorialDone: true),
      profile: PlayerProfile.newGame(seed: 42),
      clock: () => DateTime.utc(2026, 6, 1, 12),
      seed: 42,
    );
  }

  testWidgets('настройки предлагают оба языка и показывают выбранный',
      (tester) async {
    final c = build();
    await tester.pumpWidget(MaterialApp(home: OutpostScreen(controller: c)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();

    // Языки подписаны на себе самих: русский ищет «Русский», а не «Russian».
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Язык'), findsOneWidget);

    c.stop();
  });

  testWidgets('на английском Застава подписана по-английски', (tester) async {
    final c = build(lang: Lang.en);
    await tester.pumpWidget(MaterialApp(home: OutpostScreen(controller: c)));
    await tester.pumpAndSettle();

    // Постройки — словарь ядра, а не контента: их названия переключаются
    // вместе с `Lang.current`, без перезагрузки JSON.
    expect(Building.tavern.title, 'Tavern');

    // Панель построек лежит внизу длинного списка: без прокрутки её виджеты
    // не построены вовсе, и `findsNothing` означал бы «не доскроллили», а не
    // «не переведено».
    await tester.scrollUntilVisible(find.text(Building.tavern.title), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(Building.tavern.title));
    await tester.pumpAndSettle();

    expect(find.text('Tavern'), findsWidgets);
    expect(find.textContaining('Таверна'), findsNothing);

    c.stop();
  });

  test('выбранный язык переживает перезапуск', () {
    // Язык лежит рядом со звуком, а не в сейве: это настройка устройства.
    // Но читается он раньше контента — от него зависит, что грузить, — и
    // потому обязан доживать до следующего запуска сам, без сейва.
    final store = SettingsStore(dir);
    store.save(AppSettings(lang: Lang.en));

    expect(SettingsStore(dir).load().lang, Lang.en);
  });

  test('настройки без записи о языке открываются по-русски', () {
    // Файл настроек из версии, которая про язык ещё не знала. Обновление не
    // должно ни падать, ни молча переключать игру на английский.
    File('${dir.path}/rift.settings.json')
        .writeAsStringSync('{"sound":false,"haptics":true}');

    final settings = SettingsStore(dir).load();
    expect(settings.lang, Lang.ru);
    expect(settings.sound, isFalse, reason: 'остальные настройки на месте');
  });
}
