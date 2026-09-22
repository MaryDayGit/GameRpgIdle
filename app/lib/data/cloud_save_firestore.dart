import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_head.dart';

import 'cloud_save.dart';

export 'cloud_save.dart';

/// Облачное зеркало сейва на Cloud Firestore.
///
/// ## Раскладка
///
/// ```
/// players/{uid}/saves/{seasonId}
///   ├─ version, revision, deviceId, accountId, seasonId, lastSeenUtc
///   ├─ progress: { maxDepth, runs, outpostLevel, gold }
///   ├─ payload:  "<сейв целиком, одной строкой JSON>"
///   └─ updatedAt: серверное время
/// ```
///
/// **Сезон — часть адреса, а не поле.** Сейв прошлого сезона лежит в соседнем
/// документе и не мешает нынешнему: обнуление сезона — это переход на другой
/// адрес, а не удаление (`rift/core/save/season.dart`). Игрок при этом
/// ничего не теряет, а нам не нужен ни один запрос вида «а какой сезон в
/// этом документе».
///
/// **Паспорт лежит полями, тело — строкой.** Не ради экономии: документ
/// приезжает целиком в любом случае. Ради ЗАПРОСОВ. Таблица лидеров сезона —
/// это `collectionGroup('saves').where('seasonId', ...).orderBy('progress.maxDepth')`,
/// и ей незачем ни читать чужие профили, ни разбирать чужой JSON. Достижения
/// лягут туда же, отдельными полями.
///
/// Тело именно строкой, а не вложенной картой, по трём причинам, и первая
/// решает: у Firestore есть предел вложенности в 20 уровней и предел в 40 000
/// индексируемых полей на документ, а профиль — это ростер, снаряжение,
/// аффиксы на каждой вещи и журнал этажей у каждого контракта. Строка
/// проходит мимо обоих пределов и мимо автоматического индексирования,
/// которое нам тут не нужно ни на одном поле. Вторая: формат сейва ровно
/// один, и локальному с облачным нечем разъехаться. Третья: миграции
/// (`migrations.dart`) работают на облачном сейве так же, как на локальном,
/// потому что это один и тот же текст.
///
/// ## Что нужно в консоли Firebase
///
/// 1. Firestore Database → Create database.
/// 2. Правила. Сейв — это личное, и открытая база означает, что чужой сейв
///    можно и прочитать, и затереть:
///
/// ```
/// rules_version = '2';
/// service cloud.firestore {
///   match /databases/{database}/documents {
///     match /players/{uid}/saves/{seasonId} {
///       allow read, write: if request.auth != null && request.auth.uid == uid;
///     }
///   }
/// }
/// ```
class FirestoreCloudSaveStore implements CloudSaveStore {
  FirestoreCloudSaveStore._(this._db);

  final FirebaseFirestore _db;

  /// Поднимает хранилище. `null`-исход отдаётся как [NoCloudSaveStore]:
  /// отсутствие Firestore — штатный случай, а не ошибка (`AnalyticsSetup`).
  static Future<CloudSaveStore> create() async {
    try {
      // Как и в `FirebaseAccountService`: поднимаем сами, а не рассчитываем
      // на то, что это уже сделал кто-то выше по загрузке.
      await Firebase.initializeApp();
      final db = FirebaseFirestore.instance;
      // Кэш Firestore выключен намеренно. Он держит СВОЮ копию документа и
      // отдаёт её при отказе сети — то есть на вопрос «что лежит в облаке»
      // отвечает тем, что лежало когда-то. Для разрешения расхождений это
      // худший из возможных ответов: устаревший документ выглядит как
      // настоящий, и решение принимается по нему. Хозяин офлайн-состояния
      // здесь ровно один — локальный файл.
      db.settings = const Settings(persistenceEnabled: false);
      return FirestoreCloudSaveStore._(db);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[cloud] Firestore недоступен: $e');
      return const NoCloudSaveStore();
    }
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid, String seasonId) =>
      _db.collection('players').doc(uid).collection('saves').doc(seasonId);

  @override
  Future<CloudSave?> fetch({
    required String uid,
    required String seasonId,
  }) async {
    // Отказ сети НЕ проглатывается: он поднимается наверх, где отличается от
    // «документа нет». Перепутать их значит выгрузить локальный сейв поверх
    // облачного каждый раз, когда у игрока пропал интернет.
    //
    // Ожидание ограничено, потому что чтение стоит ПЕРЕД первым кадром: без
    // границы игрок без сети смотрит в чёрный экран столько, сколько отмерит
    // своим таймаутом Firestore. Истёкшее ожидание — это тот же отказ
    // чтения, и обрабатывается он там же.
    final snap = await _doc(uid, seasonId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    final data = snap.data();
    if (data == null) return null;

    final payload = data['payload'];
    if (payload is! String || payload.isEmpty) return null;

    final head = SaveHead.fromJson(data);
    if (head == null) return null;

    return CloudSave(head: head, payload: payload);
  }

  @override
  Future<bool> push({required String uid, required SaveData data}) async {
    try {
      await _doc(uid, data.seasonId).set({
        // Паспорт полями — по нему строятся запросы, не читая тело.
        // `mirroredRevision` в облачном документе не читает никто: он
        // описывает отношение КОНКРЕТНОГО устройства к облаку и смысла на
        // той стороне не имеет. Пишется вместе с остальным, чтобы у сейва
        // была одна форма, а не две почти одинаковых.
        ...data.head.toJson(),
        'payload': data.encode(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on Object catch (e) {
      // Здесь ошибка проглатывается, и это не то же самое, что в [fetch]:
      // неудачная выгрузка означает ровно одно — `mirroredRevision` не
      // поднимется, и мы попробуем снова. Ронять из-за неё игру нельзя,
      // а терять из-за неё данные нечем: хозяин лежит на диске.
      if (kDebugMode) debugPrint('[cloud] выгрузка не удалась: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteAll({required String uid}) async {
    try {
      // Все сезоны, а не нынешний: сейв прошлого сезона — тоже данные игрока
      // (`season.dart`), и «удалить мои данные» без него было бы неправдой.
      // Правила Firestore пускают владельца и читать список, и удалять.
      final saves = _db.collection('players').doc(uid).collection('saves');
      final snap = await saves
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (snap.docs.isEmpty) return true;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 15));
      return true;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[cloud] удаление не удалось: $e');
      return false;
    }
  }
}
