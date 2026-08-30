import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:rift/core/sim/combat_feed.dart';

import 'combat_animation.dart';
import 'silhouettes.dart';

/// То, что боевая сцена знает о бое.
///
/// Интерфейс, а не ссылка на симуляцию: Flame обязан только рисовать. Любая
/// формула, просочившаяся в сцену, — это расхождение картинки с журналом и
/// офлайн-расчётом, и заметят его игроки, а не тесты (`docs/02-TECH.md` §1).
abstract class BattleView {
  double get heroHpFraction;

  /// Доля маны. Мана — общий бюджет активных способностей, и без полоски
  /// игрок не поймёт, почему наёмник перестал ими бить.
  double get heroManaFraction;

  String get heroName;

  /// Чем вооружён наёмник. Билд собирается руками, и в бою это должно быть
  /// видно.
  HeroWeapon get heroWeapon;

  /// Доли здоровья живых и мёртвых врагов волны, в порядке волны.
  List<double> get enemyHpFractions;

  /// `id` архетипов той же волны, в том же порядке. По ним ищутся силуэты.
  List<String> get enemyIds;

  /// Забирает то, что случилось в бою с прошлого кадра. Именно забирает:
  /// удар анимируется один раз, а не каждый кадр, пока идёт волна.
  List<CombatBeat> takeBeats();

  String get enemyName;

  bool get bossWave;
  double get waveProgress;
}

/// Боевая сцена: герой слева, волна справа.
///
/// Фигуры рисуются кодом, а не спрайтами (см. [Silhouette]). Требование к
/// картинке одно и оно не про красоту: по силуэту должно быть понятно, КТО
/// перед героем, — иначе бой остаётся текстовым логом, только медленнее.
class BattleScene extends FlameGame {
  BattleScene(this.view);

  final BattleView view;

  @override
  Color backgroundColor() => const Color(0xFF15100E);

  @override
  Future<void> onLoad() async {
    add(_Field(view));
  }
}

/// Раскладка волны: где стоят фигуры и какого они роста.
///
/// Отдельно от рисования, потому что именно здесь уже была ошибка — фигуры
/// вылезали за край экрана. Проверить это на картинке нельзя, а на числах
/// можно: `wave_layout_test` прогоняет её по всем размерам пачки и экрана.
class WaveLayout {
  const WaveLayout({
    required this.height,
    required this.figureWidth,
    required this.positions,
    required this.lifts,
  });

  /// Рост фигуры в пикселях.
  final double height;

  /// Ширина фигуры — рост, умноженный на её пропорцию.
  final double figureWidth;

  /// Центры фигур по горизонтали, слева направо.
  final List<double> positions;

  /// Подъём каждой фигуры над линией земли. Ноль — передний ряд.
  ///
  /// Большая пачка в одну строку сжимается в точки: полоса делится на всех,
  /// а высота при этом простаивает. Задний ряд занимает пустоту вверху и
  /// позволяет фигурам остаться крупными.
  final List<double> lifts;

  /// Зазор между соседями в пикселях.
  double get gap => height * _gap;

