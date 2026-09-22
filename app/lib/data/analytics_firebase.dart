import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// `AnalyticsEvent` и `AnalyticsSink` приезжают отсюда же: фасад их
// переэкспортирует, и второй импорт тех же имён из ядра — это второе место,
// которое придётся править при переезде.
import 'analytics.dart';

/// Firebase Analytics (GA4) как сток измерений.
///
/// Выбор поставщика объяснён в `docs/11-ANALYTICS.md` §1; здесь важны два
/// следствия, которые видны прямо в коде.
///
/// **Отправка ничего не ждёт.** `logEvent` возвращает `Future`, и мы его не
/// ждём. Событие всё равно не уходит в сеть сразу: SDK кладёт его на диск и
/// выгружает пачкой примерно раз в час, а офлайн — при следующем запуске.
/// Для игры, в которую играют в метро, это главное свойство Firebase и
/// причина не писать свою очередь.
///
/// **Ошибка отправки не всплывает наружу.** Игрок без Play Services, игрок с
/// выключённой синхронизацией, игрок в самолёте — всё это нормальные игроки,
/// и сломать им спуск ради счётчика нельзя.
class FirebaseAnalyticsSink
    implements AnalyticsSink, ResettableAnalyticsSink {
  FirebaseAnalyticsSink._(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  void log(AnalyticsEvent event) {
    // Копия, а не `cast`: `cast` отдаёт представление, которое падает на
    // чтении, а не на создании, — то есть уже внутри плагина, где поймать
    // его нечем.
    final params = <String, Object>{
      for (final e in event.params.entries)
        if (e.value != null) e.key: e.value!,
    };
    unawaited(_analytics
        .logEvent(name: event.name, parameters: params.isEmpty ? null : params)
        .catchError(_swallow));
  }

  @override
  void setProperty(String name, String? value) =>
      unawaited(_analytics
          .setUserProperty(name: name, value: value)
          .catchError(_swallow));

  /// Новый идентификатор установки: события после удаления аккаунта не
  /// связываются с прежними.
  @override
  Future<void> resetData() => _analytics.resetAnalyticsData();

  @override
  void setCollectionEnabled(bool enabled) =>
      unawaited(_analytics
          .setAnalyticsCollectionEnabled(enabled)
          .catchError(_swallow));

  static void _swallow(Object error) {
    if (kDebugMode) debugPrint('[analytics] firebase: $error');
  }
}

/// Поднимает аналитику под сборку, в которой запущена игра.
///
/// Порядок предпочтений один и тот же в отладке и в релизе, и это нарочно:
/// сборка с настроенным Firebase шлёт события и на эмуляторе тоже — иначе
/// проверить схему до релиза было бы негде.
///
/// **Игра обязана запускаться без Firebase.** `google-services.json` — это
/// ключи проекта, их нет ни в репозитории, ни у нового разработчика, ни в
/// прогоне тестов. Поэтому неудача инициализации здесь не ошибка, а один из
/// ожидаемых исходов: аналитики нет, игра есть. Обратный порядок — «нет
/// ключей, нет игры» — стоил бы первого запуска у каждого, кто склонировал
/// репозиторий.
abstract final class AnalyticsSetup {
  static Future<Analytics> create({required bool enabled}) async {
    final sink = await _sink(enabled: enabled);
    return Analytics(sink: sink, enabled: enabled);
  }

  static Future<AnalyticsSink> _sink({required bool enabled}) async {
    try {
      // Без `firebase_options.dart`: на Android плагин Gradle разворачивает
      // `google-services.json` в ресурсы, и SDK читает их сам. Игра выходит
      // только на Android (`docs/02-TECH.md` §3), и генерировать файл
      // конфигурации через `flutterfire configure` ради одной платформы —
      // это второй источник тех же ключей и второе место, где они
      // разъезжаются.
      await Firebase.initializeApp();
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(enabled);
      return FirebaseAnalyticsSink._(analytics);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[analytics] Firebase не поднялся ($e) — '
            'события идут в консоль');
        return const DebugAnalyticsSink();
      }
      return const NoopAnalyticsSink();
    }
  }
}
