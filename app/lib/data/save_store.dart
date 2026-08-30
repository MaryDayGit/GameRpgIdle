import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_issue.dart';

/// Хранилище сейва на диске.
///
/// Один файл, а не база: сохраняемого состояния тут десятки килобайт
/// (`docs/02-TECH.md` §4).
///
/// Запись обязана быть атомарной. Процесс, убитый системой ровно в момент
/// записи, — это не редкость, а обычное дело на Android: приложение свернули,
/// память понадобилась, процесс сняли. Записывать поверх боевого файла значит
/// иметь шанс потерять аккаунт при каждом сворачивании.
class SaveStore {
  SaveStore(this.directory, {this.fileName = 'rift.save.json'});

  /// Хранилище в каталоге документов приложения.
  static Future<SaveStore> forApp() async =>
      SaveStore(await getApplicationDocumentsDirectory());

  final Directory directory;
  final String fileName;

  File get _file => File('${directory.path}/$fileName');
  File get _temp => File('${directory.path}/$fileName.tmp');
  File get _backup => File('${directory.path}/$fileName.bak');

  bool get exists => _file.existsSync() || _backup.existsSync();

  /// Читает сейв. `null` — сейва ещё нет, играем с чистого листа.
  ///
  /// Если основной файл не читается, пробуется резервная копия: она остаётся
  /// от предыдущей успешной записи, и потерять один автосейв гораздо лучше,
  /// чем весь прогресс.
  Future<SaveData?> load() async {
    final primary = await _tryRead(_file);
    if (primary != null) return primary;

    final fallback = await _tryRead(_backup);
    if (fallback != null) return fallback;

    if (_file.existsSync() || _backup.existsSync()) {
      throw const SaveException('файл есть, но не читается ни он, ни копия');
    }
    return null;
  }

  Future<SaveData?> _tryRead(File file) async {
    if (!file.existsSync()) return null;
    try {
      return SaveData.decode(await file.readAsString());
    } on SaveException {
      return null;
    }
  }

  /// Записывает сейв через временный файл.
  ///
  /// Порядок именно такой и не сокращается: переименование поверх
  /// существующего файла на Windows не проходит, а удалять боевой файл перед
  /// переименованием — это то самое окно, ради закрытия которого всё и
  /// затевалось. Поэтому старый файл сначала становится копией.
  Future<void> save(SaveData data) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final handle = await _temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeString(data.encode());
      await handle.flush();
    } finally {
      await handle.close();
    }

    if (_file.existsSync()) {
      if (_backup.existsSync()) await _backup.delete();
      await _file.rename(_backup.path);
    }
    await _temp.rename(_file.path);
  }

  Future<void> deleteAll() async {
    for (final file in [_file, _temp, _backup]) {
      if (file.existsSync()) await file.delete();
    }
  }
}

/// Когда сохранять.
///
/// Два повода: приложение уходит в фон и таймер. Свёртывание — главный, потому
/// что после него процесс может не проснуться; таймер — страховка на случай,
/// когда игрок закрывает приложение способом, не дающим досохраниться.
class SaveScheduler with WidgetsBindingObserver {
  SaveScheduler({
    required this.store,
    required this.snapshot,
    this.interval = const Duration(seconds: 60),
  });

  final SaveStore store;

  /// Как получить текущее состояние. Функция, а не ссылка на профиль: сохранять
  /// нужно то, что есть на момент записи, а не то, что было на момент подписки.
  final SaveData Function() snapshot;

  final Duration interval;

  Timer? _timer;
  Future<void>? _chain;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => saveNow());
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      saveNow();
    }
  }

  /// Сохраняет немедленно.
  ///
  /// Записи выстраиваются в очередь, а не отбрасываются: две одновременные
  /// записи в один временный файл затёрли бы друг друга, но и «пропустить,
  /// раз уже пишем» нельзя — тогда `await saveNow()` перестаёт что-либо
  /// гарантировать, и последнее действие игрока теряется ровно тогда, когда
  /// приложение закрывают сразу после него.
  Future<void> saveNow() {
    final next = (_chain ?? Future<void>.value())
        .then((_) => store.save(snapshot()));
    _chain = next.catchError((_) {});
    return next;
  }
}
