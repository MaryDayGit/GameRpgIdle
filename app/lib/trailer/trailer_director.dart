import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/fork.dart';

import '../state/game_controller.dart';
import '../ui/coach_mark.dart';
import 'trailer_camera.dart';
import 'trailer_caption.dart';
import 'trailer_film.dart';

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

  /// Затемнение кадра. Им закрываются переходы: смену экрана зритель видеть
  /// не должен — он должен видеть следующую сцену.
  final TrailerVeil veil = TrailerVeil();

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

  void stop() {
    _stopped = true;
    veil.stop();
  }

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

  /// Маршрут без выезда: экраны РАСТВОРЯЮТСЯ друг в друге.
  ///
  /// Штатный `MaterialPageRoute` увозит экран вбок, и на записи это читается
  /// как чужое движение поверх кадра — камера ведёт в одну сторону, маршрут
  /// уезжает в другую. Растворение не спорит с камерой ни с какой стороны.
  static Route<void> _dissolve(Widget screen) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, anim, secondary) => screen,
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  /// Открывает экран поверх Заставы — в темноте.
  Future<void> open(Widget screen) => veil.dip(() => _push(screen));

  /// Возвращается на Заставу — тоже в темноте.
  Future<void> back() => veil.dip(_pop);

  /// Сменить экран одним переходом: свернуть открытое и открыть новое.
  ///
  /// Раньше сценарий делал это парой `back()` + `open()`, и на пять разделов
  /// подряд приходилось десять переходов: экран уезжал на Заставу, Застава
  /// показывалась на треть секунды и уезжала обратно. Зритель успевал увидеть
  /// мелькание, но не успевал ничего прочесть.
  Future<void> show(Widget screen) => veil.dip(() async {
        await _pop();
        await _push(screen);
      });

  Future<void> _push(Widget screen) async {
    final nav = navigator.currentState;
    if (nav == null || _stopped) return;
    unawaited(nav.push(_dissolve(screen)));
    // Треть секунды на то, чтобы экран построился: камера ищет метку по
    // разметке, а до первого кадра разметки ещё нет.
    await pause(const Duration(milliseconds: 340));
    await onScreenReady?.call();
  }

  Future<void> _pop() async {
    navigator.currentState?.popUntil((route) => route.isFirst);
    await pause(const Duration(milliseconds: 240));
  }

  /// Что сделать с только что открытым экраном, ПОКА КАДР ЕЩЁ ТЁМНЫЙ.
  ///
  /// Сюда режиссёр подставляет докрутку до метки. Без этого она случалась
  /// после проявления: сцена появлялась, и первым, что видел зритель, был
  /// самостоятельно едущий список. Прокрутка — работа по подготовке кадра, и
  /// её место там же, где смена экрана, — в темноте.
  Future<void> Function()? onScreenReady;

  /// Вспышка на событии игры.
  ///
  /// Не на переходе: переход прячут темнотой, а вспышкой ставят точку. Она
  /// стоит ровно там, где в игре случается необратимое, — на гибели.
  Future<void> flash() => veil.flash();

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

  /// Самый верхний вертикальный список на экране.
  ///
  /// Ищется обходом дерева, а не через `PrimaryScrollController`: экраны игры
  /// заводят списки сами и наружу их не отдают, а трейлеру нельзя требовать
  /// правок в игре. Последний найденный — тот, что в верхнем маршруте: routes
  /// лежат в навигаторе по порядку, и обход в глубину доходит до верхнего
  /// последним.
  ScrollableState? _topScrollable() {
    ScrollableState? found;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final state = e.state as ScrollableState;
        if (state.position.hasPixels &&
            state.position.axis == Axis.vertical) {
          found = state;
        }
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  /// Докручивает до метки и ставит её в кадр.
  ///
  /// Без этого половина съёмки срывалась в общий план. Экраны игры — ленивые
  /// списки: то, что ниже сгиба, Flutter не строит вовсе, метки там просто
  /// нет, и наводиться камере не на что. Живой человек в этом месте
  /// прокручивает экран — трейлер делает то же самое.
  Future<void> _reveal(String id) async {
    // Откуда начали. Если метки на экране нет вовсе — наёмник не на развилке,
    // сундук пуст, — поиск иначе укатывает экран в самый низ и оставляет его
    // там: в дубль попал список построек под подписью «The path splits».
    final from = _topScrollable()?.position.pixels;

    for (var step = 0; step < 24 && !_done && mounted; step++) {
      final anchor = TutorialAnchor.contextOf(id);
      if (anchor != null && anchor.mounted) {
        await Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          // Чуть выше середины: там же, где камера держит цель, и там, где
          // её не перекрывает подпись.
          alignment: 0.38,
        );
        return;
      }

      final list = _topScrollable();
      if (list == null) return;
      final at = list.position;
      if (at.pixels >= at.maxScrollExtent) break;
      // Шаг длиннее и с замедлением на концах. Короткие линейные рывки по
      // 240 точек читались на записи как дёрганый список, а не как поиск: в
      // кадре видно каждую остановку.
      await at.animateTo(
        math.min(at.pixels + 320, at.maxScrollExtent),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
      );
    }

    // Не нашли — возвращаем экран туда, где он был.
    final back = _topScrollable();
    if (from != null && back != null && back.position.hasPixels) {
      await back.position.animateTo(
        from.clamp(0.0, back.position.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _run() async {
    for (final beat in widget.script) {
      if (_done || !mounted) return;
      await _held();

      // Подпись встаёт ДО действия, камера — после. Это не симметрия ради
      // симметрии: действие бывает долгим — перемотка спуска идёт секунды, —
      // и подпись, поставленная после него, всё это время показывает текст
      // предыдущего кадра поверх уже другой картинки. Камере же наоборот
      // нужен построенный экран, иначе метки, на которую она наводится, ещё
      // нет и наезд срывается в общий план.
      if (beat.line != _line) setState(() => _line = beat.line);

      // Камера получает новый план ДО действия, а не после.
      //
      // Действие уходит в темноту, и переезд обязан уложиться туда же. Пока
      // план ставился после, порядок был обратный: кадр проявлялся в старой
      // рамке и только потом ехал в новую — то есть зритель видел переезд,
      // ради сокрытия которого затемнение и придумано. Цель камера считает
      // каждый кадр, поэтому наводиться на ещё не построенный экран ей не
      // мешает: пока метки нет, она стоит на общем плане.
      final started = DateTime.now();
      setState(() {
        _shot = beat.shot;
        _move = beat.move;
      });

      final anchor = beat.shot.anchor;
      // Докрутку отдаём площадке: если кадр открывает экран, она выполнит её
      // в темноте перехода — до того, как картинка проявится.
      widget.stage.onScreenReady =
          anchor == null ? null : () => _reveal(anchor);

      try {
        await beat.act?.call(widget.stage);
      } catch (_) {
        // Кадр, который не удался, не должен ронять трейлер. Игра могла уйти
        // не туда — наёмник умер раньше развилки, сундук полон, — и это
        // повод пропустить кадр, а не оборвать дубль на середине.
      } finally {
        widget.stage.onScreenReady = null;
      }

      // Кадр без смены экрана докручивается здесь: прятать нечего, экран уже
      // на месте, и живая прокрутка к цели читается как взгляд, а не как сбой.
      if (anchor != null) await _reveal(anchor);

      if (_done || !mounted) return;

      // Держим кадр столько, сколько задано, минус то, что уже ушло на
      // действие. Иначе кадры со сменой экрана стояли бы дольше остальных
      // ровно на длину перехода — и ролик провисал бы там, где он и так
      // ничего не показывал.
      final left = beat.move - DateTime.now().difference(started);
      await widget.stage
          .pause((left.isNegative ? Duration.zero : left) + beat.hold);
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
          // Плёнка обнимает камеру, а не лежит поверх всего: виньетка и
          // затемнение переходов — это про картинку, а подпись про неё же не
          // должна темнеть вместе с ней. В темноте перехода текст остаётся —
          // так читается смена сцены, а не сбой показа.
          TrailerFilm(
            veil: widget.stage.veil,
            child: TrailerCamera(
              shot: _shot,
              move: _move,
              child: IgnorePointer(child: widget.child),
            ),
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
