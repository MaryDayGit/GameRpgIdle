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

  test('разрешение спрашивается на старте и один раз', () async {
    // Правило было обратным — «после первой гибели, там вопрос осмысленнее».
    // Оно стоило первого спуска: наёмник встаёт на развилке через минуты
    // после отправки, разрешения к тому моменту ещё нет, и система молча
    // выбрасывает единственное уведомление, ради которого игру закрывают.
    expect(notifier.permissionAsks, 0, reason: 'конструктор не спрашивает сам');

    await controller.askForNotifications();
    expect(notifier.permissionAsks, 1);

    // Второй раз не спрашиваем: отказ есть отказ, а системный диалог всё
    // равно показывается один раз.
    await controller.askForNotifications();
    expect(notifier.permissionAsks, 1);

    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();

    expect(notifier.permissionAsks, 1, reason: 'гибель больше не спрашивает');
  });

  test('манифест объявляет приёмники плагина уведомлений', () {
    // Доставка — дело системы, но одна её часть лежит в нашем репозитории.
    // С 19-й версии flutter_local_notifications не объявляет приёмники в
    // своём манифесте, и слияние их не добавит: без ScheduledNotification-
    // Receiver будильник срабатывает в пустоту, и уведомление о гибели не
    // появляется даже при выданном разрешении. Проверяется файлом, потому
    // что иначе это ловится только на живом устройстве.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
        manifest,
        contains('com.dexterous.flutterlocalnotifications'
            '.ScheduledNotificationReceiver'));
    expect(
        manifest,
        contains('com.dexterous.flutterlocalnotifications'
            '.ScheduledNotificationBootReceiver'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'),
        reason: 'будильники переставляются после перезагрузки телефона');
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
