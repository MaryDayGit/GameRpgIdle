import 'analytics_event.dart';

/// Куда уходят измерения.
///
/// Интерфейс живёт в ядре, реализации — в приложении (`app/lib/data/`). Это
/// то же правило, по которому в ядре нет ни сейва, ни уведомлений: ядро
/// знает, ЧТО случилось, и не знает, куда об этом сообщать. Иначе headless
/// прогон балансировщика тянул бы за собой Firebase.
///
/// Второе следствие важнее первого: сменить поставщика аналитики — значит
/// написать один новый класс на сорок строк. Ни одно место в игре, которое
/// сообщает о событии, при этом не меняется.
abstract class AnalyticsSink {
  void log(AnalyticsEvent event);

  /// Свойство игрока: живёт на профиле, а не на событии, и попадает в разрез
  /// ко ВСЕМ его событиям — прошлым в том числе. Поэтому сюда идёт то, что
  /// описывает игрока («рекорд — 40+ этажей»), а не то, что с ним случилось.
  void setProperty(String name, String? value);

  /// Выключатель на стороне поставщика.
  ///
  /// Не то же самое, что перестать звать [log]: поставщик шлёт и собственные
  /// автоматические события — открытие приложения, начало сессии, — про
  /// которые игрок ничего не выключал. Выключить надо и их, иначе галочка в
  /// настройках выключает не то, что обещает.
  void setCollectionEnabled(bool enabled);
}

/// Ничего не делает. Значение по умолчанию везде, где сток не задан: в
/// тестах, в дев-экранах, в сборке без ключей Firebase.
///
/// Не `null`, потому что `analytics?.log(...)` в двадцати местах — это
/// двадцать шансов забыть вопросительный знак и уронить игру ради счётчика.
class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();

  @override
  void log(AnalyticsEvent event) {}

  @override
  void setProperty(String name, String? value) {}

  @override
  void setCollectionEnabled(bool enabled) {}
}

/// Складывает всё в список. Для тестов: проверяем, что отправка спуска
/// действительно порождает `run_started`, не поднимая ни сети, ни Flutter.
class RecordingAnalyticsSink implements AnalyticsSink {
  final List<AnalyticsEvent> events = [];
  final Map<String, String?> properties = {};
  bool collectionEnabled = true;

  @override
  void log(AnalyticsEvent event) => events.add(event);

  @override
  void setProperty(String name, String? value) => properties[name] = value;

  @override
  void setCollectionEnabled(bool enabled) => collectionEnabled = enabled;

  /// Все события с этим именем — в порядке отправки.
  List<AnalyticsEvent> named(String name) =>
      [for (final e in events) if (e.name == name) e];

  AnalyticsEvent? last(String name) {
    final all = named(name);
    return all.isEmpty ? null : all.last;
  }

  void clear() {
    events.clear();
    properties.clear();
  }
}
