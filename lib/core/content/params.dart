import 'json_node.dart';

/// Блок `params` контента после валидации.
///
/// Формы у разных `kind` разные, поэтому типизировать блок полями нельзя —
/// но и оставлять сырую карту тоже нельзя: рантайм способностей начнёт
/// приводить типы вручную в каждой ветке. Здесь — середина: доступ типизован,
/// а схему конкретного `kind` проверяет [ParamSpec] на загрузке.
class Params {
  const Params(this._raw);

  static const Params empty = Params(<String, dynamic>{});

  final Map<String, dynamic> _raw;

  bool has(String key) => _raw.containsKey(key);

  double dbl(String key, [double or = 0.0]) {
    final v = _raw[key];
    return v is num ? v.toDouble() : or;
  }

  int integer(String key, [int or = 0]) {
    final v = _raw[key];
    return v is num ? v.toInt() : or;
  }

  String str(String key, [String or = '']) {
    final v = _raw[key];
    return v is String ? v : or;
  }

  bool flag(String key, [bool or = false]) {
    final v = _raw[key];
    return v is bool ? v : or;
  }

  Map<String, dynamic> get raw => Map.unmodifiable(_raw);

  @override
  String toString() => 'Params($_raw)';
}

enum ParamType { number, integer, text, boolean }

/// Ожидаемое поле в блоке `params`.
class ParamSpec {
  const ParamSpec(this.key, this.type, {this.optional = false});

  const ParamSpec.number(String key, {bool optional = false})
      : this(key, ParamType.number, optional: optional);

  const ParamSpec.integer(String key, {bool optional = false})
      : this(key, ParamType.integer, optional: optional);

  const ParamSpec.text(String key, {bool optional = false})
      : this(key, ParamType.text, optional: optional);

  const ParamSpec.boolean(String key, {bool optional = false})
      : this(key, ParamType.boolean, optional: optional);

  final String key;
  final ParamType type;
  final bool optional;
}

/// Проверяет блок `params` по схеме конкретного `kind` и возвращает его.
///
/// Проверяются обе стороны: и что нужное есть нужного типа, и что лишнего нет.
/// Вторая половина важнее первой — отсутствующий параметр обычно виден по
/// поведению, а лишний (то есть опечатка в имени нужного) не виден никак.
Params readParams(JsonNode owner, List<ParamSpec> specs) {
  final node = owner.child('params');

  for (final spec in specs) {
    if (!node.has(spec.key)) {
      if (!spec.optional) {
        owner.issues.add('${node.path}.${spec.key}', 'параметр отсутствует');
      }
      continue;
    }
    switch (spec.type) {
      case ParamType.number:
        node.dbl(spec.key);
      case ParamType.integer:
        node.integer(spec.key);
      case ParamType.text:
        node.str(spec.key);
      case ParamType.boolean:
        node.flag(spec.key);
    }
  }

  node.checkKeys({for (final s in specs) s.key});

  return Params(node.raw is Map
      ? (node.raw as Map).cast<String, dynamic>()
      : const <String, dynamic>{});
}
