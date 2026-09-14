import 'package:flutter/material.dart';

/// Затемнение кадра: переходы и вспышки.
///
/// Живёт отдельно от камеры и от подписей, потому что им управляет площадка,
/// а не сценарий: смена экрана — это работа, которую надо СПРЯТАТЬ. Без него
/// каждый переход между разделами показывал зрителю механику показа: маршрут
/// уезжает вбок, следом второй, камера прыгает на новую метку, список
/// докручивается. Четыре движения на одно событие, и ни одно из них не про
/// игру.
///
/// Анимируется вручную короткими шагами, а не `AnimationController`: площадка
/// — не виджет, тикера у неё нет, а дождаться конца затемнения ей надо, чтобы
/// поменять экран ровно в темноте.
class TrailerVeil extends ChangeNotifier {
  double _opacity = 0;
  Color _color = Colors.black;
  bool _stopped = false;

  double get opacity => _opacity;
  Color get color => _color;

  void stop() => _stopped = true;

  /// Затемнить, сделать дело, проявиться.
  ///
  /// Уход в темноту короче возвращения нарочно: так режут в кино. Быстрый
  /// уход читается как решение монтажёра, медленный вход — как новая сцена.
  Future<void> dip(
    Future<void> Function() body, {
    Duration out = const Duration(milliseconds: 220),
    Duration back = const Duration(milliseconds: 380),
  }) async {
    await _to(1, out, color: Colors.black);
    try {
      await body();
    } finally {
      await _to(0, back);
    }
  }

  /// Короткая вспышка. Ставится на событие игры, а не между кадрами.
  Future<void> flash({
    Color color = const Color(0xFFFFE9D6),
    double peak = 0.72,
  }) async {
    await _to(peak, const Duration(milliseconds: 70), color: color);
    await _to(0, const Duration(milliseconds: 460));
    _color = Colors.black;
  }

  Future<void> _to(double target, Duration d, {Color? color}) async {
    if (_stopped) return;
    if (color != null) _color = color;

    const step = Duration(milliseconds: 16);
    final steps = (d.inMilliseconds / step.inMilliseconds).ceil().clamp(1, 600);
    final from = _opacity;

    for (var i = 1; i <= steps && !_stopped; i++) {
      _opacity = from + (target - from) * (i / steps);
      notifyListeners();
      await Future<void>.delayed(step);
    }
    if (_stopped) return;
    _opacity = target;
    notifyListeners();
  }
}

/// Плёнка поверх игры: виньетка и затемнение.
///
/// Виньетка — единственный эффект, который трейлер накладывает всегда. Она не
/// украшение: снимок экрана отличается от кадра ровно тем, что у кадра есть
/// края. Ровная яркость до самой рамки читается как скриншот, даже когда
/// картинка движется.
///
/// Центр смещён вверх, туда же, куда камера ставит цель ([TrailerShot.gravity]).
/// Получается фокус: взгляд идёт к самому светлому месту, а самое светлое
/// место — то, ради чего снят кадр.
class TrailerFilm extends StatelessWidget {
  const TrailerFilm({
    super.key,
    required this.child,
    required this.veil,
    this.focus = -0.2,
  });

  final Widget child;
  final TrailerVeil veil;

  /// Где по высоте кадра центр виньетки: −1 верх, 1 низ.
  final double focus;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, focus),
                radius: 1.02,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.52),
                ],
                stops: const [0.42, 0.76, 1],
              ),
            ),
          ),
        ),
        // Затемнение переходов — НАД виньеткой и ПОД подписью: в темноте
        // остаётся текст, и это читается как смена сцены, а не как сбой.
        AnimatedBuilder(
          animation: veil,
          builder: (context, _) => veil.opacity <= 0.001
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: ColoredBox(
                    color: veil.color.withValues(alpha: veil.opacity),
                  ),
                ),
        ),
      ],
    );
  }
}
