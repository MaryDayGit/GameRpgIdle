import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rift/core/model/tags.dart';

/// Что игра умеет сказать звуком.
///
/// Список закрыт намеренно: игра идёт по десять минут фоном, и звук, который
/// хочется выключить на третьей минуте, хуже тишины. Поэтому он растёт только
/// туда, где разные вещи звучали одинаково, — а не «чтобы было больше».
enum Sfx {
  /// Удар героя. Самый частый и самый тихий.
  hit,

  /// Удар стихией. Пять стихий, за которые игрок платит слотами, аффиксами и
  /// целым «Проводником», звучали одним и тем же «тук» — то есть выбор стихии
  /// в бою не был слышен вовсе. Длина и громкость у всех одна: звук, который
  /// вдобавок длиннее, читался бы как «удар сильнее».
  hitFire,
  hitCold,
  hitLightning,
  hitVoid,

  /// Применённая способность. Поднимается, а не падает: удар бьёт вниз,
  /// заклинание идёт вверх, и различаются они прежде всего этим.
  cast,

  /// Волна с боссом. Звучит один раз за волну — и потому имеет право быть
  /// низким и длинным.
  boss,

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

  /// Добыча забрана — главная награда игры.
  reward,

  /// Потрачено: постройка, узел древа, крафт. Отдельно от [reward]: фанфара
  /// на каждое нажатие в Кузнице перестала бы что-либо значить, а монеты
  /// говорят ровно то, что случилось, — заплачено.
  buy,

  /// В добыче реликт. Самая редкая находка обязана звучать иначе, чем
  /// сундук обычных вещей, — иначе её узнают только из журнала.
  relic,

  /// Босс повержен. Раньше его смерть звучала тем же «пух», что и падальщик.
  bossDown,

  /// Этаж пройден: короткая отметка шага вниз.
  floor,

  /// Наёмник встал на развилке. Звучит, пока игра открыта: развилка —
  /// единственное, что ждёт игрока посреди спуска, и узнать о ней надо не
  /// глядя на экран.
  fork,
}

/// Звук удара этой стихией.
///
/// Здесь, рядом со звуками, а не на экране боя: экран говорит ЧТО случилось,
/// и знать, каким файлом озвучен Холод, ему незачем.
Sfx sfxForDamage(DamageType type) => switch (type) {
      DamageType.physical => Sfx.hit,
      DamageType.fire => Sfx.hitFire,
      DamageType.cold => Sfx.hitCold,
      DamageType.lightning => Sfx.hitLightning,
      DamageType.voidType => Sfx.hitVoid,
    };

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

  static const _poolSize = 6;

  /// Звуки, у которых по три дубля (`tool/make_sounds.dart`).
  ///
  /// Удар звучит по нескольку раз в секунду, и один и тот же файл, повторённый
  /// сотню раз, превращается в метроном: ухо перестаёт слышать удар и слышит
  /// повтор. Дубль выбирается случайно, но не повторяет предыдущий.
  static const takes = {
    Sfx.hit,
    Sfx.hitFire,
    Sfx.hitCold,
    Sfx.hitLightning,
    Sfx.hitVoid,
    Sfx.crit,
    Sfx.kill,
    Sfx.hurt,
  };

  /// Имя файла дубля: `hit.wav`, `hit_1.wav`, `hit_2.wav`.
  static String fileFor(Sfx sfx, int take) =>
      take == 0 ? '${sfx.name}.wav' : '${sfx.name}_$take.wav';

  final _rng = math.Random();
  final Map<Sfx, int> _lastTake = {};

  int _takeFor(Sfx sfx) {
    if (!takes.contains(sfx)) return 0;
    final last = _lastTake[sfx] ?? -1;
    var take = _rng.nextInt(3);
    if (take == last) take = (take + 1 + _rng.nextInt(2)) % 3;
    _lastTake[sfx] = take;
    return take;
  }

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
    unawaited(player.play(AssetSource('audio/${fileFor(sfx, _takeFor(sfx))}'),
        volume: _volume[sfx] ?? 1.0));
  }

  /// Громкость по роли, а не по файлу: удар звучит постоянно, гибель — раз
  /// за ран, и уравнивать их нельзя.
  static const _volume = {
    Sfx.hit: 0.35,
    Sfx.hitFire: 0.35,
    Sfx.hitCold: 0.35,
    Sfx.hitLightning: 0.35,
    Sfx.hitVoid: 0.35,
    Sfx.cast: 0.45,
    Sfx.boss: 0.8,
    Sfx.crit: 0.6,
    Sfx.kill: 0.5,
    Sfx.hurt: 0.6,
    Sfx.death: 0.9,
    Sfx.deploy: 0.7,
    Sfx.reward: 0.7,
    Sfx.buy: 0.5,
    Sfx.relic: 0.85,
    Sfx.bossDown: 0.85,
    Sfx.floor: 0.4,
    Sfx.fork: 0.8,
  };

  /// Громкость звука — для проверки, что у каждого она назначена.
  static double? volumeOf(Sfx sfx) => _volume[sfx];

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
