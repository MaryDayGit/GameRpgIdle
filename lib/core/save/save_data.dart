import 'dart:convert';

import '../model/player_profile.dart';
import 'codec.dart';
import 'migrations.dart';
import 'save_head.dart';
import 'save_issue.dart';
import 'season.dart';

/// Сейв целиком: паспорт (`save_head.dart`) и состояние игрока.
///
/// Один документ, а не база: сохраняемого состояния тут на десятки килобайт,
/// и Hive/Isar были бы лишней зависимостью ради одного файла
/// (`docs/02-TECH.md` §4). Тот же документ уезжает в облако — целиком, одной
/// строкой (`app/lib/data/cloud_save_store.dart`), поэтому формат ровно один
/// и разъехаться локальному с облачным нечем.
///
/// ## Что появилось вместе с аккаунтом
///
/// До аккаунта сейв знал про себя две вещи: версию формата и когда игрока
/// видели в последний раз. Этого хватало, пока сейв был один и лежал в одном
/// месте. Как только он лежит в двух, каждому чтению нужен ответ на вопрос
/// «который из них новее» — и отметки времени на него не отвечают
/// (`save_sync.dart`). Поэтому здесь появились [revision],
/// [mirroredRevision], [deviceId], [accountId] и [seasonId].
///
/// Все пять — часть ФОРМАТА, а не приложения, и живут в ядре по той же
/// причине, что и вся остальная раскладка сейва: их читает разрешение
/// конфликтов, а оно обязано проверяться headless.
class SaveData {
  const SaveData({
    required this.lastSeenUtc,
    required this.profile,
    this.version = currentVersion,
    this.revision = 1,
    this.mirroredRevision = 0,
    this.deviceId = '',
    this.accountId,
    String? seasonId,
    this.issues,
  }) : _seasonId = seasonId;

  /// Версия формата. Растёт вместе с цепочкой миграций.
  static const int currentVersion = 6;

  final int version;

  /// Когда игрок последний раз был в игре. От неё считается офлайн-догонялка,
  /// поэтому хранится в UTC: перевод часов не должен превращаться в добычу.
  ///
  /// Решений о том, какой сейв взять, на ней НЕ строится: см.
  /// `save_sync.dart`.
  final DateTime lastSeenUtc;

  /// Номер записи. Растёт на единицу с каждым сохранением.
  final int revision;

  /// Ревизия, на которой сейв последний раз сошёлся с облаком.
  final int mirroredRevision;

  /// Кто записал последним.
  final String deviceId;

  /// Аккаунт-владелец. `null` — сейв заведён без сети или до аккаунтов.
  final String? accountId;

  final String? _seasonId;

  /// Сезон, к которому относится прогресс.
  ///
  /// Сейвы до сезонов его не знают, и умолчание для них — нулевой: они и
  /// есть нулевой сезон, просто не подписанный (`season.dart`).
  String get seasonId => _seasonId ?? Season.zero.id;

  final PlayerProfile profile;

  /// Что пришлось починить при загрузке. `null` у только что собранного сейва.
  final SaveIssues? issues;

  /// Паспорт этого сейва.
  SaveHead get head => SaveHead(
        version: version,
        revision: revision,
        mirroredRevision: mirroredRevision,
        deviceId: deviceId,
        accountId: accountId,
        seasonId: seasonId,
        lastSeenUtc: lastSeenUtc,
        progress: SaveProgress.of(profile),
      );

  /// Тот же сейв с подправленным паспортом. Профиль не копируется — он
  /// изменяемый и живой, копия разъехалась бы с тем, во что играют.
  SaveData copyWith({
    DateTime? lastSeenUtc,
    int? revision,
    int? mirroredRevision,
    String? deviceId,
    String? accountId,
    String? seasonId,
  }) =>
      SaveData(
        lastSeenUtc: lastSeenUtc ?? this.lastSeenUtc,
        profile: profile,
        version: version,
        revision: revision ?? this.revision,
        mirroredRevision: mirroredRevision ?? this.mirroredRevision,
        deviceId: deviceId ?? this.deviceId,
        accountId: accountId ?? this.accountId,
        seasonId: seasonId ?? this.seasonId,
        issues: issues,
      );

