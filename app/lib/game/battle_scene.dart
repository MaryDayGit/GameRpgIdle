import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/combat_feed.dart';

import 'combat_animation.dart';
import 'vfx.dart';
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

  /// Искры, прах, цифры урона и тряска — см. [Vfx].
  final _vfx = Vfx();

  /// События, которым ещё не нашли места на экране.
  ///
  /// Забираются в `update`, а тратятся в `render`: искре нужна ТОЧКА, а точка
  /// известна только после раскладки волны, то есть при отрисовке. Считать
  /// раскладку дважды было бы дешевле по коду и дороже по кадру, а брать
  /// прошлую — значит бить искрами мимо в тот единственный кадр, когда волна
  /// сменилась.
  final List<CombatBeat> _pending = [];

  /// Была ли прошлая волна боссовой. По смене решается, показывать ли вход.
  bool _wasBoss = false;

  /// Стены бездны позади бойцов.
  final _backdrop = _Backdrop();

  // Цвета полосок — те же, что у полосок под сценой (`ui/theme.dart`):
  // здоровье героя на арене и в сводке обязано быть одним цветом.
  static final _barBack = Paint()..color = const Color(0xE0120C0A);
  static final _barEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x55F3E9DF);
  static final _barHero = Paint()..color = const Color(0xFF8CCB6E);
  static final _barMana = Paint()..color = const Color(0xFF6F9EF0);
  static final _barEnemy = Paint()..color = const Color(0xFFF08A6C);

  /// Сколько ещё держится надпись о входе босса, в секундах.
  double _bossBanner = 0.0;

  /// Название умения, которое готовит страж, и сколько надпись ещё держится.
  ///
  /// Надпись появляется на ЗАМАХЕ, а не на ударе: имя умения полезно ровно
  /// тогда, когда удара ещё не было, — после него оно только объяснение.
  String _skillName = '';
  double _skillBanner = 0.0;
  DamageType _skillType = DamageType.physical;

  @override
  void update(double dt) {
    _time += dt;

    final beats = view.takeBeats();
    _anims.apply(beats, bossWave: view.bossWave);
    if (beats.isNotEmpty) {
      // Потолок на случай перемотки: спуск догоняет тысячами тиков за кадр,
      // и события целой волны могут прийти разом. Искры от каждого удара
      // такой пачки — это не бой, а вспышка на весь экран.
      if (_pending.length > 40) _pending.removeRange(0, _pending.length - 40);
      _pending.addAll(beats);
    }

    _anims.syncDeaths(view.enemyHpFractions);
    _anims.tick(dt);
    if (_bossBanner > 0.0) _bossBanner = math.max(0.0, _bossBanner - dt);
    if (_skillBanner > 0.0) _skillBanner = math.max(0.0, _skillBanner - dt);
    _vfx.tick(dt);
    _vfx.ambient(Size(game.size.x, game.size.y), dt);
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

    final heroLook = heroSilhouette(view.heroWeapon);
    final heroX = size.x * 0.16;
    // Рост героя не зависит от волны. Если считать его от размера мобов, он
    // будет ужиматься на пачке из пяти и вырастать на боссе — фигура игрока
    // прыгала бы в размере каждую волну, а она здесь единственная постоянная.
    //
    // Но и возвышаться над волной вдвое он не должен: пачка из пяти мелких
    // делает фигуры узкими, и герой рядом с ними выглядел великаном. Отсюда
    // потолок в долях от роста мобов.
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
        layout.height +
            (layout.lifts.isEmpty ? 0.0 : layout.lifts.reduce(math.max)),
      ),
    );

    _spawnEffects(layout, enemies, ids, heroX, heroHeight, groundY);

    // Тряска двигает ВСЮ сцену, включая землю и фон: трясти одни фигуры
    // значит показать, что они нарисованы поверх, а не стоят в мире.
    final shake = _vfx.offset;
    canvas.save();
    // Сцена обязана оставаться в своей полосе. Flame её не обрезает, и без
    // этого стены бездны и искры вылезали поверх шапки экрана — на снимке
    // было видно, как камни стоят на заголовке.
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.translate(shake.dx, shake.dy);

    _backdrop.render(canvas, size, groundY, _time, shake);
    _drawGround(canvas, size, groundY);

    // --- Герой ---------------------------------------------------------------
    final breath = math.sin(_time * 2.2) * 0.008 * heroHeight;
    final lunge = _anims.hero.lunge * heroHeight * 0.13 -
        _anims.hero.recoil * heroHeight * 0.04;

    if (_anims.cast > 0) {
      _castRing(canvas, Offset(heroX, groundY - heroHeight * 0.45), heroHeight);
    }

    // След удара: дуга перед героем на самом быстром куске выпада. Силуэт
    // оружия для этого не нужен и даже вреден — у каждого оружия своя фигура,
    // а читается движение, а не железо.
    if (_anims.hero.lunge > 0.45) {
      _slash(canvas, Offset(heroX + lunge, groundY + breath), heroHeight,
          _anims.hero.lunge);
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
      groundY - heroHeight * 1.10 + 10.0,
      barWidth,
      view.heroManaFraction,
      _barMana,
      size.x,
      height: 4.0,
    );

    // --- Волна ---------------------------------------------------------------
    final h = layout.height;
    final gapWidth = layout.gap * 0.8;

    for (var i = 0; i < enemies.length; i++) {
      final hp = enemies[i];
      final alive = hp > 0.0;
      final each = silhouetteFor(i < ids.length ? ids[i] : '');

      final anim = _anims.enemy(i);
      // Моб подаётся к герою — то есть ВЛЕВО: тот же замах, зеркально.
      final x = layout.positions[i] +
          anim.recoil * h * 0.06 -
          anim.lunge * h * 0.11;
      final lift = i < layout.lifts.length ? layout.lifts[i] : 0.0;
      final bob = math.sin(_time * 1.8 + i * 0.7) * 0.012 * h;

      // Босс светится. Не украшение: волна с боссом ничем, кроме размера, не
      // отличалась от обычной, а размер на телефоне — слабый признак. Свечение
      // видно раньше, чем игрок успеет сравнить фигуры.
      if (view.bossWave && alive) {
        _aura(canvas, Offset(x, groundY + bob - lift - h * 0.5), h, each.accent);
      }

      // Замах умения: кольцо стихии сжимается к фигуре по мере того, как
      // удар приближается. Видно боковым зрением и читается как отсчёт.
      if (alive && anim.charge > 0.0) {
        _charge(canvas, Offset(x, groundY + bob - lift - h * 0.5), h,
            anim.charge, lookForDamage(anim.chargeType).core);
      }

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

    // Искры поверх фигур, цифры поверх искр: число, спрятанное за силуэтом
    // босса, не сообщает ничего.
    _vfx.render(canvas);
    _vfx.renderNumbers(canvas);

    canvas.restore();

    // Поверх всего и без тряски: рамка раны и надпись босса — это сообщения
    // игроку, а не часть мира, и дрожать вместе с камнями им незачем.
    _woundVignette(canvas, size, view.heroHpFraction);
    if (_anims.skill > 0.0) _skillFlash(canvas, size);
    if (_bossBanner > 0.0) {
      _drawBossBanner(canvas, size);
    } else if (_skillBanner > 0.0) {
      _drawSkillBanner(canvas, size);
    }
  }

  /// Кольцо замаха: широкое в начале, прижатое к фигуре перед ударом.
  void _charge(Canvas canvas, Offset center, double height, double charge,
      Color color) {
    final radius = height * (1.05 - 0.45 * charge);
    final pulse = 0.75 + 0.25 * math.sin(_time * (8.0 + 10.0 * charge));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + 4.0 * charge
        ..color = color.withValues(alpha: (0.25 + 0.6 * charge) * pulse),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = Gradient.radial(center, radius, [
          color.withValues(alpha: 0.22 * charge),
          color.withValues(alpha: 0.0),
        ]),
    );
  }

  /// Вспышка по краям экрана в момент удара умения — цветом его стихии.
  void _skillFlash(Canvas canvas, Vector2 size) {
    final color = lookForDamage(_anims.skillType).core;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()
        ..shader = Gradient.radial(
          Offset(size.x / 2, size.y / 2),
          math.max(size.x, size.y) * 0.7,
          [
            const Color(0x00000000),
            color.withValues(alpha: 0.35 * _anims.skill),
          ],
          const [0.45, 1.0],
        ),
    );
  }

  /// Имя умения на замахе: узкая полоса над ареной, цветом стихии.
  void _drawSkillBanner(Canvas canvas, Vector2 size) {
    const total = 1.6;
    final t = 1.0 - _skillBanner / total;
    final alpha = t < 0.12 ? t / 0.12 : (t > 0.8 ? (1.0 - t) / 0.2 : 1.0);
    final color = lookForDamage(_skillType).core;
    final y = size.y * 0.06;
    const h = 28.0;

    canvas.drawRect(
      Rect.fromLTWH(0, y, size.x, h),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, y),
          Offset(size.x, y),
          [
            const Color(0x00000000),
            const Color(0xFF120C0A).withValues(alpha: 0.85 * alpha),
            const Color(0xFF120C0A).withValues(alpha: 0.85 * alpha),
            const Color(0x00000000),
          ],
          const [0.0, 0.2, 0.8, 1.0],
        ),
    );
    final label = ParagraphBuilder(ParagraphStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      textAlign: TextAlign.center,
    ))
      ..pushStyle(TextStyle(
        color: color.withValues(alpha: alpha),
        letterSpacing: 2.0,
      ))
      ..addText(_skillName.toUpperCase());
    final paragraph = label.build()
      ..layout(ParagraphConstraints(width: size.x));
    canvas.drawParagraph(paragraph, Offset(0, y + (h - paragraph.height) / 2));
  }

  /// Красная рамка по краям, когда здоровья мало.
  ///
  /// Полоска над героем — в десять точек высотой, и на пачке из пяти мобов
  /// её не видно за искрами. Край экрана, наливающийся красным и дышащий,
  /// видно всегда и сразу: это ровно тот сигнал, после которого отзывают.
  void _woundVignette(Canvas canvas, Vector2 size, double hp) {
    if (hp <= 0.0 || hp >= 0.35) return;
    final danger = 1.0 - hp / 0.35;
    final pulse = 0.75 + 0.25 * math.sin(_time * 6.0);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.x / 2, size.y / 2),
          math.max(size.x, size.y) * 0.75,
          [
            const Color(0x00000000),
            const Color(0xFFB3261E).withValues(alpha: 0.38 * danger * pulse),
          ],
          const [0.55, 1.0],
        ),
    );
  }

  /// Надпись о входе босса: полоса поперёк арены с именем волны.
  ///
  /// Свечение и размер фигуры говорят «этот крупнее», но не говорят «это
  /// босс» — а босс единственный враг, ради которого стоит смотреть бой.
  void _drawBossBanner(Canvas canvas, Vector2 size) {
    const total = 1.8;
    final t = 1.0 - _bossBanner / total;
    // Въезжает, держится, гаснет.
    final alpha = t < 0.15
        ? t / 0.15
        : t > 0.75
            ? (1.0 - t) / 0.25
            : 1.0;
    final y = size.y * 0.16;
    final h = 34.0;

    canvas.drawRect(
      Rect.fromLTWH(0, y, size.x, h),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, y),
          Offset(size.x, y),
          [
            const Color(0x00000000),
            const Color(0xFF3A1709).withValues(alpha: 0.85 * alpha),
            const Color(0xFF3A1709).withValues(alpha: 0.85 * alpha),
            const Color(0x00000000),
          ],
          const [0.0, 0.25, 0.75, 1.0],
        ),
    );
    for (final edge in [y, y + h]) {
      canvas.drawRect(
        Rect.fromLTWH(size.x * 0.15, edge, size.x * 0.7, 1.2),
        Paint()..color = const Color(0xFFE8804F).withValues(alpha: 0.8 * alpha),
      );
    }

    final label = ParagraphBuilder(ParagraphStyle(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      textAlign: TextAlign.center,
    ))
      ..pushStyle(TextStyle(
        color: const Color(0xFFF2B65E).withValues(alpha: alpha),
        letterSpacing: 4.0,
      ))
      ..addText(view.enemyName.toUpperCase());
    final paragraph = label.build()
      ..layout(ParagraphConstraints(width: size.x));
    canvas.drawParagraph(
        paragraph, Offset(0, y + (h - paragraph.height) / 2));
  }

  /// Земля, свет над ней и затемнение по краям.
  ///
  /// Фон здесь не украшение: до него сцена была фигурами в пустоте, и глубина
  /// боя ничем не отличалась от глубины меню. Свет у линии земли даёт бойцам
  /// место, где они стоят, а затемнение по краям — стены вокруг.
  void _drawGround(Canvas canvas, Vector2 size, double groundY) {
    final glow = Rect.fromLTWH(0, groundY - size.y * 0.32, size.x,
        size.y * 0.32 + 10.0);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, glow.top),
          Offset(0, glow.bottom),
          const [Color(0x00000000), Color(0x22C7643F)],
        ),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, groundY + 2, size.x, 1.2),
      Paint()..color = const Color(0x33D9C8A9),
    );

    // Отражение на камне: полоса под линией земли, тусклее самой линии.
    canvas.drawRect(
      Rect.fromLTWH(0, groundY + 3.2, size.x, math.max(0.0, size.y - groundY)),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, groundY + 3.2),
          Offset(0, size.y),
          const [Color(0x18D9C8A9), Color(0x00000000)],
        ),
    );

    for (final side in const [true, false]) {
      final w = size.x * 0.16;
      canvas.drawRect(
        Rect.fromLTWH(side ? 0 : size.x - w, 0, w, size.y),
        Paint()
          ..shader = Gradient.linear(
            Offset(side ? 0 : size.x, 0),
            Offset(side ? w : size.x - w, 0),
            const [Color(0x66000000), Color(0x00000000)],
          ),
      );
    }
  }

  /// Кольцо применённой способности: расходится и гаснет.
  void _castRing(Canvas canvas, Offset center, double height) {
    final t = _anims.cast;
    for (var ring = 0; ring < 2; ring++) {
      final phase = (t - ring * 0.18).clamp(0.0, 1.0);
      if (phase <= 0.0) continue;
      canvas.drawCircle(
        center,
        height * (0.30 + 0.60 * (1.0 - phase)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + 2.5 * phase
          ..color = const Color(0xFF7FB069).withValues(alpha: 0.40 * phase),
      );
    }
  }

  /// Превращает случившееся в бою в искры, цифры и толчки камеры.
  ///
  /// Здесь же и только здесь бой становится зрелищем. Правило одно: эффект
  /// рождается из УЖЕ случившегося события и ни на что не влияет — иначе бой
  /// шёл бы иначе, когда на него смотрят.
  void _spawnEffects(
    WaveLayout layout,
    List<double> enemies,
    List<String> ids,
    double heroX,
    double heroHeight,
    double groundY,
  ) {
    // Вход босса: волна началась, и в ней тот, кто крупнее всех.
    if (view.bossWave && !_wasBoss) {
      _vfx.kick(7.0);
      _bossBanner = 1.8;
    }
    _wasBoss = view.bossWave;

    if (_pending.isEmpty) return;

    Offset spot(int index) {
      if (index < 0 || index >= layout.positions.length) {
        return Offset(heroX, groundY - heroHeight * 0.55);
      }
      final lift = index < layout.lifts.length ? layout.lifts[index] : 0.0;
      // Середина груди, а не ноги: удар приходится в фигуру, и искры от ног
      // читаются как пыль из-под сапог.
      return Offset(layout.positions[index], groundY - lift - layout.height * 0.55);
    }

    for (final beat in _pending) {
      switch (beat.kind) {
        case BeatKind.waveStarted:
          _vfx.clear();
        case BeatKind.enemyHit:
          final at = spot(beat.index);
          _vfx.hit(at, beat.type, crit: beat.crit, scale: layout.height);
          _vfx.number(at, beat.amount, crit: beat.crit, type: beat.type);
          // Трясёт только крит. Тряска на каждом ударе — это не вес, а
          // дрожащий экран: удары идут по нескольку раз в секунду.
          if (beat.crit) _vfx.kick(3.5);
        case BeatKind.enemyDied:
          final each = silhouetteFor(
              beat.index < ids.length && beat.index >= 0 ? ids[beat.index] : '');
          _vfx.death(spot(beat.index), each.accent, scale: layout.height);
        case BeatKind.heroHurt:
          final at = Offset(heroX, groundY - heroHeight * 0.55);
          _vfx.hit(at, beat.type, scale: heroHeight);
          _vfx.number(at, beat.amount, type: beat.type);
          _vfx.kick(2.0);
        case BeatKind.heroDied:
          _vfx.kick(10.0);
        case BeatKind.bossWindup:
          _skillName = beat.name;
          _skillType = beat.type;
          _skillBanner = 1.6;
        case BeatKind.bossSkill:
          // Удар умения — самый тяжёлый момент боя, тяжелее крита.
          _vfx.kick(8.0);
          _vfx.hit(Offset(heroX, groundY - heroHeight * 0.55), beat.type,
              crit: true, scale: heroHeight * 1.4);
          if (_skillBanner <= 0.0) {
            // Умение без замаха (ярость) объявляется в момент применения.
            _skillName = beat.name;
            _skillType = beat.type;
            _skillBanner = 1.6;
          }
        case BeatKind.heroSwing:
        case BeatKind.heroCast:
          break;
      }
    }
    _pending.clear();
  }

  /// Дуга удара: широкий мазок перед фигурой, гаснущий вместе с выпадом.
  void _slash(Canvas canvas, Offset feet, double height, double lunge) {
    final power = ((lunge - 0.45) / 0.55).clamp(0.0, 1.0);
    final center = Offset(feet.dx + height * 0.22, feet.dy - height * 0.52);
    canvas.drawArc(
      Rect.fromCenter(
          center: center, width: height * 0.85, height: height * 1.05),
      -1.05,
      2.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = height * 0.05 * power
        ..color = const Color(0xFFFFF3DC).withValues(alpha: 0.5 * power),
    );
  }

  /// Свечение боссовой фигуры: дышит, а не мигает.
  void _aura(Canvas canvas, Offset center, double height, Color color) {
    final pulse = 0.5 + 0.5 * math.sin(_time * 2.4);
    canvas.drawCircle(
      center,
      height * (0.62 + 0.05 * pulse),
      Paint()
        ..shader = Gradient.radial(center, height * (0.62 + 0.05 * pulse), [
          color.withValues(alpha: 0.16 + 0.06 * pulse),
          color.withValues(alpha: 0.0),
        ]),
    );
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
      Paint()..color = const Color(0x33000000).withValues(alpha: 0.20 * alpha),
    );

    canvas.save();

    if (falling > 0.0) {
      canvas.translate(feet.dx, feet.dy);
      canvas.rotate(falling * 1.25);
      canvas.translate(-feet.dx, -feet.dy);
    }


    // Сжатие от удара: фигуру приминает к земле и раздаёт вширь. Объём
    // сохраняется — иначе она не приминается, а просто становится меньше.
    if (anim.squash > 0.0) {
      final k = anim.squash * 0.12;
      canvas.translate(feet.dx, feet.dy);
      canvas.scale(1.0 + k, 1.0 - k);
      canvas.translate(-feet.dx, -feet.dy);
    }

    // Объём тремя проходами одной и той же фигуры.
    //
    // Силуэт — это плоская заливка, и никакой формой его не сделать объёмным.
    // Но глазу хватает края: тёмная копия, сдвинутая вниз-вправо, читается
    // как собственная тень, светлая копия вверх-влево — как свет, падающий
    // оттуда же, откуда светит вся сцена. Дороже ровно на два прохода и
    // работает сразу на всех двадцати фигурах, не трогая ни одной из них.
    final depth = height * 0.014;
    look.draw(Sketch(
      canvas: canvas,
      feet: feet.translate(depth, depth * 0.35),
      height: height,
      t: _time,
      body: const Color(0xFF0C0908),
      accent: const Color(0xFF0C0908),
      alpha: 0.55 * alpha,
    ));
    look.draw(Sketch(
      canvas: canvas,
      feet: feet.translate(-depth * 0.7, -depth * 0.7),
      height: height,
      t: _time,
      body: _lighten(look.body, 0.45),
      accent: _lighten(look.accent, 0.35),
      alpha: alpha,
    ));

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
      // Цвет вспышки — цвет стихии. Одна белая вспышка на все пять стихий
      // означала бы, что игрок, собравший сборку вокруг Холода, не видит в
      // бою никакой разницы с физическим ударом.
      final tint = lookForDamage(anim.flashType).core;
      look.draw(Sketch(
        canvas: canvas,
        feet: feet,
        height: height,
        t: _time,
        body: tint,
        accent: tint,
        alpha: 0.55 * anim.flash,
      ));
    }

    canvas.restore();
  }

  /// Цвет, подтянутый к белому. Нужен обводке света: у каждой фигуры свой
  /// цвет, и общий белый край превратил бы их всех в фольгу.
  static Color _lighten(Color c, double k) => Color.fromARGB(
        (c.a * 255).round(),
        (c.r * 255 + (255 - c.r * 255) * k).round(),
        (c.g * 255 + (255 - c.g * 255) * k).round(),
        (c.b * 255 + (255 - c.b * 255) * k).round(),
      );

  void _bar(
    Canvas canvas,
    double centerX,
    double y,
    double width,
    double fraction,
    Paint fill,
    double fieldWidth, {
    double height = 6.0,
  }) {
    // Полоска не выходит за край поля: у героя она шире его фигуры, а сам он
    // стоит близко к левому краю — и полоска обрезалась экраном.
    final half = width / 2;
    final x = centerX.clamp(
      math.min(half + 4.0, fieldWidth / 2),
      math.max(fieldWidth - half - 4.0, fieldWidth / 2),
    );
    final rect = Rect.fromLTWH(x - half, y, width, height);
    final radius = Radius.circular(height / 2);
    // Подложка шире на точку со всех сторон: полоска стоит на тёмной плашке
    // и не теряется на светлом разломе позади.
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.5), radius), _barBack);
    final filled = rect.width * fraction.clamp(0.0, 1.0);
    if (filled > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, rect.top, filled, rect.height), radius),
        fill,
      );
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.5), radius), _barEdge);
  }
}


