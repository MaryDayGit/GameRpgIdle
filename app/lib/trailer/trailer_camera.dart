import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/coach_mark.dart';

/// Куда смотрит камера в этом кадре.
///
/// Данные, а не виджет: сценарий (`trailer_script.dart`) описывает съёмку и
/// ничего не знает про матрицы, камера ничего не знает про игру.
@immutable
class TrailerShot {
  const TrailerShot({
    this.anchor,
    this.fill = 0.72,
    this.gravity = 0.42,
    this.maxZoom = 3.2,
  });

  /// Общий план: вся Застава целиком.
  static const wide = TrailerShot();

  /// Метка [TutorialAnchor], на которую наезжает камера. `null` — общий план.
  ///
  /// Метки уже расставлены по экранам обучением, и это не совпадение: место,
  /// на которое стоит показать пальцем новичку, — ровно то место, которое
  /// стоит показать в трейлере.
  final String? anchor;

  /// Какую долю кадра должна занять цель. Больше — ближе наезд.
  final double fill;

  /// Где по высоте кадра стоит цель: 0 — вверху, 1 — внизу.
  ///
  /// По умолчанию выше середины, потому что нижнюю треть занимает подпись, а
  /// в соцсетях — ещё и лента с кнопками поверх видео.
  final double gravity;

  /// Дальше камера не наезжает. Интерфейс нарисован векторно и не мылится,
  /// но с четырёхкратного увеличения кадр перестаёт быть похож на телефон.
  final double maxZoom;
}

/// Положение камеры: куда смотрит и насколько близко.
@immutable
class _Frame {
  const _Frame(this.focus, this.scale);

  final Offset focus;
  final double scale;

  static _Frame lerp(_Frame a, _Frame b, double t) => _Frame(
        Offset.lerp(a.focus, b.focus, t)!,
        a.scale + (b.scale - a.scale) * t,
      );
}

/// Камера над живой игрой.
///
/// Не запись экрана и не картинки: под камерой работает настоящее приложение
/// со своими экранами, а наезд — это `Transform` поверх них. Flutter рисует
/// текст в уже преобразованных координатах, поэтому при увеличении подписи
/// остаются резкими, а не превращаются в кашу из пикселей, как было бы с
/// увеличением снятого кадра.
///
/// Цель пересчитывается КАЖДЫЙ кадр, а не один раз при смене плана. Экран,
/// который только что открылся, ещё не имеет разметки, список может доехать
/// до места на полсекунды позже, — одноразовый расчёт промахнулся бы, и
/// камера уехала бы в пустоту. Пересчёт стоит одного `localToGlobal`.
class TrailerCamera extends StatefulWidget {
  const TrailerCamera({
    super.key,
    required this.shot,
    required this.child,
    this.move = const Duration(milliseconds: 1100),
  });

  final TrailerShot shot;
  final Widget child;

  /// Сколько длится переезд между планами.
  final Duration move;

  @override
  State<TrailerCamera> createState() => _TrailerCameraState();
}

class _TrailerCameraState extends State<TrailerCamera>
    with TickerProviderStateMixin {
  /// Ключ мира — того, что ЛЕЖИТ ПОД преобразованием.
  ///
  /// Мерить метки надо относительно него, а не относительно самой камеры:
  /// координаты, снятые поверх преобразования, уже включают текущий наезд, и
  /// камера погналась бы за собственным хвостом.
  final GlobalKey _worldKey = GlobalKey(debugLabel: 'trailer:world');

  late final AnimationController _move;

  /// Медленное дыхание кадра. Работает всегда: неподвижная картинка на
  /// вертикальном видео читается как зависшее приложение, а не как игра.
  late final AnimationController _drift;

  _Frame? _from;
  _Frame? _current;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: widget.move)
      ..addListener(_onFrame);
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 19),
    )..repeat();
  }

  @override
  void didUpdateWidget(TrailerCamera old) {
    super.didUpdateWidget(old);
    if (old.shot != widget.shot) {
      _from = _current;
      _move
        ..duration = widget.move
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _drift.dispose();
    super.dispose();
  }

  void _onFrame() {
    if (mounted) setState(() {});
  }

  /// Размер мира. Совпадает с размером кадра: преобразование не меняет
  /// разметку, поэтому приложение под камерой раскладывается во весь экран.
  Size? get _worldSize {
    final box = _worldKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.size;
  }

  /// Куда камера хочет смотреть прямо сейчас.
  _Frame _target(Size view) {
    final world = _worldSize ?? view;
    final centre = Offset(world.width / 2, world.height / 2);

    final anchor = widget.shot.anchor;
    if (anchor == null) return _Frame(centre, 1);

    final rect = TutorialAnchor.rectOf(
      anchor,
      _worldKey.currentContext?.findRenderObject(),
    );
    // Метки на экране нет — например, раздел ещё не открылся или список до
    // неё не доехал. Общий план вместо наезда в пустоту: сценарий не должен
    // ломаться от того, что кнопку переставили.
    if (rect == null || rect.isEmpty) return _Frame(centre, 1);

    final scale = math.min(
      view.width * widget.shot.fill / rect.width,
      view.height * widget.shot.fill / rect.height,
    ).clamp(1.0, widget.shot.maxZoom);

    return _Frame(rect.center, scale.toDouble());
  }

  /// Не выпускает край мира в кадр.
  ///
  /// При наезде видно окно размером `кадр / увеличение`. Если центр этого
  /// окна не удержать, за краем интерфейса появляется пустота — и зритель
  /// видит не игру, а как её показывают.
  Offset _clamp(Offset focus, double scale, Size view, Size world) {
    final target = Offset(view.width / 2, view.height * widget.shot.gravity);

    double axis(double value, double t, double viewLen, double worldLen) {
      final lo = t / scale;
      final hi = worldLen - (viewLen - t) / scale;
      if (lo > hi) return worldLen / 2;
      return value.clamp(lo, hi);
    }

    return Offset(
      axis(focus.dx, target.dx, view.width, world.width),
      axis(focus.dy, target.dy, view.height, world.height),
    );
  }

  Matrix4 _matrix(_Frame frame, Size view, Size world) {
    // Дыхание: полпроцента наезда и пара пикселей увода. Незаметно как приём
    // и заметно как жизнь.
    final phase = _drift.value * 2 * math.pi;
    final scale = frame.scale * (1 + 0.006 * math.sin(phase));
    final focus = _clamp(
      frame.focus + Offset(math.sin(phase * 0.7) * 4, math.cos(phase) * 5),
      scale,
      view,
      world,
    );
    final target = Offset(view.width / 2, view.height * widget.shot.gravity);

    return Matrix4.identity()
      ..translateByDouble(target.dx, target.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-focus.dx, -focus.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.biggest;
        final world = _worldSize ?? view;

        final target = _target(view);
        final from = _from;
        final frame = from == null
            ? target
            : _Frame.lerp(
                from,
                target,
                Curves.easeInOutCubic.transform(_move.value),
              );
        _current = frame;

        return ClipRect(
          child: Transform(
            transform: _matrix(frame, view, world),
            child: KeyedSubtree(key: _worldKey, child: widget.child),
          ),
        );
      },
    );
  }
}
