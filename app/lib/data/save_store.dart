import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_head.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/save/save_sync.dart';

/// Хранилище сейва на диске.
///
/// Один файл, а не база: сохраняемого состояния тут десятки килобайт
/// (`docs/02-TECH.md` §4).
///
/// Запись обязана быть атомарной. Процесс, убитый системой ровно в момент
/// записи, — это не редкость, а обычное дело на Android: приложение свернули,
/// память понадобилась, процесс сняли. Записывать поверх боевого файла значит
/// иметь шанс потерять аккаунт при каждом сворачивании.
///
/// ## Что здесь появилось вместе с облаком
///
/// **Хозяин по-прежнему этот файл.** Firestore — зеркало
/// (`cloud_save.dart`), и порядок именно такой: спуск считается на
/// устройстве и обязан считаться без сети. Всё, что добавилось, добавилось
/// ради того, чтобы зеркало можно было СВЕСТИ с оригиналом.
///
/// **Номер записи.** [revision] растёт на единицу с каждым сохранением. По
/// нему, а не по часам, решается, чей сейв чей потомок (`save_sync.dart`).
///
/// **Отметка синхронизации.** [mirroredRevision] — ревизия, на которой сейв
/// последний раз доехал в облако. Лежит В ОТДЕЛЬНОМ маленьком файле, а не
/// в самом сейве, и это не украшение: обновлять её надо сразу после
/// удачной выгрузки, а переписать ради одного числа весь сейв нельзя —
/// в памяти к этому моменту уже другое состояние, и в файле с ревизией N
/// оказалось бы не то, что уехало в облако под номером N.
///
/// **Отказы перестали быть тихими.** Битый сейв и неудачная запись
/// сообщаются через [onTrouble]. До этого и то и другое происходило молча:
/// игрок терял час прогресса, не писал в поддержку, а просто удалял игру.
class SaveStore {
  SaveStore(
    this.directory, {
    this.fileName = 'rift.save.json',
    this.deviceId = '',
    this.onTrouble,
  });

  /// Хранилище в каталоге документов приложения.
  static Future<SaveStore> forApp({String deviceId = ''}) async =>
      SaveStore(await getApplicationDocumentsDirectory(), deviceId: deviceId);

  final Directory directory;
  final String fileName;

  /// Кто пишет. Уезжает в паспорт сейва, чтобы отличить «это писали мы» от
  /// «это писал планшет».
  final String deviceId;

  /// Куда сообщать о поломках: `(вид, ступень)`. Вид — `recovered` или
  /// `failed`, ступень — что именно не получилось.
  ///
  /// Функция, а не аналитика напрямую: хранилище не должно знать ни про
  /// Firebase, ни про то, что игрок отключил статистику.
  final void Function(String kind, String stage)? onTrouble;

  File get _file => File('${directory.path}/$fileName');
  File get _temp => File('${directory.path}/$fileName.tmp');
  File get _backup => File('${directory.path}/$fileName.bak');
  File get _sync => File('${directory.path}/$fileName.sync');

  bool get exists => _file.existsSync() || _backup.existsSync();

  int _revision = 0;

  /// Знаем ли мы номер последней записи, или ещё не смотрели.
  ///
  /// Отдельный признак, а не ноль в [_revision], потому что ноль — законное
  /// значение: с него начинается и новая игра, и сезон после архива, и
  /// принятый облачный сейв с первой ревизией. Спутать «не смотрели» с
  /// «записей не было» значит один раз в жизни игрока перечитать файл там,
  /// где перечитывать нельзя.
  bool _revisionKnown = false;

  /// Номер последней записи. 0 — сейва ещё не было.
  int get revision => _revision;

  int _mirrored = 0;

  /// Ревизия, на которой сейв последний раз доехал в облако.
  int get mirroredRevision => _mirrored;

  /// Аккаунт-владелец. Ставится после входа и уезжает в паспорт: по нему
  /// видно смену аккаунта на одном телефоне.
  String? accountId;

  /// Читает паспорт, не разбирая профиль.
  ///
  /// Нужно, чтобы решить, какой сейв брать, ДО загрузки: разбор чужого сейва
  /// снисходителен (`codec.dart`) и меняет то, что сравниваешь.
  Future<SaveHead?> peek() async {
    for (final file in [_file, _backup]) {
      if (!file.existsSync()) continue;
      final head = SaveData.peek(await file.readAsString());
      if (head != null) return _withMirrored(head);
    }
    return null;
  }

