/// Одна проблема в контенте: путь до поля и что с ним не так.
class ContentIssue {
  const ContentIssue(this.path, this.message);

  /// Путь вида `abilities[3].params.cooldown` — по нему опечатка находится
  /// в файле сразу, без поиска по тексту ошибки.
  final String path;

  final String message;

  @override
  String toString() => '$path — $message';
}

/// Накопитель проблем.
///
/// Валидатор, падающий на первой ошибке, заставляет чинить контент по одной
/// опечатке за прогон: правка, перезапуск, следующая опечатка. Здесь ошибки
/// копятся, и один прогон даёт полный список.
class ContentIssues {
  final List<ContentIssue> _issues = [];

  List<ContentIssue> get all => List.unmodifiable(_issues);

  bool get isEmpty => _issues.isEmpty;
  bool get isNotEmpty => _issues.isNotEmpty;
  int get length => _issues.length;

  void add(String path, String message) =>
      _issues.add(ContentIssue(path, message));

  void throwIfAny() {
    if (_issues.isNotEmpty) throw ContentException(all);
  }

  @override
  String toString() => _issues.map((i) => '  $i').join('\n');
}

/// Контент не прошёл валидацию.
///
/// Бросается только на границе загрузки. Игра с битым контентом стартовать не
/// должна: молча подставленное значение по умолчанию — это неправильный
/// баланс, который никто не заметит.
class ContentException implements Exception {
  const ContentException(this.issues);

  final List<ContentIssue> issues;

  @override
  String toString() => 'Контент не прошёл валидацию, проблем: '
      '${issues.length}\n${issues.map((i) => '  $i').join('\n')}';
}
