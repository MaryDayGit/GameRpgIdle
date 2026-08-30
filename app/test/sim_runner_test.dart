import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/dev/sim_runner.dart';

/// Страховка от отказа без симптомов (docs/05-ANDROID-PORT.md §3.2):
/// `Curves`, `Tuning` и `Bestiary` — статики, а статики изолятно-локальны.
/// Если забыть настроить их внутри изолята, симуляция посчитается на значениях
/// по умолчанию — молча, правдоподобно и неправильно.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('изолят считает тот же ран, что и главный поток', () async {
    final content = _content();

    ContentBundle.apply(content);
    final local = DescentSimulator(
      profile: HeroProfile(powerMultiplier: 4.0),
      seed: 7,
      backpackCapacityOverride: 12,
    ).run();

    final remote = await runDescent(SimRequest(
      seed: 7,
      content: content,
      powerMultiplier: 4.0,
    ));

    expect(remote.maxDepth, local.maxDepth);
    expect(remote.ending, local.ending);
    expect(remote.echo, local.echo);
  });

  test('контент действительно применяется, а не игнорируется', () async {
    final content = _content();

    // Вдвое более живучий герой обязан уходить глубже. Если бы `apply`
    // в изоляте не срабатывал, обе симуляции дали бы одинаковый результат.
    final tweaked = _content();
    final hero = (tweaked['balance'] as Map)['hero'] as Map;
    hero['maxHp'] = (hero['maxHp'] as num) * 2;

    // По одному сиду глубина не монотонна: удвоение HP меняет всю траекторию
    // рана — другие бои, другой лут, другие развилки. Сравниваем средние.
    var base = 0, buffed = 0;
    for (var seed = 1; seed <= 5; seed++) {
      base += (await runDescent(SimRequest(seed: seed, content: content)))
          .maxDepth;
      buffed += (await runDescent(SimRequest(seed: seed, content: tweaked)))
          .maxDepth;
    }

    expect(buffed, greaterThan(base));
  });

  test('ассеты приложения совпадают с источником в корне репозитория', () {
    for (final name in ContentPack.fileNames) {
      final copy = File('assets/content/$name.json').readAsStringSync();
      final source = File('../assets/content/$name.json').readAsStringSync();
      expect(
        copy,
        source,
        reason: 'assets/content/$name.json разошёлся с источником — '
            'запусти `dart run tool/sync_content.dart`',
      );
    }
  });
}

/// rootBundle в юнит-тестах читает скомпилированный манифест ассетов, а его
/// в `flutter test` нет. Читаем файлы напрямую — пути те же.
Map<String, Object?> _content() {
  final raw = <String, Object?>{};
  for (final name in ContentPack.fileNames) {
    raw[name] =
        jsonDecode(File('assets/content/$name.json').readAsStringSync());
  }
  return raw;
}
