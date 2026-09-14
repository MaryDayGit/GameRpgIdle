/// Одно измерение: имя события и его параметры.
///
/// Чистый Dart, как и всё остальное в ядре. Событие — это ЗНАЧЕНИЕ, а не
/// вызов: его можно построить в headless-тесте, сравнить с ожидаемым и не
/// поднимать ни Flutter, ни сеть. Отправкой занимается [AnalyticsSink] в
/// приложении.
///
/// ## Почему здесь живут ограничения GA4
///
/// Firebase Analytics отбрасывает то, что не влезло в его лимиты, **молча**.
/// Слишком длинное имя события, двадцать шестой параметр, строка на 120
/// символов — ничего не падает, в логе приложения пусто, а в отчёте через
/// сутки просто нет колонки. Узнать об этом можно только через сутки и только
/// если знать, что искать.
///
/// Поэтому лимиты записаны здесь, в ядре, и стерегутся тестом
/// (`test/telemetry_test.dart`): каталог событий целиком прогоняется через
/// [problems], и любое новое событие, которое GA4 обрежет, роняет тест на
/// машине разработчика, а не теряет данные на телефонах игроков.
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.params = const {}]);

  final String name;

  /// Значения: `String`, `int`, `double`, `bool`. Ничего другого GA4 не
  /// принимает; `bool` он тоже не принимает — [sanitized] переводит его в
  /// 0/1, потому что писать это в каждом конструкторе события значило бы
  /// девять шансов забыть.
  final Map<String, Object?> params;

  // --- Лимиты GA4 (Firebase Analytics, Android) ------------------------------

  static const int nameMaxLength = 40;
  static const int paramNameMaxLength = 40;
  static const int paramValueMaxLength = 100;
  static const int paramsMax = 25;
  static const int propertyNameMaxLength = 24;
  static const int propertyValueMaxLength = 36;

  /// Префиксы, зарезервированные Google. Событие с таким именем не
  /// отправляется вовсе.
  static const List<String> reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  static final RegExp _validName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  /// Что в этом событии GA4 испортит или выбросит. Пустой список — событие
  /// дойдёт целиком.
  List<String> get problems {
    final out = <String>[];

    if (!_validName.hasMatch(name)) {
      out.add('имя "$name": только буквы, цифры и подчёркивание, '
          'начинается с буквы');
    }
    if (name.length > nameMaxLength) {
      out.add('имя "$name": ${name.length} символов, максимум $nameMaxLength');
    }
    for (final prefix in reservedPrefixes) {
      if (name.toLowerCase().startsWith(prefix)) {
        out.add('имя "$name": префикс "$prefix" зарезервирован Google');
      }
    }
    if (params.length > paramsMax) {
      out.add('$name: ${params.length} параметров, максимум $paramsMax');
    }

    params.forEach((key, value) {
      if (!_validName.hasMatch(key)) {
        out.add('$name.$key: недопустимое имя параметра');
      }
      if (key.length > paramNameMaxLength) {
        out.add('$name.$key: ${key.length} символов в имени, '
            'максимум $paramNameMaxLength');
      }
      if (value is String && value.length > paramValueMaxLength) {
        out.add('$name.$key: строка ${value.length} символов, '
            'максимум $paramValueMaxLength');
      }
      if (value != null &&
          value is! String &&
          value is! int &&
          value is! double &&
          value is! bool) {
        out.add('$name.$key: тип ${value.runtimeType} GA4 не принимает');
      }
    });

    return out;
  }

  /// Приводит событие к тому, что GA4 действительно примет.
  ///
  /// Обрезает, а не выбрасывает: половина параметра полезнее, чем его
  /// отсутствие. Единственное, что выбрасывается целиком, — `null`
  /// (у GA4 нет пустого значения, параметр с ним просто не существует).
  ///
  /// Вызывается на отправке, но НЕ отменяет [problems]: тест обязан ловить
  /// такие события до сборки, потому что обрезанное имя события — это ещё и
  /// склейка двух разных событий в одно.
  AnalyticsEvent sanitized() {
    final cleanParams = <String, Object?>{};
    for (final entry in params.entries) {
      if (cleanParams.length >= paramsMax) break;
      final value = entry.value;
      if (value == null) continue;

      final key = _trim(_normalize(entry.key), paramNameMaxLength);
      if (key.isEmpty) continue;

      cleanParams[key] = switch (value) {
        bool b => b ? 1 : 0,
        String s => _trim(s, paramValueMaxLength),
        _ => value,
      };
    }
    return AnalyticsEvent(
      _trim(_normalize(name), nameMaxLength),
      cleanParams,
    );
  }

  /// Имя свойства игрока и его значение по лимитам GA4. Свойства строже
  /// событий: 24 символа на имя, 36 на значение.
  static (String, String?) property(String name, String? value) => (
        _trim(_normalize(name), propertyNameMaxLength),
        value == null ? null : _trim(value, propertyValueMaxLength),
      );

  /// Приводит имя к допустимому: нижний регистр, недопустимое — в
  /// подчёркивание. Имя, начавшееся не с буквы, получает `e_`: пустая строка
  /// GA4 не имя, а отброшенное событие.
  static String _normalize(String raw) {
    final buffer = StringBuffer();
    for (final code in raw.toLowerCase().codeUnits) {
      final isDigit = code >= 0x30 && code <= 0x39;
      final isLower = code >= 0x61 && code <= 0x7a;
      buffer.writeCharCode(
          isDigit || isLower || code == 0x5f ? code : 0x5f);
    }
    final out = buffer.toString();
    if (out.isEmpty) return 'e';
    final first = out.codeUnitAt(0);
    return first >= 0x61 && first <= 0x7a ? out : 'e_$out';
  }

  static String _trim(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  @override
  String toString() => '$name $params';
}
