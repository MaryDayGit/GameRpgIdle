import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/fork.dart';

import '../state/game_controller.dart';
import 'trailer_camera.dart';
import 'trailer_caption.dart';

/// Часы трейлера.
///
/// Отдельный объект, а не поле площадки, из-за порядка сборки: `GameController`
/// требует функцию времени уже в конструкторе, а площадке нужен готовый
/// контроллер. Часы создаются первыми, и обе стороны держат одну ссылку.
class TrailerClock {
  TrailerClock(this.now);

  DateTime now;
}

/// Съёмочная площадка: игра, часы и навигация в одних руках.
///
/// Сценарий говорит, ЧТО показать; площадка знает, как до этого дойти. Ни
/// один экран игры про съёмку не знает и знать не должен: как только трейлер
/// потребует правки в самой игре, он перестанет показывать игру.
class TrailerStage {
  TrailerStage({
    required this.controller,
    required this.navigator,
    required this.clock,
  });

  final GameController controller;
  final GlobalKey<NavigatorState> navigator;
  final TrailerClock clock;

  /// Во сколько раз игровое время быстрее реального.
  ///
  /// Спуск целиком идёт около полуминуты — для рилса это вечность, для
  /// перемотки почти ничто. Поэтому ускорение здесь маленькое: ускоряется не
  /// показ, а само время игры, и счётчик глубины растёт по-настоящему, потому
  /// что контракт действительно доходит до этажа, а не рисует цифру.
  ///
  /// Сверху оно ограничено развилкой. Наёмник ждёт ответа 45 игровых секунд;
  /// при девятисоткратном ускорении один тик перепрыгивал через это окно
  /// целиком, развилка не показывалась вовсе, и трейлер вставал на ожидании
  /// события, которое уже прошло. На сорокакратном окно занимает семнадцать
  /// тиков — увидеть его успевают и камера, и сценарий.
  double _speed = 1;

  bool _stopped = false;

  DateTime get now => clock.now;

  PlayerProfile get profile => controller.profile;

  /// Контракт в работе: идущий вниз или ждущий получения.
  Contract? get contract =>
      controller.activeContract ?? controller.collectableContract;

  void stop() => _stopped = true;

  Duration _sinceTick = Duration.zero;

  /// Как часто игре сообщают, что время сдвинулось.
  ///
  /// Не каждый кадр. `tick` перестраивает всю Заставу, и делать это шестьдесят
  /// раз в секунду значит тратить кадры на то, чего не видно: счётчик глубины
  /// читается и на пятнадцати обновлениях, а камере остаётся втрое больше
  /// времени на собственную плавность — её-то в кадре как раз видно.
  static const _tickEvery = Duration(milliseconds: 66);

  /// Шаг часов. Зовётся раз в кадр из [TrailerHost].
  void advance(Duration dt) {
    if (_stopped || _speed <= 0) return;
    clock.now = clock.now.add(dt * _speed);

    _sinceTick += dt;
    if (_sinceTick < _tickEvery) return;
    _sinceTick = Duration.zero;
    controller.tick();
  }

  // --- Что умеет площадка -----------------------------------------------

  /// Открывает экран поверх Заставы.
  Future<void> open(Widget screen) async {
    final nav = navigator.currentState;
    if (nav == null || _stopped) return;
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => screen)));
    // Треть секунды на то, чтобы экран построился: камера ищет метку по
    // разметке, а до первого кадра разметки ещё нет.
    await pause(const Duration(milliseconds: 340));
  }

  /// Возвращается на Заставу.
  Future<void> back() async {
    navigator.currentState?.popUntil((route) => route.isFirst);
    await pause(const Duration(milliseconds: 340));
  }

  /// Отправляет вниз лучшего из резерва.
  void deployBest() {
    if (!profile.canDeploy) return;
    final reserve = [...profile.roster.reserve]
      ..sort((a, b) => b.rank.index.compareTo(a.rank.index));
    if (reserve.isEmpty) return;
    controller.deploy(reserve.first);
  }

  /// Отвечает на развилке смелым путём — тем, которого нет у приказа.
  void chooseBold() {
    final c = contract;
    if (c == null || !c.atFork) return;
    controller.chooseFork(c, Fork.boldIndex);
  }

  /// Забирает добычу вернувшегося.
  void collect() {
    final c = controller.collectableContract;
    if (c == null) return;
    controller.collect(c);
  }

  /// Гонит время, пока не случится [done] — но не дальше, чем на [budget]
  /// ИГРОВОГО времени.
  ///
  /// Предел обязателен. Условие, которое не наступит — наёмник погиб раньше
  /// развилки, добычу уже забрали, — иначе остановило бы трейлер навсегда, и
  /// выяснилось бы это на съёмке.
  ///
  /// Меряется он игровыми часами, и это единственная мера, которая одинаково
  /// работает и на телефоне, и в тесте. Предел по настенным часам в тесте не
  /// наступает вовсе — время там поддельное. Предел по числу опросов не
  /// работает наоборот: один кадр теста прокручивает десятки опросов подряд,
  /// а часы двигает один раз, и запас сгорает вхолостую.
  ///
  /// [hardStop] — страховка от остановившихся часов: если время не идёт
  /// совсем, бюджет не потратится никогда.
  Future<void> until(
    bool Function() done, {
    double speed = 40,
    Duration budget = const Duration(minutes: 20),
    int hardStop = 20000,
  }) async {
    _speed = speed;
    final from = clock.now;
    var guard = 0;
    while (!_stopped &&
        !done() &&
        guard++ < hardStop &&
        clock.now.difference(from) < budget) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    _speed = 1;
  }

  /// Держит кадр [d] реального времени, не трогая часы игры.
  ///
  /// Дробится на короткие куски, чтобы остановка была мгновенной. Одна
  /// длинная задержка переживает снятие дерева: трейлер уже не показывают, а
  /// таймер на три секунды всё ещё держит ссылку на мёртвое состояние — и в
  /// тесте это падение, а на телефоне утечка на каждом круге.
  Future<void> pause(Duration d) async {
    const step = Duration(milliseconds: 50);
    var left = d;
    while (!_stopped && left > Duration.zero) {
      final take = left < step ? left : step;
      await Future<void>.delayed(take);
      left -= take;
    }
  }
}

