import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

/// Дымовая проба Flame: доказывает, что боевая сцена встраивается в обычный
/// Flutter-экран и тикает независимо от него. Это НЕ дизайн боя — вся
/// боевая графика делается в Фазе 5 по собственному UI/UX.
///
/// Важное для порта: Flame здесь получает уже посчитанные ядром числа и
/// только рисует их. Ни одной формулы внутри `game/` быть не должно —
/// иначе офлайн-расчёт и онлайн-бой начнут расходиться (`docs/01-ANALYSIS.md` §3).
class BattleProbeGame extends FlameGame {
  BattleProbeGame({this.enemyCount = 4});

  final int enemyCount;

  @override
  Color backgroundColor() => const Color(0xFF12100F);

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < enemyCount; i++) {
      add(_ProbeEnemy(index: i, total: enemyCount));
    }
  }
}

class _ProbeEnemy extends Component with HasGameReference<FlameGame> {
  _ProbeEnemy({required this.index, required this.total});

  final int index;
  final int total;

  double _t = 0.0;

  static final _body = Paint()..color = const Color(0xFF8C4A3F);
  static final _hpBack = Paint()..color = const Color(0xFF2A2422);
  static final _hpFill = Paint()..color = const Color(0xFFC7643F);

  /// «HP» здесь декоративный: настоящее значение придёт из `WaveOutcome`.
  double get _hp => 0.5 + 0.5 * math.sin(_t * 1.6 + index);

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final size = game.size;
    if (size.x <= 0 || size.y <= 0) return;

    final step = size.x / (total + 1);
    final cx = step * (index + 1);
    final cy = size.y * 0.55 + math.sin(_t * 2.0 + index) * 6.0;
    final r = math.min(step * 0.28, 26.0);

    canvas.drawCircle(Offset(cx, cy), r, _body);

    final barW = r * 2.4;
    final bar = Rect.fromLTWH(cx - barW / 2, cy - r - 12.0, barW, 5.0);
    canvas.drawRect(bar, _hpBack);
    canvas.drawRect(
      Rect.fromLTWH(bar.left, bar.top, bar.width * _hp, bar.height),
      _hpFill,
    );
  }
}

/// Готовый виджет для встраивания в любой экран.
GameWidget<BattleProbeGame> battleProbeWidget() =>
    GameWidget<BattleProbeGame>.controlled(gameFactory: BattleProbeGame.new);