  /// Паспорт и профиль. Паспорт пишется целиком из [head], а не полем за
  /// полем: два места, собирающих одну и ту же шапку, — это два места,
  /// которые разъедутся, и разъедутся молча.
  ///
  /// Вместе с паспортом уезжает сводка прогресса — рекорд, спуски, Застава.
  /// Она выводится из профиля и в этом смысле лишняя, но без неё [peek]
  /// теряет смысл: он читает шапку, НЕ разбирая профиль, и без сводки любой
  /// сейв выглядел бы для него пустым. А «пустой» — это ровно тот признак,
  /// по которому сейв уступает облачному (`save_sync.dart`), то есть цена
  /// её отсутствия — стёртый аккаунт.
  ///
  /// Источником при этом остаётся профиль: на загрузке шапка собирается
  /// заново (`head`), и записанная сводка нигде, кроме [peek], не читается.
  Map<String, dynamic> toJson() => {
        ...head.toJson(),
        'profile': SaveCodec.encodeProfile(profile),
      };

  String encode() => jsonEncode(toJson());

  /// Читает только паспорт, не разбирая профиль.
  ///
  /// Нужно на каждом запуске, где есть облако: решение «какой сейв взять»
  /// принимается до загрузки, и разбирать ради него оба профиля значит
  /// разбирать чужой сейв снисходительно (`codec.dart`) — то есть сравнивать
  /// уже не то, что лежит в облаке, а то, что от него осталось после
  /// починки.
  ///
  /// Возвращает `null`, а не бросает: паспорт читается у чужого документа,
  /// и «не разобрался» здесь означает ровно то же, что «его нет».
  static SaveHead? peek(String text) {
    try {
      final parsed = jsonDecode(text);
      if (parsed is! Map) return null;
      return SaveHead.fromJson(parsed.cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }

  /// Читает сейв, при необходимости прогоняя через миграции.
  ///
  /// Бросает [SaveException] только на том, после чего играть нечем: не JSON,
  /// нет версии, версия из будущего, разорванная цепочка миграций. Всё
  /// остальное — потерянный аффикс, вырезанный реликт, наёмник без ранга —
  /// попадает в [SaveIssues], а сейв открывается.
  static SaveData decode(
    String text, {
    SaveMigrations migrations = const SaveMigrations(),
    int targetVersion = currentVersion,
  }) {
    Object? parsed;
    try {
      parsed = jsonDecode(text);
    } on FormatException catch (e) {
      throw SaveException('не разбирается как JSON (${e.message})');
    }

    if (parsed is! Map) {
      throw SaveException('в корне не объект');
    }
    final raw = parsed.cast<String, dynamic>();

    final version = raw['version'];
    if (version is! int) {
      throw SaveException('нет поля version');
    }

    final issues = SaveIssues();
    final upgraded = migrations.upgrade(
      raw,
      from: version,
      target: targetVersion,
      issues: issues,
    );

    final profileJson = upgraded['profile'];
    if (profileJson is! Map) {
      throw SaveException('нет раздела profile');
    }

    return SaveData(
      version: targetVersion,
      revision: _int(upgraded['revision'], or: 1),
      mirroredRevision: _int(upgraded['mirroredRevision']),
      deviceId: upgraded['deviceId'] is String
          ? upgraded['deviceId'] as String
          : '',
      accountId: upgraded['accountId'] is String
          ? upgraded['accountId'] as String
          : null,
      seasonId: upgraded['seasonId'] is String
          ? upgraded['seasonId'] as String
          : Season.zero.id,
      lastSeenUtc: DateTime.tryParse('${upgraded['lastSeenUtc']}')?.toUtc() ??
          DateTime.now().toUtc(),
      profile: SaveCodec.decodeProfile(
          profileJson.cast<String, dynamic>(), issues),
      issues: issues,
    );
  }

  static int _int(Object? raw, {int or = 0}) =>
      raw is num ? raw.toInt() : or;
}
