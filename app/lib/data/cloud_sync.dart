import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_sync.dart';

import 'account.dart';
import 'cloud_save.dart';
import 'save_store.dart';

/// Чем кончилось сведение сейвов на запуске.
class CloudSyncResult {
  const CloudSyncResult(this.decision, {this.remote, this.errorStage});

  final SyncDecision decision;

  /// Облачный сейв целиком — он нужен позже, если игрок выберет его в
  /// диалоге. Второй раз в сеть за ним не ходим: между вопросом и ответом
  /// игрока сеть успевает пропасть, и «вы выбрали облачный, но мы его
  /// потеряли» — худший из возможных ответов.
  final CloudSave? remote;

  /// На чём споткнулись, если споткнулись: `auth`, `read`. `null` — всё
  /// прошло.
  final String? errorStage;

  bool get needsPlayer => decision.needsPlayer;
}

/// Облачное зеркало: сводит сейв на телефоне с сейвом в Firestore и держит
/// их сведёнными.
///
/// ## Что здесь решается, а что нет
///
/// Правило, по которому выбирается сейв, живёт в ядре
/// (`rift/core/save/save_sync.dart`) и проверяется headless. Здесь — только
/// работа с сетью и диском вокруг него: сходить за документом, положить
/// облачный сейв на место локального, выгрузить локальный.
///
/// Разделение не формальное. Правило — единственное место в игре, где ошибка
/// стоит чужого аккаунта, и оно обязано проверяться без Firebase, без
/// эмулятора и без двух телефонов.
///
/// ## Почему выгрузка не идёт на каждом сохранении
///
/// Сейв пишется на диск раз в минуту и при каждом уходе в фон. Выгружать
/// его в Firestore с той же частотой нельзя по двум причинам, и вторая
/// важнее.
///
/// Первая — квота. Бесплатный Firestore даёт 20 000 записей в сутки НА
/// ПРОЕКТ, а не на игрока. Тысяча игроков по двадцать записей в день — это
/// ровно квота, после которой синхронизация отваливается у всех сразу.
///
/// Вторая — смысл. Зеркало нужно для переустановки и второго устройства,
/// то есть в момент, когда игрок ушёл отсюда и пришёл туда. Состояние
/// поминутной свежести для этого не нужно; нужна свежесть на момент, когда
/// игрок закрыл игру. Поэтому выгрузка привязана к уходу в фон, к концу
/// спуска и к редкому таймеру — а не к записи файла.
class CloudMirror {
  CloudMirror({
    required this.store,
    required this.cloud,
    required this.account,
    this.minInterval = const Duration(minutes: 5),
    this.clock = DateTime.now,
    this.onEvent,
  });

  final SaveStore store;
  final CloudSaveStore cloud;
  final AccountService account;

  /// Реже этого промежутка обычная выгрузка не идёт. Уход в фон и явный
  /// вызов промежуток игнорируют.
  final Duration minInterval;

  final DateTime Function() clock;

  /// Куда сообщать о происходящем: `(вид, ступень)`. Аналитика подключается
  /// сюда, а зеркало про неё не знает.
  final void Function(String kind, String stage)? onEvent;

  DateTime? _lastPush;
  int _pushedRevision = 0;
  Future<void>? _chain;

  bool get enabled => account.current.hasId;

  /// Сводит сейвы на запуске. Ничего не меняет на диске — только считает
  /// решение и приносит облачный сейв.
  ///
  /// Не трогает диск намеренно: между решением и действием стоит игрок
  /// (ветка `ask`), и хранилище, изменённое до его ответа, лишило бы ответ
  /// смысла.
  Future<CloudSyncResult> resolveOnBoot() async {
    final local = await store.peek();

    final uid = account.current.uid;
    if (uid == null || uid.isEmpty) {
      // Аккаунта нет: нет сети, нет Play Services, игрок вышел. Это не
      // ошибка синхронизации, это её отсутствие — играем локальным.
      return CloudSyncResult(
        SaveSync.resolve(local: local),
        errorStage: 'auth',
      );
    }

    CloudSave? remote;
    try {
      remote = await cloud.fetch(uid: uid, seasonId: SaveSync.currentSeasonId);
    } on Object catch (e) {
      // Не смогли спросить — это НЕ «документа нет». Разница решающая:
      // приняв отказ сети за пустое облако, мы бы выгрузили локальный сейв
      // поверх облачного у каждого, у кого пропал интернет.
      if (kDebugMode) debugPrint('[cloud] чтение не удалось: $e');
      onEvent?.call('error', 'read');
      return CloudSyncResult(
        SaveSync.resolve(local: local),
        errorStage: 'read',
      );
    }

    return CloudSyncResult(
      SaveSync.resolve(local: local, remote: remote?.head),
      remote: remote,
    );
  }

  /// Кладёт облачный сейв на место локального.
  Future<SaveData> adopt(CloudSave remote) async {
    final data = remote.decode();
    return store.adopt(data);
  }

  /// Выгружает, если пора. [force] отменяет промежуток — так уходит в облако
  /// уход в фон и конец спуска.
  ///
  /// Никогда не ждёт сети дольше, чем нужно вызывающему: выгрузки выстроены
  /// в очередь, и вызов возвращается, не дожидаясь чужой.
  Future<void> push(SaveData saved, {bool force = false}) {
    if (!enabled) return Future<void>.value();
    if (saved.revision <= _pushedRevision) return Future<void>.value();

    if (!force) {
      final last = _lastPush;
      if (last != null && clock().difference(last) < minInterval) {
        return Future<void>.value();
      }
    }

    final next = (_chain ?? Future<void>.value()).then((_) async {
      final uid = account.current.uid;
      if (uid == null || uid.isEmpty) return;

      final ok = await cloud.push(uid: uid, data: saved);
      if (!ok) {
        onEvent?.call('error', 'write');
        return;
      }
      _lastPush = clock();
      _pushedRevision = saved.revision;
      await store.markMirrored(saved.revision);
    });

    _chain = next.catchError((Object e) {
      if (kDebugMode) debugPrint('[cloud] выгрузка сорвалась: $e');
      onEvent?.call('error', 'write');
    });
    return _chain!;
  }

  /// Забывает, что выгружали. Зовётся после смены аккаунта: сейв под новым
  /// uid лежит по другому адресу, и «мы это уже выгружали» про него неправда.
  void reset() {
    _lastPush = null;
    _pushedRevision = 0;
  }
}