/// Стены бездны позади бойцов.
///
/// До них сцена была двумя фигурами в черноте, и десятый этаж выглядел ровно
/// как шестидесятый. Требование к фону ровно одно и оно не про красоту: он
/// обязан оставаться ФОНОМ. Поэтому здесь нет ни одной яркой точки — только
/// силуэты темнее и светлее общей темноты, — и ни одного движения, кроме
/// сдвига при тряске.
///
/// Столбы считаются один раз на размер экрана, а не каждый кадр: это десяток
/// прямоугольников, но кадр в бою и без них занят.
class _Backdrop {
  final List<_Column> _far = [];
  final List<_Column> _near = [];
  double _builtFor = -1.0;

  void _build(double width) {
    _far.clear();
    _near.clear();
    // Свой генератор с постоянным зерном: стены не должны перестраиваться
    // при каждом повороте телефона — иначе бездна «моргает» другой пещерой.
    final rng = math.Random(4242);

    for (var i = 0; i < 7; i++) {
      _far.add(_Column(
        x: width * (0.02 + 0.16 * i) + rng.nextDouble() * width * 0.05,
        width: width * (0.05 + rng.nextDouble() * 0.06),
        height: 0.55 + rng.nextDouble() * 0.35,
      ));
    }
    for (var i = 0; i < 4; i++) {
      _near.add(_Column(
        x: width * (0.08 + 0.28 * i) + rng.nextDouble() * width * 0.07,
        width: width * (0.08 + rng.nextDouble() * 0.07),
        height: 0.30 + rng.nextDouble() * 0.28,
      ));
    }
  }

