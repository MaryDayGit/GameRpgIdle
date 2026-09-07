import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/mercenary.dart';

import '../ui/strings.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Уведомление о гибели наёмника.
///
/// Интерфейс, а не прямой вызов плагина: планирование — это решение игры
/// («когда наёмник погибнет»), а доставка — дело системы. Разделение нужно,
/// чтобы решение можно было проверить тестом, не поднимая Android.
abstract class DeathNotifier {
  /// Спрашивает разрешение. Возвращает, дано ли оно.
  Future<bool> ensurePermission();

  /// [atFork] — наёмник не погибнет, а встанет на развилке и будет ждать
  /// решения. Уведомление о гибели в этот момент было бы прямой ложью, а
  /// шторка уведомлений — единственное место, где игрок читает игру, не
  /// открывая её.
  Future<void> scheduleContractEvent({
    required int id,
    required DateTime whenUtc,
    required String mercName,
    required int depth,
    required bool atFork,
  });

  Future<void> cancel(int id);
}

/// Ничего не делает. Для тестов и для платформ без уведомлений.
class NoDeathNotifier implements DeathNotifier {
  const NoDeathNotifier();

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<void> scheduleContractEvent({
    required int id,
    required DateTime whenUtc,
    required String mercName,
    required int depth,
    required bool atFork,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}

/// Локальное уведомление через системный планировщик.
///
/// Время гибели известно точно в момент отправки — ран считается целиком, — и
/// потому уведомление ставится один раз и не требует ни фоновой службы, ни
/// пробуждений (`docs/02-TECH.md` §3).
class LocalDeathNotifier implements DeathNotifier {
  LocalDeathNotifier(this._plugin);

  static const _channelId = 'rift_descent';
  static String get _channelName => S.notificationChannel;

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  static Future<LocalDeathNotifier> create() async {
    tzdata.initializeTimeZones();

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return LocalDeathNotifier(plugin).._ready = true;
  }

  /// Разрешение спрашивается на первом запуске.
  ///
  /// Раньше — после первой гибели: вопрос там осмысленнее, игрок уже понял,
  /// что наёмник уходит надолго. Но платил за это первый спуск. Наёмник
  /// встаёт на развилке через минуты после отправки, разрешения к этому
  /// моменту ещё нет, и система выбрасывает ровно то уведомление, ради
  /// которого игру и закрывают (`docs/02-TECH.md` §3).
  @override
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;

    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> scheduleContractEvent({
    required int id,
    required DateTime whenUtc,
    required String mercName,
    required int depth,
    required bool atFork,
  }) async {
    if (!_ready) return;

    final when = tz.TZDateTime.from(whenUtc.toUtc(), tz.UTC);
    if (when.isBefore(tz.TZDateTime.now(tz.UTC))) return;

    // Род берётся из имени: половина наёмников женского рода, и «Мирена
    // погиб» — это первое, что игрок увидит в шторке уведомлений.
    final she = MercFactory.genderOf(mercName) == Gender.feminine;

    await _plugin.zonedSchedule(
      id: id,
      title: atFork
          ? S.notifyForkTitle(mercName)
          : S.notifyDeathTitle(mercName),
      body: atFork
          ? S.notifyForkBody(she: she, depth: depth)

          : S.notifyDeathBody(she: she, depth: depth),

      scheduledDate: when,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: S.notificationChannelAbout,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // Неточный будильник намеренно: точный требует отдельного разрешения,
      // которое Google Play выдаёт под обоснование, а опоздание на несколько
      // минут для сообщения «наёмник погиб» ничего не меняет.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }
}
