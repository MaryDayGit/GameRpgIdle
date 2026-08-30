import 'dart:io';

import 'package:test/test.dart';

/// Балансировщик — не вспомогательный скрипт, а инструмент, которым
/// принимаются решения о балансе. Его молчаливая поломка означает, что
/// следующая правка кривых делается вслепую.
///
/// Здесь проверяется не результат замера, а то, что каждый режим доходит до
/// конца. Ровно этого не хватило, когда контракты стали ждать своего времени:
/// `--campaign` падал с исключением, а тесты ядра были зелёными.
void main() {
  Future<void> runsCleanly(List<String> args) async {
    final result = await Process.run(
      'dart',
      ['run', 'tool/sim_cli.dart', ...args],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'sim_cli ${args.join(" ")} упал:\n'
          '${result.stdout}\n${result.stderr}',
    );
    expect('${result.stdout}', isNotEmpty);
  }

  test('режим кривых', () => runsCleanly(['--curve']), timeout: _slow);
  test('распределение глубины',
      () => runsCleanly(['--dist', '--runs', '5']), timeout: _slow);
  test('замер стены', () => runsCleanly(['--wall', '--runs', '2']),
      timeout: _slow);
  test('мета-прогрессия', () => runsCleanly(['--meta', '3']), timeout: _slow);
  test('полный цикл кампании', () => runsCleanly(['--campaign', '3']),
      timeout: _slow);
  test('сравнение билдов', () => runsCleanly(['--builds', '--runs', '2']),
      timeout: _slow);
  test('политики развилки', () => runsCleanly(['--forks', '--runs', '2']),
      timeout: _slow);
}

/// Каждый запуск поднимает свою VM — секунды, а не миллисекунды.
const _slow = Timeout(Duration(minutes: 3));