/// Один кадр трейлера: куда смотреть, что сказать, что перед этим сделать.
@immutable
class TrailerBeat {
  const TrailerBeat({
    this.shot = TrailerShot.wide,
    this.line,
    this.hold = const Duration(seconds: 3),
    this.act,
    this.move = const Duration(milliseconds: 1100),
  });

  final TrailerShot shot;
  final TrailerLine? line;

  /// Сколько кадр стоит после того, как камера доехала.
  final Duration hold;

  /// Что сделать в игре ПЕРЕД кадром: открыть экран, отправить наёмника,
  /// прогнать время. `null` — кадр только смотрит.
  final Future<void> Function(TrailerStage)? act;

  final Duration move;
}

/// Трейлер поверх живой игры.
///
/// Оборачивает `Navigator` целиком (через `MaterialApp.builder`), а не один
/// экран: иначе открытая поверх Сборка оказалась бы НАД камерой, и наезд её
/// не касался бы.
///
/// Касания до игры не доходят. Съёмка идёт с телефона в руках, и случайное
/// касание ладонью открыло бы посреди дубля чужой экран. Двойное касание
/// ставит показ на паузу — это единственное, что трейлер слушает.
class TrailerHost extends StatefulWidget {
  const TrailerHost({
    super.key,
    required this.stage,
    required this.script,
    required this.onLoop,
    required this.child,
  });

  final TrailerStage stage;
  final List<TrailerBeat> script;

  /// Круг пройден. Хозяин пересоздаёт игру, и следующий дубль показывает ту
  /// же Заставу: профиль детерминирован, значит и запись повторима.
  final VoidCallback onLoop;

  final Widget child;

  @override
  State<TrailerHost> createState() => _TrailerHostState();
}

class _TrailerHostState extends State<TrailerHost>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  TrailerShot _shot = TrailerShot.wide;
  TrailerLine? _line;
  Duration _move = const Duration(milliseconds: 1100);

  bool _paused = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    _done = true;
    widget.stage.stop();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (_paused) return;
    widget.stage.advance(dt);
  }

  /// Ждёт, пока снята пауза.
  Future<void> _held() async {
    while (_paused && !_done && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _run() async {
    for (final beat in widget.script) {
      if (_done || !mounted) return;
      await _held();
      try {
        await beat.act?.call(widget.stage);
      } catch (_) {
        // Кадр, который не удался, не должен ронять трейлер. Игра могла уйти
        // не туда — наёмник умер раньше развилки, сундук полон, — и это
        // повод пропустить кадр, а не оборвать дубль на середине.
      }
      if (_done || !mounted) return;
      setState(() {
        _shot = beat.shot;
        _line = beat.line;
        _move = beat.move;
      });
      await widget.stage.pause(beat.move + beat.hold);
    }
    if (!_done && mounted) widget.onLoop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => setState(() => _paused = !_paused),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TrailerCamera(
            shot: _shot,
            move: _move,
            child: IgnorePointer(child: widget.child),
          ),
          TrailerCaptionLayer(line: _line),
          // Метка паузы: точка в углу. Оператору надо видеть, что показ
          // стоит; зрителю этого видеть не надо.
          if (_paused)
            const Positioned(
              left: 4,
              top: 4,
              child: IgnorePointer(
                child: CircleAvatar(radius: 3, backgroundColor: Colors.white24),
              ),
            ),
        ],
      ),
    );
  }
}
