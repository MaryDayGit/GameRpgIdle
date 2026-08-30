import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Что игра умеет сказать звуком.
///
/// Список закрыт и короткий намеренно: игра идёт по десять минут фоном, и
/// звук, который хочется выключить на третьей минуте, хуже тишины.
enum Sfx {
  /// Удар героя. Самый частый и самый тихий.
  hit,

  /// Критический удар.
  crit,

  /// Моб погиб.
  kill,

  /// Попадание по герою.
  hurt,

  /// Наёмник погиб — конец рана.
  death,

  /// Наёмник ушёл вниз.
  deploy,

  /// Что-то получено: добыча, узел древа, крафт.
  reward,
}

/// Тактильная отдача. Три силы, больше не нужно: телефон умеет отличать
/// «щёлк» от «удар», а полутона на нём неразличимы.
enum Bump { light, medium, heavy }

/// Звук и вибрация.
///
/// Отдельный слой, а не вызовы из экранов, по той же причине, по которой
/// симуляция отделена от рисования: экран не должен знать, включён ли звук,
/// загрузился ли файл и не идёт ли уже такой же удар. Он говорит ЧТО
/// случилось, а не как это озвучить.
class GameFeedback {
  GameFeedback({
    this.sound = true,
    this.haptics = true,
    AudioPlayer Function()? player,
  }) : _newPlayer = player ?? AudioPlayer.new;

  final AudioPlayer Function() _newPlayer;

  bool sound;
  bool haptics;

  /// Пул проигрывателей: удары идут по нескольку раз в секунду, и один
  /// проигрыватель обрывал бы предыдущий удар на середине.
  final List<AudioPlayer> _pool = [];
  var _next = 0;

  static const _poolSize = 4;

  /// Когда последний раз звучал каждый звук. Удары в бою идут пачками, и
  /// десять «тук» в один кадр сливаются в треск.
  final Map<Sfx, DateTime> _lastPlayed = {};

  /// Минимальный промежуток между повторами одного звука.
  static const _minGap = Duration(milliseconds: 70);

  bool _ready = false;

  Future<void> init() async {
    if (_ready || !_supported) return;

    for (var i = 0; i < _poolSize; i++) {
      final player = _newPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      _pool.add(player);
    }
    _ready = true;
  }

  /// Звук работает не везде: в тестах и на неподдержанной платформе плеера
  /// просто нет, и это не повод падать.
  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void play(Sfx sfx, {Bump? bump}) {
    if (bump != null) this.bump(bump);
    if (!sound || !_ready || _pool.isEmpty) return;

    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last) < _minGap) return;
    _lastPlayed[sfx] = now;

    final player = _pool[_next++ % _pool.length];
    unawaited(player.play(AssetSource('audio/${sfx.name}.wav'),
        volume: _volume[sfx] ?? 1.0));
  }

  /// Громкость по роли, а не по файлу: удар звучит постоянно, гибель — раз
  /// за ран, и уравнивать их нельзя.
  static const _volume = {
    Sfx.hit: 0.35,
    Sfx.crit: 0.6,
    Sfx.kill: 0.5,
    Sfx.hurt: 0.6,
    Sfx.death: 0.9,
    Sfx.deploy: 0.7,
    Sfx.reward: 0.7,
  };

  void bump(Bump strength) {
    if (!haptics) return;
    switch (strength) {
      case Bump.light:
        unawaited(HapticFeedback.selectionClick());
      case Bump.medium:
        unawaited(HapticFeedback.mediumImpact());
      case Bump.heavy:
        unawaited(HapticFeedback.heavyImpact());
    }
  }

  Future<void> dispose() async {
    for (final player in _pool) {
      await player.dispose();
    }
    _pool.clear();
    _ready = false;
  }
}