  /// Читает сейв. `null` — сейва ещё нет, играем с чистого листа.
  ///
  /// Если основной файл не читается, пробуется резервная копия: она остаётся
  /// от предыдущей успешной записи, и потерять один автосейв гораздо лучше,
  /// чем весь прогресс.
  Future<SaveData?> load() async {
    _mirrored = _readMirrored();
    _revisionKnown = true;

    final primary = await _tryRead(_file);
    if (primary != null) {
      _revision = primary.revision;
      return primary;
    }

    final fallback = await _tryRead(_backup);
    if (fallback != null) {
      // Основной файл был и не открылся. Спасла копия — но узнать об этом
      // надо: битый сейв на телефоне игрока не воспроизводится дома и
      // не приходит в поддержку.
      onTrouble?.call('recovered', _file.existsSync() ? 'primary' : 'missing');
      _revision = fallback.revision;
      return fallback;
    }

    if (_file.existsSync() || _backup.existsSync()) {
      onTrouble?.call('recovered', 'both');
      throw const SaveException('файл есть, но не читается ни он, ни копия');
    }
    return null;
  }

  Future<SaveData?> _tryRead(File file) async {
    if (!file.existsSync()) return null;
    try {
      final data = SaveData.decode(await file.readAsString());
      // Отметка синхронизации берётся из своего файла и перекрывает то, что
      // записано в сейве. Источник у величины ровно один — иначе они
      // разъедутся, и разъедутся молча.
      return data.copyWith(mirroredRevision: _mirrored);
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
  ///
  /// Возвращает записанное — с проставленными номером записи, устройством и
  /// аккаунтом. Штамп ставится ЗДЕСЬ, а не у вызывающего: номер записи
  /// обязан расти ровно один раз на одну запись, и раздать эту обязанность
  /// вызывающим значит рано или поздно записать два разных сейва под одним
  /// номером.
  Future<SaveData> save(SaveData data) async {
    await _ensureRevision();

    final stamped = data.copyWith(
      revision: _revision + 1,
      mirroredRevision: _mirrored,
      deviceId: deviceId,
      accountId: accountId ?? data.accountId,
    );

    try {
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final handle = await _temp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(stamped.encode());
        await handle.flush();
      } finally {
        await handle.close();
      }

      if (_file.existsSync()) {
        if (_backup.existsSync()) await _backup.delete();
        await _file.rename(_backup.path);
      }
      await _temp.rename(_file.path);
    } on Object {
      // Кончилось место, каталог недоступен, файл занят. Игра при этом
      // выглядит работающей ровно до перезапуска, поэтому молчать нельзя.
      onTrouble?.call('failed', 'write');
      rethrow;
    }

    _revision = stamped.revision;
    return stamped;
  }

  /// Поднимает счётчик записей с диска, если его ещё не смотрели.
  ///
  /// Без этого счётчик зависел бы от того, позвали ли перед записью
  /// [load], — а такое требование не проверяется ничем и однажды будет
  /// нарушено. Цена нарушения высокая: два разных сейва под одним номером
  /// означают, что разрешение расхождений (`save_sync.dart`) считает более
  /// старый сейв потомком более нового.
  Future<void> _ensureRevision() async {
    if (_revisionKnown) return;
    _revisionKnown = true;
    _mirrored = _readMirrored();
    final head = await peek();
    if (head != null) _revision = head.revision;
  }

  /// Отмечает, что сейв доехал в облако до ревизии [revision].
  ///
  /// Отдельный маленький файл, а не поле в сейве: см. заголовок класса.
  Future<void> markMirrored(int revision) async {
    if (revision <= _mirrored) return;
    _mirrored = revision;
    try {
      await _sync.writeAsString(jsonEncode({'mirroredRevision': revision}));
    } on Object {
      // Потеря этой отметки не теряет данных: следующий запуск просто
      // посчитает сейвы разошедшимися и спросит игрока. Хуже, чем молча
      // сойтись, но лучше, чем молча затереть.
      onTrouble?.call('failed', 'sync_mark');
    }
  }

  /// Кладёт облачный сейв на место локального.
  ///
  /// Ревизия берётся ОБЛАЧНАЯ, а не следующая своя: взятый сейв — это тот же
  /// сейв, а не новая запись поверх него. Он же сразу отмечается
  /// синхронизированным — мы буквально только что его оттуда и взяли.
  Future<SaveData> adopt(SaveData cloud) async {
    _revisionKnown = true;
    _revision = cloud.revision - 1;
    final saved = await save(cloud);
    await markMirrored(saved.revision);
    return saved;
  }

  /// Убирает сейв прошлого сезона в архив и возвращает имя архива.
  ///
  /// Переименование, а не удаление. Сезон кончается — доказанное в нём нет
  /// (`rift/core/save/season.dart`), и если однажды выяснится, что обнулили
  /// не то, вернуть файл будет ровно одним переименованием обратно.
  Future<String?> archiveSeason(String seasonId) async {
    if (!_file.existsSync()) return null;

    final name = SaveSync.archiveName(fileName, seasonId);
    final target = File('${directory.path}/$name');
    try {
      if (target.existsSync()) await target.delete();
      await _file.rename(target.path);
      if (_backup.existsSync()) await _backup.delete();
      if (_sync.existsSync()) await _sync.delete();
    } on Object {
      onTrouble?.call('failed', 'archive');
      return null;
    }
    _revision = 0;
    _mirrored = 0;
    _revisionKnown = true;
    return name;
  }

  /// Убирает нечитаемый сейв в сторону.
  ///
  /// Зовётся, когда не открылись ни основной файл, ни копия. Начать новую
  /// игру поверх такого файла — значит потерять его окончательно, а он ещё
  /// может пригодиться: сейв не открывается СЕГОДНЯШНЕЙ версией игры, и
  /// причина этого может оказаться нашей ошибкой, которую завтра починят.
  Future<String?> quarantine() async {
    final name = '$fileName.broken';
    final target = File('${directory.path}/$name');
    try {
      if (target.existsSync()) await target.delete();
      if (_file.existsSync()) {
        await _file.rename(target.path);
      } else if (_backup.existsSync()) {
        await _backup.rename(target.path);
      } else {
        return null;
      }
      for (final file in [_file, _backup, _sync]) {
        if (file.existsSync()) await file.delete();
      }
    } on Object {
      onTrouble?.call('failed', 'quarantine');
      return null;
    }
    _revision = 0;
    _mirrored = 0;
    _revisionKnown = true;
    return name;
  }

  Future<void> deleteAll() async {
    for (final file in [_file, _temp, _backup, _sync]) {
      if (file.existsSync()) await file.delete();
    }
    _revision = 0;
    _mirrored = 0;
    _revisionKnown = true;
  }

  /// Стирает ВСЁ, что осталось от игрока на телефоне: сейв с копией и
  /// меткой синхронизации, отложенный в карантин битый сейв и архивы
  /// прошлых сезонов.
  ///
  /// [deleteAll] про текущий сейв и оставляет архивы — это правильно для
  /// обнуления сезона, где доказанное не пропадает (`season.dart`). Удаление
  /// аккаунта — другое: «удалить мои данные» с архивом на диске было бы
  /// неправдой. Файл настроек не трогается: язык и звук — не данные игрока.
  Future<void> deleteEverything() async {
    await deleteAll();
    final dot = fileName.indexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final rest = dot <= 0 ? '' : fileName.substring(dot);
    // Имена — как их строят `SaveSync.archiveName` и [quarantine]:
    // `rift.save.json.broken`, `rift.<сезон>.save.json`.
    bool ours(String name) =>
        name.startsWith('$fileName.') ||
        (rest.isNotEmpty && name.startsWith('$stem.') && name.endsWith(rest));
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (ours(name)) await entity.delete();
    }
  }