  /// [aspect] — ширина фигуры в долях роста, [scale] — во сколько раз она
  /// крупнее обычного моба (босс — крупнее).
  static WaveLayout compute({
    required int count,
    required double left,
    required double right,
    required double screenHeight,
    required double aspect,
    double scale = 1.0,
  }) {
    final usable = math.max(0.0, right - left);

    // Большая пачка становится двумя рядами. В одну строку шесть мобов
    // делят полосу на шесть и превращаются в точки, хотя над ними пустует
    // половина арены.
    final rows = count > _maxPerRow ? 2 : 1;
    final perRow = rows == 1 ? count : (count / rows).ceil();

    // На фигуру нужна её ширина плюс зазор — иначе соседи соприкасаются, и
    // пачка читается одним пятном вместо пяти противников. Всё считается в
    // долях РОСТА, поэтому масштаб босса входит ровно один раз.
    // Полшага сверху — место под смещение заднего ряда: без запаса он
    // упирается в край и садится ровно за передний.
    final slots = perRow + (rows > 1 ? 0.5 : 0.0);
    final byWidth =
        perRow <= 0 ? usable : usable / (slots * (aspect + _gap) * scale);

    // Два ряда делят и высоту: задний ряд поднимается, и вместе они обязаны
    // остаться в полосе.
    final byHeight = screenHeight * (rows == 1 ? 0.30 : 0.22);
    final height =
        math.min(math.min(byWidth, byHeight), maxHeight).clamp(12.0, maxHeight);

    final h = height * scale;
    final figure = h * aspect;
    final gap = h * _gap;

    final positions = <double>[];
    final lifts = <double>[];

    for (var row = 0; row < rows; row++) {
      final inRow = row == 0
          ? math.min(perRow, count)
          : count - math.min(perRow, count);
      if (inRow <= 0) continue;

      final span = figure * inRow + gap * (inRow - 1);

      // Пачка ставится по центру полосы, а не прижимается к краю: волна из
      // одного и волна из пяти должны занимать одно и то же место, иначе бой
      // прыгает по экрану на каждой смене врага. Задний ряд смещён на
      // полшага — иначе он прячется ровно за передним.
      // Ряды разъезжаются симметрично: передний на полшага влево, задний
      // на полшага вправо. Так задний не прячется за передним и оба
      // остаются в полосе — запас под это заложен в `slots`.
      final stagger =
          rows == 1 ? 0.0 : (row == 0 ? -1 : 1) * (figure + gap) / 4;
      final startX = left + (usable - span) / 2 + figure / 2 + stagger;

      for (var i = 0; i < inRow; i++) {
        positions.add(startX + i * (figure + gap));
        lifts.add(row == 0 ? 0.0 : h * _backRowLift);
      }
    }

    return WaveLayout(
      height: h,
      figureWidth: figure,
      positions: positions,
      lifts: lifts,
    );
  }

  /// Зазор между соседями в долях роста.
  static const _gap = 0.25;

  /// Больше этого числа в ряду — пачка встаёт двумя рядами.
  static const _maxPerRow = 4;

  /// Насколько задний ряд поднят над линией земли, в долях роста.
  static const _backRowLift = 0.55;

  /// Выше этого фигура перестаёт быть участником боя и становится фоном.
  static const maxHeight = 200.0;
}

/// Где проходит линия земли.
///
/// Композиция стоит по центру полосы, а не на фиксированной доле высоты:
/// раньше линия делила поле на 74 %, и на высоком телефоне над бойцами
/// оставалось пустое поле в половину экрана. Отдельная функция, потому что
/// на низкой полосе границы сходятся, и «просто clamp» падает.
double groundLineFor({required double fieldHeight, required double tallest}) {
  const bottom = 6.0;
  final lowest = math.max(0.0, fieldHeight - bottom);

  // Над самой высокой фигурой нужно место на полоску здоровья.
  final highest = math.min(tallest * 1.25, lowest);
  final centered = fieldHeight * 0.5 + tallest * 0.5;

  return centered.clamp(highest, lowest);
}

class _Field extends Component with HasGameReference<FlameGame> {
  _Field(this.view);

  final BattleView view;

  double _time = 0.0;

  /// Что показывает бой сверх полосок: замах, попадание, падение.
  /// Считается по событиям боя — см. [BattleAnimations].
  final _anims = BattleAnimations();

  static final _barBack = Paint()..color = const Color(0xFF2A2422);
  static final _barHero = Paint()..color = const Color(0xFF7FB069);
  static final _barMana = Paint()..color = const Color(0xFF5B8DD9);
  static final _barEnemy = Paint()..color = const Color(0xFFC7643F);

  static const _hitColor = Color(0xFFFFE3B3);

