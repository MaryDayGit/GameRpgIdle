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
    this.zoom = 1,
    this.fill = 0.5,
    this.gravity = 0.4,
    this.minZoom = 1.2,
    this.maxZoom = 1.9,
    this.push = 0.12,
  });

  /// Общий план: вся Застава целиком. Наезда нет, но кадр всё равно живёт —
  /// его медленно ведёт [push].
  static const wide = TrailerShot(push: 0.13);

  /// Масштаб плана БЕЗ метки.
  ///
  /// Нужен экранам, внутри которых меток нет вовсе, — древо Эха, кузница,
  /// сундук. Наводиться там не на что, а показывать их совсем общим планом
  /// значит четыре кадра подряд не двигаться. Заводить ради трейлера метки в
  /// самой игре нельзя: как только он потребует правок в игре, он перестанет
  /// показывать игру.
  final double zoom;

  /// Метка [TutorialAnchor], на которую наезжает камера. `null` — общий план.
  ///
  /// Метки уже расставлены по экранам обучением, и это не совпадение: место,
  /// на которое стоит показать пальцем новичку, — ровно то место, которое
  /// стоит показать в трейлере.
  final String? anchor;

  /// Какую долю ВЫСОТЫ кадра занимает цель. Меньше — ближе наезд.
  ///
  /// Именно высоты. Кадр вертикальный, а почти всё в игре — панели во всю
  /// ширину экрана: по ширине они заполнены и без наезда, и рамка, взятая
  /// как минимум из двух сторон, давала масштаб 1.0 — то есть неподвижную
  /// картинку. Высота — единственная сторона, по которой в этом кадре есть
  /// куда наезжать.
  final double fill;

  /// Где по высоте кадра стоит цель: 0 — вверху, 1 — внизу.
  ///
  /// Выше середины, потому что нижнюю треть занимает подпись, а в соцсетях —
  /// ещё и лента с кнопками поверх видео.
  final double gravity;

  /// Ближе какого масштаба камера не отъезжает.
  ///
  /// Уступает ограничению по ширине, и это важнее, чем кажется. Сначала было
  /// наоборот — «наезд, которого не видно, хуже его отсутствия», — и минимум
  /// перебивал ширину: панель во всю ширину послушно наезжала до 1.35 и
  /// теряла по краям «Floor 62» и таймер. Наезд, режущий то, ради чего снят
  /// кадр, хуже отсутствия наезда. Движение в таком плане даёт [push].
  final double minZoom;

  /// Дальше камера не наезжает.
  ///
  /// Двукратного хватает: на живом прогоне сетка снаряжения при 2.6 вылезала
  /// за оба края кадра, и вместо девяти слотов зритель видел четыре.
  final double maxZoom;

  /// Насколько кадр «подъезжает» за время плана. 0.09 — девять процентов.
  ///
  /// Медленное непрерывное движение — единственное, что отличает кадр игры
  /// от снимка экрана. Без него вертикальное видео читается как зависшее
  /// приложение.
  final double push;

  /// Сколько ширины цели обязано остаться в кадре.
  ///
  /// Наезд по высоте неизбежно режет края широкой панели, и цена этого
  /// выяснилась на живом прогоне: при допуске в треть карточка спуска
  /// лишилась «Floor 62» слева и таймера справа — то есть ровно тех двух
  /// чисел, ради которых кадр и снимался. Содержимое панелей прижато к краям,
  /// а не к центру, поэтому резать почти нечего: девяносто три процента.
  static const keepWidth = 0.93;
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

  /// Подъезд кадра. Не покачивание, а движение в одну сторону: камера всё
  /// время идёт вперёд, и это единственное, что отличает кадр игры от снимка
  /// экрана. Перезапускается на каждом плане.
  late final AnimationController _push;

  _Frame? _from;
  _Frame? _current;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: widget.move)
      ..addListener(_onFrame);
    // Подписан на перерисовку так же, как переезд: без этого подъезд замирал
    // бы ровно в тот момент, когда камера доехала до плана, — то есть на всё
    // время, пока кадр стоит и его как раз смотрят.
    _push = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )
      ..addListener(_onFrame)
      ..forward();
  }

  @override
  void didUpdateWidget(TrailerCamera old) {
    super.didUpdateWidget(old);
    if (old.shot != widget.shot) {
      _from = _current;
      _move
        ..duration = widget.move
        ..forward(from: 0);
      _push.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _push.dispose();
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
    if (anchor == null) return _Frame(centre, widget.shot.zoom);

    final rect = TutorialAnchor.rectOf(
      anchor,
      _worldKey.currentContext?.findRenderObject(),
    );
    // Метки на экране нет — например, раздел ещё не открылся или список до
    // неё не доехал. Общий план вместо наезда в пустоту: сценарий не должен
    // ломаться от того, что кнопку переставили.
    if (rect == null || rect.isEmpty) return _Frame(centre, widget.shot.zoom);

    // Рамка по высоте — и ограничение, чтобы не срезать цель по бокам.
    final byHeight = view.height * widget.shot.fill / rect.height;
    final widthLimit = view.width / (rect.width * TrailerShot.keepWidth);

    // Порядок здесь и есть правило: сначала желаемое, потом потолок, и
    // ТОЛЬКО ПОТОМ ширина. Ширина — последнее слово, иначе минимальный наезд
    // перебивает её и режет цель по краям.
    final wanted =
        byHeight.clamp(widget.shot.minZoom, widget.shot.maxZoom).toDouble();
    final scale = math.max(1.0, math.min(wanted, widthLimit));

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
    // Подъезд: кадр весь план идёт вперёд и чуть вверх, с замедлением к
    // концу. Величина у каждого плана своя — общий план едет заметнее, ему
    // нечем больше жить.
    final t = Curves.easeOutSine.transform(_push.value);
    final scale = frame.scale * (1 + widget.shot.push * t);
    final focus = _clamp(
      frame.focus + Offset(0, -14 * t),
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