  void render(Canvas canvas, Vector2 size, double groundY, double time,
      Offset shake) {
    if (_builtFor != size.x) {
      _build(size.x);
      _builtFor = size.x;
    }

    // Разлом в глубине: единственный источник света в кадре, и он же
    // объясняет, откуда на фигурах свет.
    final riftX = size.x * 0.62;
    final top = math.max(0.0, groundY - size.y * 0.78);
    canvas.drawRect(
      Rect.fromLTRB(riftX - size.x * 0.14, top, riftX + size.x * 0.14, groundY),
      Paint()
        ..shader = Gradient.radial(
          Offset(riftX, groundY - size.y * 0.30),
          size.x * 0.30,
          [
            // Дышит еле заметно: неподвижный свет читается как картинка,
            // а слишком живой — как мигающая лампа.
            Color(0x1AC7643F)
                .withValues(alpha: 0.055 + 0.012 * math.sin(time * 0.8)),
            const Color(0x00000000),
          ],
        ),
    );

    // Дальний слой почти не смещается тряской, ближний — заметно: разница и
    // читается как расстояние.
    _columns(canvas, _far, size, groundY, const Color(0xFF1C1513),
        shake * -0.15);
    _columns(canvas, _near, size, groundY, const Color(0xFF231A17),
        shake * -0.45);
  }

  void _columns(Canvas canvas, List<_Column> columns, Vector2 size,
      double groundY, Color color, Offset offset) {
    final paint = Paint()..color = color;
    for (final c in columns) {
      final h = size.y * c.height;
      final rect = Rect.fromLTWH(
        c.x + offset.dx,
        groundY - h + offset.dy,
        c.width,
        h,
      );
      // Верх столба скруглён: прямоугольник в прямоугольном кадре читается
      // как элемент интерфейса, а не как камень.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(c.width * 0.5),
          topRight: Radius.circular(c.width * 0.5),
        ),
        paint,
      );
    }
  }
}

class _Column {
  const _Column({required this.x, required this.width, required this.height});

  final double x;
  final double width;

  /// Рост в долях высоты поля.
  final double height;
}