  @override
  void update(double dt) {
    _time += dt;
    _anims.apply(view.takeBeats());
    _anims.syncDeaths(view.enemyHpFractions);
    _anims.tick(dt);
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    if (size.x <= 0 || size.y <= 0) return;

    final enemies = view.enemyHpFractions;
    final ids = view.enemyIds;

    // Пачка — это один архетип, поэтому ширина считается по первому: у пеплоеда
    // и падальщика она отличается вдвое, и общая мерка «фигура шириной с рост»
    // либо разносит пламя по всему экрану, либо склеивает падальщиков в пятно.
    final look = silhouetteFor(ids.isEmpty ? '' : ids.first);
    final bossScale = view.bossWave ? 1.7 : 1.0;

    // Размер фигур считается от полосы, в которую они обязаны поместиться,
    // а не от размеров экрана: на высоком телефоне «доля от высоты» давала
    // фигуры шире отведённого места, и волна вылезала за край.
    final layout = WaveLayout.compute(
      count: enemies.length,
      left: size.x * 0.36,
      right: size.x * 0.95,
      screenHeight: size.y,
      aspect: look.aspect,
      scale: bossScale,
    );

    // --- Герой ---------------------------------------------------------------
    //
    // Рост героя не зависит от волны. Если считать его от размера мобов, он
    // будет ужиматься на пачке из пяти и вырастать на боссе — фигура игрока
    // прыгала бы в размере каждую волну, а она здесь единственная постоянная.
    //
    // Но и возвышаться над волной вдвое он не должен: пачка из пяти мелких
    // делает фигуры узкими, и герой рядом с ними выглядел великаном. Отсюда
    // потолок в долях от роста мобов.
    final heroLook = heroSilhouette(view.heroWeapon);
    final heroX = size.x * 0.16;
    final heroHeight = math.min(
      math.min(size.y * 0.30, WaveLayout.maxHeight) * 1.05,
      layout.height * 1.4,
    );

    // Бой идёт на линии, а не висит в пустоте. Земля даёт фигурам опору,
    // и вся сцена стоит по центру полосы: раньше линия делила экран на
    // 74 %, и на высоком телефоне над бойцами оставалось пустое поле
    // в половину экрана.
    final groundY = groundLineFor(
      fieldHeight: size.y,
      // Задний ряд поднят над землёй, и место под него нужно заложить: иначе
      // на двухрядной пачке верхние фигуры уезжают под шапку экрана.
      tallest: math.max(
        heroHeight,
        layout.height + (layout.lifts.isEmpty ? 0.0 : layout.lifts.reduce(math.max)),
      ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, groundY + 2, size.x, 1.2),
      Paint()..color = const Color(0x22D9C8A9),
    );

    final breath = math.sin(_time * 2.2) * 0.008 * heroHeight;

    // Замах — рывок навстречу волне. Без него герой бьёт неотличимо от того,
    // как он стоит, и бой читается только по полоскам.
    final lunge = _anims.hero.swing * heroHeight * 0.10 -
        _anims.hero.recoil * heroHeight * 0.04;

    if (_anims.cast > 0) {
      canvas.drawCircle(
        Offset(heroX, groundY - heroHeight * 0.45),
        heroHeight * (0.35 + 0.55 * (1.0 - _anims.cast)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + 2.0 * _anims.cast
          ..color =
              const Color(0xFF7FB069).withValues(alpha: 0.45 * _anims.cast),
      );
    }

    _draw(
      canvas,
      heroLook,
      Offset(heroX + lunge, groundY + breath),
      heroHeight,
      anim: _anims.hero,
    );
    final barWidth = heroHeight * heroLook.aspect * 0.8;
    _bar(
      canvas,
      heroX,
      groundY - heroHeight * 1.10,
      barWidth,
      view.heroHpFraction,
      _barHero,
      size.x,
    );
    // Мана — второй полоской под здоровьем и тоньше: она про способности,
    // а не про жизнь, и путать их нельзя.
    _bar(
      canvas,
      heroX,
      groundY - heroHeight * 1.10 + 6.0,
      barWidth,
      view.heroManaFraction,
      _barMana,
      size.x,
      height: 3.0,
    );

    if (enemies.isEmpty) return;

    // --- Волна ---------------------------------------------------------------
    final h = layout.height;
    final gapWidth = layout.gap * 0.8;

    for (var i = 0; i < enemies.length; i++) {
      final hp = enemies[i];
      final alive = hp > 0.0;
      final each = silhouetteFor(i < ids.length ? ids[i] : '');

      final anim = _anims.enemy(i);
      final x = layout.positions[i] + anim.recoil * h * 0.06;
      final lift = i < layout.lifts.length ? layout.lifts[i] : 0.0;
      final bob = math.sin(_time * 1.8 + i * 0.7) * 0.012 * h;

      // Гаснет фигура ПОСЛЕ падения, а не в момент смерти: иначе моб темнеет
      // раньше, чем начинает заваливаться, и падает уже труп.
      _draw(
        canvas,
        anim.fallen ? each.dead : each,
        Offset(x, groundY + bob - lift),
        h,
        anim: anim,
      );

      if (alive) {
        // Ширина полоски — от ширины ФИГУРЫ, а не от роста. У пеплоеда рост
        // вдвое больше ширины, и полоски «в три четверти роста» сливались
        // над волной в одну сплошную черту.
        _bar(
          canvas,
          x,
          groundY - lift - h * 1.10,
          math.min(layout.figureWidth * 1.15, layout.figureWidth + gapWidth),
          hp,
          _barEnemy,
          size.x,
        );
      }
    }
  }

  /// Фигура с тенью на земле и вспышкой на попадании.
  ///
  /// Вспышка повторяет силуэт, а не рисуется кругом вокруг: круг сообщал
  /// «здесь что-то произошло», а подсвеченная фигура — «попали именно по ней».
  void _draw(
    Canvas canvas,
    Silhouette look,
    Offset feet,
    double height, {
    required FigureAnim anim,
  }) {
    // Падение: фигура заваливается и гаснет, а не исчезает подменой цвета.
    // Пропавший без падения моб читается как сбой отрисовки, а не как смерть.
    final falling = anim.falling;
    final alpha = falling > 0.0 ? (1.0 - falling * 0.55) : 1.0;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(feet.dx, feet.dy + 3),
        width: height * look.aspect * 0.9 * (1.0 - falling * 0.3),
        height: height * 0.10,
      ),
      Paint()..color = Color(0x33000000).withValues(alpha: 0.20 * alpha),
    );

