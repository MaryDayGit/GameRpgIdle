import 'package:flutter/foundation.dart';
import 'package:rift/core/telemetry/analytics_event.dart';
import 'package:rift/core/telemetry/analytics_sink.dart';

export 'package:rift/core/telemetry/analytics_event.dart';
export 'package:rift/core/telemetry/analytics_sink.dart';
export 'package:rift/core/telemetry/game_events.dart';

/// Аналитика приложения: один вход, за которым может стоять кто угодно.
///
/// Игра ничего не знает ни про Firebase, ни про сеть — она зовёт [log] с
/// событием из `GameEvents`. Всё остальное здесь: выключатель игрока,
/// свойства профиля, приведение к лимитам GA4 и обещание не падать.
///
/// ## Три правила
///
/// **Аналитика не роняет игру.** Каждый вызов обёрнут в `try`. Счётчик,
/// уронивший спуск, — это не счётчик, а баг; отправить событие всегда менее
/// важно, чем доиграть.
///
/// **Аналитика молчит, если игрок сказал молчать.** [enabled] проверяется
/// здесь, в одном месте, а не в двадцати точках вызова. Выключенная
/// аналитика не буферизует «на потом»: выключено значит выключено.
///
/// **Схема ловится дома.** В отладочной сборке событие, которое GA4 обрежет,
/// печатается в консоль с объяснением (см. [AnalyticsEvent.problems]).
/// В релизе оно молча приводится к допустимому: терять данные плохо, но
/// падать на телефоне игрока хуже.
class Analytics {
  Analytics({
    AnalyticsSink sink = const NoopAnalyticsSink(),
    bool enabled = true,
  })  : _sink = sink,
        _enabled = enabled;

  final AnalyticsSink _sink;

  bool _enabled;
  bool get enabled => _enabled;

  /// Переключатель из настроек. Выключение доходит до самого поставщика
  /// (`setCollectionEnabled`), а не только до этого класса: иначе Firebase
  /// продолжил бы слать собственные автоматические события — `session_start`,
  /// `screen_view`, — про которые игрок ничего не выключал.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _guard(() => _sink.setCollectionEnabled(value));
  }

  /// Уже отправленные свойства. Свойство постоянно, пока его не поменяли, и
  /// слать «Клеймо = 2» после каждого спуска значит тратить бюджет вызовов
  /// на то, что уже записано.
  final Map<String, String?> _properties = {};

  void log(AnalyticsEvent event) {
    if (!_enabled) return;

    if (kDebugMode) {
      final problems = event.problems;
      if (problems.isNotEmpty) {
        debugPrint('[analytics] событие "${event.name}" GA4 испортит:');
        for (final p in problems) {
          debugPrint('[analytics]   - $p');
        }
      }
    }

    _guard(() => _sink.log(event.sanitized()));
  }

  /// Свойства профиля пачкой — так их и собирает `GameEvents.properties`.
  /// Неизменившиеся не отправляются.
  void setProperties(Map<String, String> values) {
    if (!_enabled) return;
    values.forEach(setProperty);
  }

  void setProperty(String name, String? value) {
    if (!_enabled) return;
    final (key, clean) = AnalyticsEvent.property(name, value);
    if (_properties[key] == clean) return;
    _properties[key] = clean;
    _guard(() => _sink.setProperty(key, clean));
  }

  /// Ошибка внутри аналитики — это ошибка аналитики, а не игры.
  void _guard(void Function() action) {
    try {
      action();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[analytics] отправка не удалась: $e');
    }
  }
}

/// Печатает события в консоль. Нужен ровно там, где Firebase бесполезен: на
/// эмуляторе и в дев-прогоне видно СРАЗУ, что событие ушло и с чем, — а в
/// консоли Firebase то же самое появится через часы.
class DebugAnalyticsSink implements AnalyticsSink {
  const DebugAnalyticsSink();

  @override
  void log(AnalyticsEvent event) => debugPrint('[analytics] $event');

  @override
  void setProperty(String name, String? value) =>
      debugPrint('[analytics] property $name = $value');

  @override
  void setCollectionEnabled(bool enabled) =>
      debugPrint('[analytics] collection = $enabled');
}
