/// Что пришлось выкинуть или починить при загрузке сейва.
///
/// Не ошибка. Сейв обязан открываться, даже если контент с тех пор изменился:
/// удалённый аффикс, переименованный реликт, способность, вырезанная между
/// версиями. Альтернатива — «сейв повреждён» на ровном месте, то есть
/// потерянный аккаунт из-за правки JSON.
class SaveIssue {
  const SaveIssue(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path — $message';
}

/// Накопитель претензий к сейву.
class SaveIssues {
  final List<SaveIssue> _issues = [];

  List<SaveIssue> get all => List.unmodifiable(_issues);

  bool get isEmpty => _issues.isEmpty;
  bool get isNotEmpty => _issues.isNotEmpty;
  int get length => _issues.length;

  void add(String path, String message) =>
      _issues.add(SaveIssue(path, message));

  @override
  String toString() => _issues.map((i) => '  $i').join('\n');
}

/// Сейв не удалось прочитать вообще: битый JSON, отсутствующая версия,
/// версия из будущего. В отличие от [SaveIssues] это уже отказ.
class SaveException implements Exception {
  const SaveException(this.message);

  final String message;

  @override
  String toString() => 'Сейв не прочитан: $message';
}