    if (falling > 0.0) {
      canvas.save();
      canvas.translate(feet.dx, feet.dy);
      canvas.rotate(falling * 1.25);
      canvas.translate(-feet.dx, -feet.dy);
    }

    look.draw(Sketch(
      canvas: canvas,
      feet: feet,
      height: height,
      t: _time,
      body: look.body,
      accent: look.accent,
      alpha: alpha,
    ));

    if (anim.flash > 0) {
      look.draw(Sketch(
        canvas: canvas,
        feet: feet,
        height: height,
        t: _time,
        body: _hitColor,
        accent: _hitColor,
        alpha: 0.55 * anim.flash,
      ));
    }

    if (falling > 0.0) canvas.restore();
  }

  void _bar(
    Canvas canvas,
    double centerX,
    double y,
    double width,
    double fraction,
    Paint fill,
    double fieldWidth, {
    double height = 4.0,
  }) {
    // Полоска не выходит за край поля: у героя она шире его фигуры, а сам он
    // стоит близко к левому краю — и полоска обрезалась экраном.
    final half = width / 2;
    final x = centerX.clamp(
      math.min(half + 4.0, fieldWidth / 2),
      math.max(fieldWidth - half - 4.0, fieldWidth / 2),
    );
    final rect = Rect.fromLTWH(x - half, y, width, height);
    canvas.drawRect(rect, _barBack);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width * fraction.clamp(0.0, 1.0),
          rect.height),
      fill,
    );
  }
}
