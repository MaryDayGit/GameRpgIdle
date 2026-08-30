import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/notifications.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/state/game_controller.dart';

/// Уведомление — единственная связь игры с игроком, пока приложение закрыто.
/// Проверяется решение («когда и о чём сообщить»), а не доставка: доставка —
/// дело системы, и Android для этого поднимать не нужно.
class _FakeNotifier implements DeathNotifier {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  int permissionAsks = 0;

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    return true;
  }

  @override
  Future<void> scheduleContractEvent({
    required int id,
    required DateTime whenUtc,
    required String mercName,
    required int depth,
    required bool atFork,
  }) async {
    scheduled.add({
      'id': id,
      'when': whenUtc,
      'merc': mercName,
      'depth': depth,
      'atFork': atFork,
    });
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late _FakeNotifier notifier;
  late GameController controller;
  late DateTime clock;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_notify_test');
    clock = DateTime.utc(2026, 9, 1, 10);
    notifier = _FakeNotifier();
    controller = GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile.newGame(seed: 3),
      clock: () => clock,
      notifier: notifier,
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // не важно
    }
  });

  test('отправка ставит уведомление на ближайшую развилку', () {
    // Раньше уведомление ставилось на предсказанное время гибели: спуск
    // считался целиком. Теперь первое, что случится, — развилка, и звать
    // игрока надо к ней: сообщение «погиб», когда наёмник стоит и ждёт, —
    // прямая ложь в шторке уведомлений.
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    expect(notifier.scheduled, hasLength(1));
    final job = notifier.scheduled.single;

    expect(job['when'], contract.segmentEndsAtUtc);
    expect(job['merc'], merc.name);
    expect(job['depth'], contract.result!.maxDepth);
    expect(job['id'], GameController.notificationIdFor(contract));
    expect(job['atFork'], isTrue);
  });

  test('решение на развилке переставляет уведомление на следующий отрезок', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    final first = contract.segmentEndsAtUtc!;

    clock = first.add(const Duration(seconds: 1));
    controller.tick();
    expect(contract.atFork, isTrue);

    expect(controller.chooseFork(contract, 0), isTrue);
    expect(notifier.scheduled, hasLength(2));
    expect(notifier.scheduled.last['when'], contract.segmentEndsAtUtc);
    expect(notifier.scheduled.last['when'], isNot(first),
        reason: 'новый отрезок — новое время');
  });

  test('забор добычи снимает уведомление', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();
    controller.collect(contract);

    expect(notifier.cancelled, [GameController.notificationIdFor(contract)]);
  });

  test('разрешение спрашивается после первой гибели, а не на старте', () {
    // На первом запуске игрок ещё не понимает, зачем игре уведомления.
    expect(notifier.permissionAsks, 0);

    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    controller.tick();
    expect(notifier.permissionAsks, 0, reason: 'наёмник ещё жив');

    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();
    expect(notifier.permissionAsks, 1);

    // Второй раз не спрашиваем: отказ есть отказ.
    controller.collect(contract);
    final second = controller.profile.roster.candidates.first;
    controller.profile.gold += 100000;
    controller.hire(second);
    final next = controller.deploy(second)!;
    clock = next.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();

    expect(notifier.permissionAsks, 1);
  });

  test('идентификатор уведомления переживает перезапуск', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    // Выводится из сида контракта, а не из счётчика: счётчик после перезапуска
    // начался бы заново и отменял чужие уведомления.
    expect(GameController.notificationIdFor(contract),
        GameController.notificationIdFor(contract));
    expect(GameController.notificationIdFor(contract), isNonNegative);
  });
}
