import 'content_issue.dart';

/// Типизированное чтение JSON с накоплением ошибок и путём до поля.
///
/// Обращение к отсутствующему или неправильному по типу полю не бросает
/// исключение, а записывает проблему и возвращает подстановочное значение.
/// Смысл тот же, что у [ContentIssues]: один прогон должен показать весь
/// список поломок в файле, а не первую из них.
class JsonNode {
  const JsonNode(this.raw, {required this.path, required this.issues});

  /// Корень файла. `name` — имя файла без расширения, оно становится началом
  /// всех путей в сообщениях.
  factory JsonNode.root(Object? raw, String name, ContentIssues issues) {
    if (raw is! Map) {
      issues.add(name, 'ожидался объект в корне файла');
      return JsonNode(const <String, dynamic>{}, path: name, issues: issues);
    }
    return JsonNode(raw, path: name, issues: issues);
  }

  final Object? raw;
  final String path;
  final ContentIssues issues;

  bool get isMap => raw is Map;

  Map<String, dynamic> get _map =>
      raw is Map ? (raw as Map).cast<String, dynamic>() : const {};

  String _at(String key) => path.isEmpty ? key : '$path.$key';

  bool has(String key) => _map.containsKey(key);

  /// Проверка на неизвестные поля.
  ///
  /// Это главная ценность валидатора: `"cooldwn": 3.0` без такой проверки
  /// молча превращается в способность с нулевой перезарядкой. Ключи,
  /// начинающиеся с `_`, — комментарии в контенте, они легальны всегда.
  void checkKeys(Set<String> known) {
    if (!isMap) {
      issues.add(path, 'ожидался объект');
      return;
    }
    for (final key in _map.keys) {
      if (key.startsWith('_')) continue;
      if (!known.contains(key)) issues.add(_at(key), 'неизвестное поле');
    }
  }

  // --- Скаляры ---------------------------------------------------------------

  double dbl(String key, {double? or}) {
    final v = _map[key];
    if (v == null) {
      if (or != null) return or;
      issues.add(_at(key), 'обязательное число отсутствует');
      return 0.0;
    }
    if (v is num) return v.toDouble();
    issues.add(_at(key), 'ожидалось число, получено «$v»');
    return or ?? 0.0;
  }

  int integer(String key, {int? or}) {
    final v = _map[key];
    if (v == null) {
      if (or != null) return or;
      issues.add(_at(key), 'обязательное целое отсутствует');
      return 0;
    }
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    issues.add(_at(key), 'ожидалось целое, получено «$v»');
    return or ?? 0;
  }

  String str(String key, {String? or}) {
    final v = _map[key];
    if (v == null) {
      if (or != null) return or;
      issues.add(_at(key), 'обязательная строка отсутствует');
      return '';
    }
    if (v is String) return v;
    issues.add(_at(key), 'ожидалась строка, получено «$v»');
    return or ?? '';
  }

  bool flag(String key, {bool or = false}) {
    final v = _map[key];
    if (v == null) return or;
    if (v is bool) return v;
    issues.add(_at(key), 'ожидалось true/false, получено «$v»');
    return or;
  }

  // --- Составные -------------------------------------------------------------

  /// Вложенный объект. Отсутствующий возвращается пустым узлом: чтения из него
  /// сами доложат, чего не хватает, — двойной ошибки не будет.
  JsonNode child(String key, {bool required = false}) {
    final v = _map[key];
    if (v == null) {
      if (required) issues.add(_at(key), 'обязательный объект отсутствует');
      return JsonNode(const <String, dynamic>{},
          path: _at(key), issues: issues);
    }
    if (v is! Map) {
      issues.add(_at(key), 'ожидался объект, получено «$v»');
      return JsonNode(const <String, dynamic>{},
          path: _at(key), issues: issues);
    }
    return JsonNode(v, path: _at(key), issues: issues);
  }