  int _readMirrored() {
    if (!_sync.existsSync()) return 0;
    try {
      final raw = jsonDecode(_sync.readAsStringSync());
      if (raw is Map && raw['mirroredRevision'] is num) {
        return (raw['mirroredRevision'] as num).toInt();
      }
    } on Object {
      // Испорченная отметка — это отсутствующая отметка. Ноль безопасен:
      // он приводит к вопросу игроку, а не к тихой перезаписи.
    }
    return 0;
  }

  SaveHead _withMirrored(SaveHead head) => SaveHead(
        version: head.version,
        revision: head.revision,
        mirroredRevision: _mirrored,
        deviceId: head.deviceId,
        accountId: head.accountId,
        seasonId: head.seasonId,
        lastSeenUtc: head.lastSeenUtc,
        progress: head.progress,
      );
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
    this.onSaved,
  });

  final SaveStore store;

  /// Как получить текущее состояние. Функция, а не ссылка на профиль: сохранять
  /// нужно то, что есть на момент записи, а не то, что было на момент подписки.
  final SaveData Function() snapshot;

  final Duration interval;

  /// Что делать с записанным. Сюда подключается облачное зеркало
  /// (`cloud_sync.dart`): оно решает само, выгружать сейчас или подождать.
  ///
  /// Хранилище про облако при этом не знает вовсе — оно пишет файл.
  final void Function(SaveData saved, {required bool leaving})? onSaved;

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
      // `leaving` — не то же самое, что «пора сохранить». Уход в фон это
      // последний момент, когда сейв ещё можно выгрузить в облако: процесс
      // после него могут снять в любую секунду, и следующий запуск случится
      // на другом телефоне.
      saveNow(leaving: true);
    }
  }

  /// Сохраняет немедленно.
  ///
  /// Записи выстраиваются в очередь, а не отбрасываются: две одновременные
  /// записи в один временный файл затёрли бы друг друга, но и «пропустить,
  /// раз уже пишем» нельзя — тогда `await saveNow()` перестаёт что-либо
  /// гарантировать, и последнее действие игрока теряется ровно тогда, когда
  /// приложение закрывают сразу после него.
  Future<void> saveNow({bool leaving = false}) {
    final next = (_chain ?? Future<void>.value()).then((_) async {
      final saved = await store.save(snapshot());
      onSaved?.call(saved, leaving: leaving);
    });
    _chain = next.catchError((_) {});
    return next;
  }
}
