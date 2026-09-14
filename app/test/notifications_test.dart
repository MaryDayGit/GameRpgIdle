import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/balance/tuning.dart';
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
    Duration? expiresAfter,
  }) async {
    scheduled.add({
      'id': id,
      'when': whenUtc,
      'merc': mercName,
      'depth': depth,
      'atFork': atFork,
      'expiresAfter': expiresAfter,
    });
  }

  /// Последнее, что поставлено на этот идентификатор. Уведомлений на контракт
  /// два — зов к развилке и весть о гибели, — и спрашивать их надо по имени.
  Map<String, Object?>? last(int id) {
    for (final job in scheduled.reversed) {
      if (job['id'] == id) return job;
    }
    return null;
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

    final job = notifier.last(GameController.notificationIdFor(contract))!;

    expect(job['when'], contract.segmentEndsAtUtc);
    expect(job['merc'], merc.name);
    expect(job['depth'], contract.result!.maxDepth);
    expect(job['atFork'], isTrue);

    // Зов к развилке живёт ровно столько, сколько наёмник стоит. Иначе он
    // висит в шторке и после ухода наёмника — зовёт туда, где никого нет.
    expect(job['expiresAfter'],
        Duration(seconds: Tuning.forkWaitAwaySeconds.round()));
  });

  test('вместе с зовом к развилке ставится и весть о гибели', () {
    // Пока приложение закрыто, переставить будильник некому: отрезок до
    // развилки кончается раньше спуска, и на одном уведомлении игрок,
    // проспавший развилку, не узнавал о спуске больше ничего — наёмник
    // доходил и погибал в тишине.
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    final ahead = notifier.last(GameController.runEndIdFor(contract))!;
    expect(ahead['atFork'], isFalse, reason: 'это весть о гибели');
    expect((ahead['when']! as DateTime).isAfter(contract.segmentEndsAtUtc!),
        isTrue);
    expect(ahead['expiresAfter'], isNull,
        reason: 'добыча ждёт сколько угодно — этому уведомлению не истекать');

    // И она сбывается: наёмник, не дождавшийся игрока, доходит спуск сам
    // ровно к этому времени.
    clock = contract.segmentEndsAtUtc!
        .add(Duration(seconds: Tuning.forkWaitAwaySeconds.round() + 1));
    controller.tick();

    expect(contract.segmentEndsAtUtc!.difference(ahead['when']! as DateTime).abs(),
        lessThan(const Duration(seconds: 2)),
        reason: 'взгляд вперёд считал тот же спуск и тот же простой');
  });

  test('не дождавшийся наёмник переставляет уведомление на конец спуска', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    final arrivedAt = contract.segmentEndsAtUtc!;

    clock = arrivedAt.add(const Duration(seconds: 1));
    controller.tick();
    expect(contract.atFork, isTrue);

    clock = arrivedAt
        .add(Duration(seconds: Tuning.forkWaitAwaySeconds.round() + 1));
    controller.tick();

    expect(contract.atFork, isFalse, reason: 'терпение кончилось');
    final job = notifier.last(GameController.notificationIdFor(contract))!;
    expect(job['atFork'], isFalse);
    expect(job['when'], contract.segmentEndsAtUtc);
  });

  test('решение на развилке переставляет уведомление на следующий отрезок', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;
    final first = contract.segmentEndsAtUtc!;

    clock = first.add(const Duration(seconds: 1));
    controller.tick();
    expect(contract.atFork, isTrue);

    final aheadBefore =
        notifier.last(GameController.runEndIdFor(contract))!['when'];

    expect(controller.chooseFork(contract, 0), isTrue);
    final job = notifier.last(GameController.notificationIdFor(contract))!;
    expect(job['when'], contract.segmentEndsAtUtc);
    expect(job['when'], isNot(first), reason: 'новый отрезок — новое время');

    // Решение игрока меняет и спуск, и то, когда он кончится: взгляд вперёд
    // пересчитывается от нового пути, а не остаётся от предсказания приказа.
    expect(notifier.last(GameController.runEndIdFor(contract))!['when'],
        isNot(aheadBefore));
  });

  test('забор добычи снимает уведомление', () {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    clock = contract.segmentEndsAtUtc!.add(const Duration(days: 1));
    controller.tick();
    controller.collect(contract);

    expect(
        notifier.cancelled,
        containsAll([
          GameController.notificationIdFor(contract),
          GameController.runEndIdFor(contract),
        ]));
  });

  test('разрешение спрашивается при отправке и один раз', () async {
    // Спрашивалось «после первой гибели» — это стоило первого спуска:
    // наёмник встаёт на развилке через минуты после отправки, разрешения к
    // тому моменту ещё нет, и система молча выбрасывает единственное
    // уведомление, ради которого игру закрывают.
    //
    // Спрашивалось и «на загрузке» — системный диалог вставал ровно поверх
    // вступительного окна первого запуска (проверено на телефоне). Отправка —
    // и не поздно, и есть о чём: наёмник только что ушёл вниз.
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

  test('отправка сама спрашивает разрешение, и только первая', () async {
    expect(notifier.permissionAsks, 0);

    final first = controller.profile.roster.reserve.first;
    controller.deploy(first);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.permissionAsks, 1,
        reason: 'наёмник ушёл вниз — вот теперь уведомлять есть о чём');

    // Второй отправки системный диалог не заслуживает: отказ есть отказ.
    clock = clock.add(const Duration(days: 1));
    controller.tick();
    for (final c in [...controller.collectableContracts]) {
      controller.collect(c);
    }
    controller.refreshTavern();
    final next = controller.profile.tavernCandidates.first;
    controller.profile.gold = 1e6;
    controller.hire(next);
    controller.deploy(next);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.permissionAsks, 1);
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