  /// Массив объектов. Путь каждого элемента получает индекс.
  List<JsonNode> children(String key, {bool required = true}) {
    final v = _map[key];
    if (v == null) {
      if (required) issues.add(_at(key), 'обязательный массив отсутствует');
      return const [];
    }
    if (v is! List) {
      issues.add(_at(key), 'ожидался массив, получено «$v»');
      return const [];
    }
    final out = <JsonNode>[];
    for (var i = 0; i < v.length; i++) {
      out.add(JsonNode(v[i], path: '${_at(key)}[$i]', issues: issues));
    }
    return out;
  }

  List<String> strList(String key, {bool required = false}) {
    final v = _map[key];
    if (v == null) {
      if (required) issues.add(_at(key), 'обязательный массив отсутствует');
      return const [];
    }
    if (v is! List) {
      issues.add(_at(key), 'ожидался массив строк, получено «$v»');
      return const [];
    }
    final out = <String>[];
    for (var i = 0; i < v.length; i++) {
      final item = v[i];
      if (item is String) {
        out.add(item);
      } else {
        issues.add('${_at(key)}[$i]', 'ожидалась строка, получено «$item»');
      }
    }
    return out;
  }

  /// Карта «имя значения перечисления -> число». Так заданы сопротивления
  /// мобов: `{"fire": 40.0, "cold": -25.0}`.
  Map<T, double> enumDoubleMap<T extends Enum>(String key, List<T> values) {
    final v = _map[key];
    if (v == null) return const {};
    return JsonNode(v, path: _at(key), issues: issues)
        .asEnumDoubleMap(values);
  }

  /// То же, но узел САМ является такой картой — так заданы эффекты
  /// модификаторов этажа.
  Map<T, double> asEnumDoubleMap<T extends Enum>(
    List<T> values, {
    String unknownMessage = 'неизвестное значение',
  }) {
    if (raw is! Map) {
      issues.add(path, 'ожидался объект, получено «$raw»');
      return const {};
    }
    final out = <T, double>{};
    (raw as Map).forEach((rawKey, rawValue) {
      final name = '$rawKey';
      final match = _byName(values, name);
      if (match == null) {
        issues.add('$path.$name', '$unknownMessage, '
            'допустимы: ${_names(values)}');
        return;
      }
      if (rawValue is num) {
        out[match] = rawValue.toDouble();
      } else {
        issues.add('$path.$name', 'ожидалось число, получено «$rawValue»');
      }
    });
    return out;
  }

  /// Значение перечисления по имени. Список допустимых значений в сообщении
  /// обязателен: без него опечатка в теге ищется по коду, а не по ошибке.
  T? enumByName<T extends Enum>(String key, List<T> values, {T? or}) {
    final v = _map[key];
    if (v == null) {
      if (or != null) return or;
      issues.add(_at(key), 'обязательное поле отсутствует, '
          'допустимы: ${_names(values)}');
      return null;
    }
    if (v is! String) {
      issues.add(_at(key), 'ожидалась строка, получено «$v»');
      return or;
    }
    final match = _byName(values, v);
    if (match == null) {
      issues.add(_at(key), 'неизвестное значение «$v», '
          'допустимы: ${_names(values)}');
      return or;
    }
    return match;
  }

  /// Значения перечисления из массива строк — теги способности, например.
  List<T> enumList<T extends Enum>(String key, List<T> values) {
    final out = <T>[];
    final raw = _map[key];
    if (raw == null) return out;
    if (raw is! List) {
      issues.add(_at(key), 'ожидался массив, получено «$raw»');
      return out;
    }
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! String) {
        issues.add('${_at(key)}[$i]', 'ожидалась строка, получено «$item»');
        continue;
      }
      final match = _byName(values, item);
      if (match == null) {
        issues.add('${_at(key)}[$i]',
            'неизвестное значение «$item», допустимы: ${_names(values)}');
        continue;
      }
      out.add(match);
    }
    return out;
  }

  static T? _byName<T extends Enum>(List<T> values, String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static String _names<T extends Enum>(List<T> values) =>
      values.map((v) => v.name).join(', ');
}
