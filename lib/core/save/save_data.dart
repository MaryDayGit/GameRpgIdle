import 'dart:convert';

import '../model/player_profile.dart';
import 'codec.dart';
import 'migrations.dart';
import 'save_issue.dart';

/// Сейв целиком: версия, отметка времени и состояние игрока.
///
/// Один документ, а не база: сохраняемого состояния тут на десятки килобайт,
/// и Hive/Isar были бы лишней зависимостью ради одного файла
/// (`docs/02-TECH.md` §4).
class SaveData {
  const SaveData({
    required this.lastSeenUtc,
    required this.profile,
    this.version = currentVersion,
    this.issues,
  });

  /// Версия формата. Растёт вместе с цепочкой миграций.
  static const int currentVersion = 3;

  final int version;

  /// Когда игрок последний раз был в игре. От неё считается офлайн-догонялка,
  /// поэтому хранится в UTC: перевод часов не должен превращаться в добычу.
  final DateTime lastSeenUtc;

  final PlayerProfile profile;

  /// Что пришлось починить при загрузке. `null` у только что собранного сейва.
  final SaveIssues? issues;

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastSeenUtc': lastSeenUtc.toUtc().toIso8601String(),
        'profile': SaveCodec.encodeProfile(profile),
      };

  String encode() => jsonEncode(toJson());

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
      lastSeenUtc: DateTime.tryParse('${upgraded['lastSeenUtc']}')?.toUtc() ??
          DateTime.now().toUtc(),
      profile: SaveCodec.decodeProfile(
          profileJson.cast<String, dynamic>(), issues),
      issues: issues,
    );
  }
}
