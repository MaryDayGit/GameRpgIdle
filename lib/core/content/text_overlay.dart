/// Перевод контента накладкой поверх исходного JSON.
///
/// Числа баланса и тексты живут в одном файле — `assets/content/*.json`, — и
/// это правильно: правя урон способности, автор видит её описание рядом.
/// Но перевод в тот же файл класть нельзя. Таблицы `balance/*.md`, которые
/// правятся с телефона, генерируются из этих же файлов; каждая вторая строка
/// в них стала бы английской, а diff правки баланса — нечитаемым.
///
/// Поэтому переводы лежат отдельно, по одному файлу на язык:
/// `assets/content/en/abilities.json`. Накладка знает только идентификаторы и
/// строки — ни одного числа, — и применяется к СЫРОМУ JSON до разбора.
///
/// Ключевое следствие: разборщики (`ability_def.dart` и соседи) о переводе не
/// знают вовсе и остаются одним местом, где проверяется контент. Накладка,
/// подставившая мусор, падает на том же валидаторе, что и опечатка в
/// исходнике, — а не тихо доезжает до экрана.
library;

/// Как называется поле в исходнике и как — в накладке.
///
/// Совпадают все, кроме одного: в исходнике текст лежит в поле `ru` (язык —
/// свойство поля), в накладке — в `name` (язык — свойство файла). Держать в
/// английском файле поле с именем `ru` было бы ровно тем сортом мелочи, из-за
/// которой через полгода никто не понимает, что там лежит.
const _sourceToOverlay = {
  'ru': 'name',
  'text': 'text',
  'role': 'role',
  'plus': 'plus',
  'minus': 'minus',
  'about': 'about',
};

/// Поля исходника, в которых лежит текст для игрока.
const translatableFields = {'ru', 'text', 'role', 'plus', 'minus', 'about'};

/// Чем запись контента опознаётся в накладке.
///
/// Почти везде это `id`. Имплициты в `items.json` идентифицируются типом
/// предмета (`kind`) — своего `id` у них нет и заводить его ради перевода
/// значило бы менять контент под инструмент, а не наоборот.
String? entryKey(Map<Object?, Object?> node) {
  final id = node['id'];
  if (id is String) return id;
  final kind = node['kind'];
  if (kind is String) return kind;
  return null;
}

class TextOverlay {
  const TextOverlay(this.entries);

  /// Пусто — язык оригинала: накладывать нечего, и это не ошибка.
  const TextOverlay.none() : entries = const {};

  /// `идентификатор -> {поле накладки -> строка}`.
  final Map<String, Map<String, String>> entries;

  bool get isEmpty => entries.isEmpty;

  /// Разбирает файл накладки.
  ///
  /// Мягко: неизвестное поле и запись не той формы пропускаются, а не роняют
  /// загрузку. Перевод — это не баланс: недоперевод должен показать русскую
  /// строку, а не запретить игру. Строгость остаётся там, где она уместна, —
  /// в `tool/l10n.dart --check`, который сверяет накладку с исходником и
  /// говорит, что осталось.
  factory TextOverlay.fromJson(Object? raw) {
    if (raw is! Map) return const TextOverlay.none();
    final entries = raw['entries'];
    if (entries is! Map) return const TextOverlay.none();

    final out = <String, Map<String, String>>{};
    for (final entry in entries.entries) {
      final key = entry.key;
      final fields = entry.value;
      if (key is! String || fields is! Map) continue;

      final strings = <String, String>{};
      for (final field in fields.entries) {
        final name = field.key;
        final value = field.value;
        if (name is String && value is String && value.isNotEmpty) {
          strings[name] = value;
        }
      }
      if (strings.isNotEmpty) out[key] = strings;
    }
    return TextOverlay(out);
  }

  /// Накладывает перевод на сырой JSON одного файла контента.
  ///
  /// Возвращает НОВОЕ дерево, а не правит исходное: `ContentBundle` держит
  /// сырые карты, чтобы отправлять их в фоновый изолят, и правка на месте
  /// означала бы, что переключение языка портит то, что уже отправлено.
  ///
  /// Обход не знает форму файлов. Способности лежат списком, узлы дерева —
  /// внутри веток, задания — внутри цепей, и перечислять эти пути значило бы
  /// завести второе описание контента, которое разойдётся с первым при первой
  /// же новой сущности. Вместо этого правило одно: **любая карта, у которой
  /// есть опознаваемый ключ и переводимое поле, — запись.**
  Object? applyTo(Object? node) {
    if (isEmpty) return node;
    return _walk(node);
  }

  Object? _walk(Object? node) {
    if (node is List) return [for (final item in node) _walk(item)];
    if (node is! Map) return node;

    final copy = <String, Object?>{
      for (final entry in node.entries)
        '${entry.key}': _walk(entry.value),
    };

    final key = entryKey(node);
    if (key == null) return copy;

    final translated = entries[key];
    if (translated == null) return copy;

    for (final field in translatableFields) {
      if (!copy.containsKey(field)) continue;
      final replacement = translated[_sourceToOverlay[field]!];
      if (replacement != null) copy[field] = replacement;
    }
    return copy;
  }

  /// Накладывает перевод на весь пакет: `имя файла -> разобранный JSON`.
  ///
  /// Файл без накладки проходит как есть — это и есть откат на язык
  /// оригинала, и он работает по частям: переведённые способности читаются
  /// по-английски, ещё не переведённые задания — по-русски. Игра не ждёт,
  /// пока перевод дойдёт до конца.
  static Map<String, Object?> applyAll(
    Map<String, Object?> raw,
    Map<String, TextOverlay> overlays,
  ) =>
      {
        for (final entry in raw.entries)
          entry.key:
              (overlays[entry.key] ?? const TextOverlay.none()).applyTo(entry.value),
      };
}
