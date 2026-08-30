import 'dart:math' as math;
import 'dart:ui';

import 'package:rift/core/model/equipment.dart';

/// Как выглядят обитатели бездны.
///
/// Силуэты нарисованы кодом, а не загружены картинками. Причина не в лени:
/// спрайтовый атлас — это лицензии, вес пакета и вторая копия бестиария,
/// которая расходится с `enemies.json` при первом же добавлении моба.
/// Здесь связь обратная — силуэт ищется по `id` из контента, и тест падает,
/// если у нового моба своего силуэта нет.
///
/// Рисование идёт в единичных координатах: `y = 0` — под ногами, `y = 1` —
/// макушка, `x` от `-0.5` до `0.5`. Значит одна и та же фигура одинаково
/// выглядит и мелким мобом в пачке из пяти, и боссом во весь экран.
class Sketch {
  Sketch({
    required this.canvas,
    required this.feet,
    required this.height,
    required this.t,
    required Color body,
    required Color accent,
    double alpha = 1.0,
  })  : _body = Paint()..color = body.withValues(alpha: body.a * alpha),
        _accent = Paint()..color = accent.withValues(alpha: accent.a * alpha);

  final Canvas canvas;

  /// Точка опоры: середина ступней на линии земли.
  final Offset feet;

  /// Высота фигуры в пикселях — единица измерения всего остального.
  final double height;

  /// Время сцены в секундах. По нему живут пламя, щупальца и прочее, что
  /// обязано шевелиться, чтобы бой не выглядел паузой.
  final double t;

  final Paint _body;
  final Paint _accent;

  Paint _paint(bool accent) => accent ? _accent : _body;

  Offset at(double x, double y) =>
      Offset(feet.dx + x * height, feet.dy - y * height);

  void circle(double x, double y, double r, {bool accent = false}) =>
      canvas.drawCircle(at(x, y), r * height, _paint(accent));

  void oval(double x, double y, double w, double h, {bool accent = false}) =>
      canvas.drawOval(
        Rect.fromCenter(
            center: at(x, y), width: w * height, height: h * height),
        _paint(accent),
      );

  void poly(List<Offset> points, {bool accent = false}) {
    if (points.length < 3) return;
    final first = at(points.first.dx, points.first.dy);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = at(p.dx, p.dy);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path..close(), _paint(accent));
  }

  /// Конечность, хвост, щупальце — линия с круглыми торцами. Дешевле любого
  /// многоугольника и читается как объём, а не как палка.
  void limb(double x1, double y1, double x2, double y2, double w,
      {bool accent = false}) {
    canvas.drawLine(
      at(x1, y1),
      at(x2, y2),
      _paint(accent)
        ..strokeWidth = w * height
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Кольцо: внешний круг с вырезанным нутром. Нужно там, где силуэт — это
  /// пасть, а не тело.
  void ring(double x, double y, double outer, double inner,
      {bool accent = false}) {
    final c = at(x, y);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: outer * height))
        ..addOval(Rect.fromCircle(center: c, radius: inner * height)),
      _paint(accent),
    );
  }
}

/// Силуэт: чем рисовать и насколько он широк относительно своей высоты.
class Silhouette {
  const Silhouette({
    required this.body,
    required this.accent,
    required this.draw,
    this.aspect = 0.8,
  });

  final Color body;
  final Color accent;

  /// Ширина в долях высоты. По ней сцена расставляет волну: падальщик занимает
  /// больше места вбок, чем закованный в броню столб, и налезать они не должны.
  final double aspect;

  final void Function(Sketch s) draw;

  /// Мёртвый вариант: та же фигура, погасшая. Отдельная поза не нужна —
  /// важно, что цель больше не участвует в бою, а не как именно она упала.
  Silhouette get dead => Silhouette(
        body: const Color(0xFF2A2422),
        accent: const Color(0xFF221D1B),
        draw: draw,
        aspect: aspect,
      );
}

/// Силуэт по `id` из `enemies.json`. Неизвестный моб получает общую фигуру:
/// контент добавляется данными, и клиент не имеет права падать из-за строки,
/// которой он не знает.
Silhouette silhouetteFor(String enemyId) => _book[enemyId] ?? unknownSilhouette;

/// Все известные клиенту `id`. Тест сверяет этот набор с контентом.
Iterable<String> get knownSilhouetteIds => _book.keys;

const _book = <String, Silhouette>{
  'scavenger': Silhouette(
      body: Color(0xFF8C6A4A),
      accent: Color(0xFFE0C08A),
      aspect: 1.0,
      draw: _scavenger),
  'bonebreaker': Silhouette(
      body: Color(0xFF9A8B72),
      accent: Color(0xFFD9C8A9),
      aspect: 0.92,
      draw: _bonebreaker),
  'ash_eater': Silhouette(
      body: Color(0xFFC7643F),
      accent: Color(0xFFFFC46B),
      aspect: 0.48,
      draw: _ashEater),
  'frost_warden': Silhouette(
      body: Color(0xFF5E7E92),
      accent: Color(0xFFAEE0F0),
      aspect: 0.82,
      draw: _frostWarden),
  'void_whisperer': Silhouette(
      body: Color(0xFF5B4A78),
      accent: Color(0xFFB9A0E8),
      aspect: 0.68,
      draw: _voidWhisperer),
  'blood_leech': Silhouette(
      body: Color(0xFF8E3A46),
      accent: Color(0xFFE0707F),
      aspect: 0.85,
      draw: _bloodLeech),
  'ash_lord': Silhouette(
      body: Color(0xFFB4532F),
      accent: Color(0xFFFFD08A),
      aspect: 0.85,
      draw: _ashLord),
  'void_devourer': Silhouette(
      body: Color(0xFF4A3B6B),
      accent: Color(0xFFC7A6FF),
      aspect: 1.05,
      draw: _voidDevourer),
  'stone_fist': Silhouette(
      body: Color(0xFF7C7468),
      accent: Color(0xFFCFC4B0),
      aspect: 1.05,
      draw: _stoneFist),
  'rot_howler': Silhouette(
      body: Color(0xFF6B7A4A),
      accent: Color(0xFFBBD08A),
      aspect: 1.17,
      draw: _rotHowler),
  'grave_swarm': Silhouette(
      body: Color(0xFF6E6154),
      accent: Color(0xFFC2B39A),
      aspect: 0.9,
      draw: _graveSwarm),
  'cinderling': Silhouette(
      body: Color(0xFFD1712F),
      accent: Color(0xFFFFE08A),
      aspect: 0.7,
      draw: _cinderling),
  'forge_smith': Silhouette(
      body: Color(0xFF9A4A2E),
      accent: Color(0xFFFFB25B),
      aspect: 0.95,
      draw: _forgeSmith),
  'rime_horror': Silhouette(
      body: Color(0xFF6E8FA6),
      accent: Color(0xFFCDEBFA),
      aspect: 0.9,
      draw: _rimeHorror),
  'frost_maw': Silhouette(
      body: Color(0xFF4E6B80),
      accent: Color(0xFFB6DCEF),
      aspect: 0.88,
      draw: _frostMaw),
  'sparkling': Silhouette(
      body: Color(0xFFB89A2E),
      accent: Color(0xFFFFF07A),
      aspect: 0.6,
      draw: _sparkling),
  'storm_warden': Silhouette(
      body: Color(0xFF7D7A3E),
      accent: Color(0xFFFFF3A0),
      aspect: 0.98,
      draw: _stormWarden),
  'arc_leech': Silhouette(
      body: Color(0xFF8A8340),
      accent: Color(0xFFFFEE8C),
      aspect: 0.8,
      draw: _arcLeech),
  'void_reaper': Silhouette(
      body: Color(0xFF4E3F70),
      accent: Color(0xFFC0A4F0),
      aspect: 0.78,
      draw: _voidReaper),
  'mana_eater': Silhouette(
      body: Color(0xFF574670),
      accent: Color(0xFFB9A0E8),
      aspect: 0.84,
      draw: _manaEater),
  'rift_shade': Silhouette(
      body: Color(0xFF433764),
      accent: Color(0xFFA98CE0),
      aspect: 0.66,
      draw: _riftShade),
  'storm_sovereign': Silhouette(
      body: Color(0xFF9C8F3A),
      accent: Color(0xFFFFF6B0),
      aspect: 1.2,
      draw: _stormSovereign),
  'frost_patriarch': Silhouette(
      body: Color(0xFF4A6B84),
      accent: Color(0xFFCFEBFF),
      aspect: 1.0,
      draw: _frostPatriarch),
};

const unknownSilhouette = Silhouette(
    body: Color(0xFF7A6A5C),
    accent: Color(0xFFD9C8A9),
    aspect: 0.4,
    draw: _humanoid);

// --- Мобы --------------------------------------------------------------------
//
// Все смотрят влево: герой стоит слева, и фигура, отвернувшаяся от него,
// читается как декорация, а не как противник.

/// Падальщик: низкий, горбатый, вперёд челюстью. Мясо волны — узнаётся по
/// тому, что их пятеро и они мельче всех.
void _scavenger(Sketch s) {
  s.limb(-0.06, 0.24, -0.16, 0.0, 0.055);
  s.limb(0.06, 0.26, 0.02, 0.0, 0.055);
  s.limb(0.20, 0.28, 0.26, 0.0, 0.055);
  s.limb(0.30, 0.44, 0.48, 0.58, 0.035);
  s.oval(0.06, 0.40, 0.56, 0.40);

  // Горб из шипов: по нему падальщик отличается от любой другой мелочи даже
  // тогда, когда фигура размером с ноготь.
  for (var i = 0; i < 3; i++) {
    final x = -0.06 + i * 0.14;
    s.poly([
      Offset(x - 0.05, 0.56),
      Offset(x, 0.68 - i * 0.03),
      Offset(x + 0.05, 0.56),
    ]);
  }

  s.circle(-0.22, 0.44, 0.13);
  s.poly(const [Offset(-0.28, 0.42), Offset(-0.50, 0.34), Offset(-0.26, 0.34)],
      accent: true);
  s.circle(-0.24, 0.50, 0.028, accent: true);
}

/// Костолом: плечи шире всего остального и дубина. Медленный тяжёлый удар
/// должен быть виден до того, как он случится.
void _bonebreaker(Sketch s) {
  s.limb(-0.10, 0.34, -0.14, 0.0, 0.10);
  s.limb(0.12, 0.34, 0.16, 0.0, 0.10);
  s.poly(const [
    Offset(-0.34, 0.80),
    Offset(0.34, 0.80),
    Offset(0.20, 0.32),
    Offset(-0.20, 0.32),
  ]);
  s.circle(-0.02, 0.90, 0.10);
  s.limb(-0.30, 0.74, -0.44, 0.42, 0.07);
  s.limb(-0.44, 0.42, -0.50, 0.24, 0.14, accent: true);
}

/// Пеплоед: тела нет, есть пламя. Единственный, кто заметно шевелится в покое,
/// — по нему видно, что сцена живая, даже когда никто не бьёт.
void _ashEater(Sketch s) {
  final f = math.sin(s.t * 3.4) * 0.05;
  s.poly([
    const Offset(-0.22, 0.0),
    const Offset(0.22, 0.0),
    Offset(0.12, 0.44 + f),
    Offset(0.20 + f, 0.78),
    const Offset(0.0, 0.62),
    Offset(-0.14 - f, 0.86 + f),
    const Offset(-0.10, 0.40),
  ]);
  s.circle(0.02, 0.34, 0.10, accent: true);
  s.circle(0.10 + f, 0.94, 0.035, accent: true);
  s.circle(-0.16, 1.02 - f, 0.025, accent: true);
}

/// Ледяной страж: столб брони и щит. Широкий, угловатый, неподвижный —
/// силуэт обещает броню раньше, чем игрок увидит цифры.
void _frostWarden(Sketch s) {
  s.poly(const [
    Offset(-0.20, 0.0),
    Offset(0.20, 0.0),
    Offset(0.26, 0.70),
    Offset(0.0, 0.84),
    Offset(-0.26, 0.70),
  ]);
  s.poly(const [
    Offset(-0.14, 0.84),
    Offset(0.14, 0.84),
    Offset(0.0, 1.0),
  ]);
  s.poly(const [
    Offset(-0.26, 0.66),
    Offset(-0.44, 0.52),
    Offset(-0.42, 0.20),
    Offset(-0.24, 0.14),
  ], accent: true);
  s.limb(0.20, 0.72, 0.34, 0.96, 0.05, accent: true);
  s.circle(0.0, 0.88, 0.035, accent: true);
}

/// Пустотный шептун: капюшон без ног. Висит — поэтому у него нет опоры,
/// и это единственная фигура, которая не касается земли.
void _voidWhisperer(Sketch s) {
  final drift = math.sin(s.t * 1.6) * 0.02;
  double y(double v) => v + drift;

  // Рваный подол вместо ног. Ровный низ сделал бы фигуру стоящей, а шептун
  // висит — и это единственное, чем он отличается силуэтом от любого мага.
  s.poly([
    Offset(-0.26, y(0.20)),
    Offset(-0.17, y(0.06)),
    Offset(-0.08, y(0.22)),
    Offset(0.02, y(0.02)),
    Offset(0.12, y(0.22)),
    Offset(0.22, y(0.08)),
    Offset(0.26, y(0.24)),
    Offset(0.18, y(0.62)),
    Offset(-0.18, y(0.62)),
  ]);

  // Капюшон: круг с острым верхом. Круг отдельно от плеч — иначе всё
  // сливается в один вытянутый клин.
  s.circle(0.0, y(0.72), 0.15);
  s.poly([
    Offset(-0.13, y(0.78)),
    Offset(-0.04, y(1.0)),
    Offset(0.10, y(0.80)),
  ]);
  s.circle(-0.05, y(0.72), 0.055, accent: true);

  s.limb(-0.16, y(0.58), -0.34, y(0.40), 0.045);
  s.circle(-0.36, y(0.38), 0.045, accent: true);
}

/// Кровавая пиявка: сегментированная дуга. Чем дольше бой, тем она опаснее
/// (`rampUp`), и вытянутая вперёд голова показывает, куда она тянется.
void _bloodLeech(Sketch s) {
  const segments = 7;
  Offset seg(int i) {
    final k = i / (segments - 1);
    return Offset(0.34 - k * 0.62, 0.09 + math.sin(k * math.pi) * 0.44);
  }

  // Сегменты соединены телом: отдельные круги читались пузырями, а не червём.
  for (var i = 1; i < segments; i++) {
    final a = seg(i - 1);
    final b = seg(i);
    s.limb(a.dx, a.dy, b.dx, b.dy, 0.15 - i * 0.008);
  }
  for (var i = 0; i < segments; i++) {
    final p = seg(i);
    s.circle(p.dx, p.dy, 0.095 - i * 0.006);
  }

  final head = seg(segments - 1);
  s.ring(head.dx, head.dy, 0.085, 0.042, accent: true);
}

// --- Боссы -------------------------------------------------------------------

/// Владыка Пепла: рост, корона и плащ. Босс обязан быть узнаваем силуэтом
/// с той же дистанции, что и обычная пачка.
void _ashLord(Sketch s) {
  // Плащ — два крыла, отброшенных от узкого тела. Широкое полотно сливалось
  // с торсом в одно оранжевое пятно, и от босса оставалась только корона.
  s.poly(const [
    Offset(0.11, 0.76),
    Offset(0.44, 0.36),
    Offset(0.34, 0.06),
    Offset(0.20, 0.34),
  ]);
  s.poly(const [
    Offset(-0.11, 0.76),
    Offset(-0.40, 0.38),
    Offset(-0.30, 0.08),
    Offset(-0.19, 0.36),
  ]);

  // Тело — узкая колонна: рост босса читается только на контрасте с плащом.
  s.poly(const [
    Offset(-0.09, 0.0),
    Offset(0.09, 0.0),
    Offset(0.12, 0.72),
    Offset(-0.12, 0.72),
  ]);
  s.limb(0.0, 0.72, 0.0, 0.80, 0.07);
  s.circle(0.0, 0.88, 0.105);

  // Наплечники и пояс — акцентом: доспех, а не балахон.
  s.oval(-0.15, 0.72, 0.13, 0.09, accent: true);
  s.oval(0.15, 0.72, 0.13, 0.09, accent: true);
  s.limb(-0.10, 0.38, 0.10, 0.38, 0.045, accent: true);

  for (var i = -1; i <= 1; i++) {
    s.poly([
      Offset(i * 0.075 - 0.032, 0.95),
      Offset(i * 0.075, 1.06 + (i == 0 ? 0.05 : 0.0)),
      Offset(i * 0.075 + 0.032, 0.95),
    ], accent: true);
  }

  s.limb(-0.13, 0.62, -0.28, 0.40, 0.055);
  final ember = math.sin(s.t * 2.0) * 0.04;
  s.circle(-0.31, 0.38 + ember, 0.06, accent: true);
  s.circle(0.30, 0.92 + ember, 0.028, accent: true);
}

/// Пустотный Пожиратель: пасть, а не тело. Щупальца шевелятся — они и есть
/// его силуэт, кольцо само по себе слишком спокойно для того, кто ест бафы.
void _voidDevourer(Sketch s) {
  for (var i = 0; i < 5; i++) {
    final k = i / 4.0;
    final sway = math.sin(s.t * 1.4 + i) * 0.06;
    s.limb(-0.30 + k * 0.60, 0.34, -0.44 + k * 0.88 + sway, 0.0, 0.05);
  }
  s.ring(0.0, 0.56, 0.34, 0.17);
  for (var i = 0; i < 8; i++) {
    final a = i / 8.0 * math.pi * 2;
    s.poly([
      Offset(math.cos(a) * 0.17, 0.56 + math.sin(a) * 0.17),
      Offset(math.cos(a + 0.20) * 0.17, 0.56 + math.sin(a + 0.20) * 0.17),
      Offset(math.cos(a + 0.10) * 0.07, 0.56 + math.sin(a + 0.10) * 0.07),
    ], accent: true);
  }
}

// --- Герой -------------------------------------------------------------------

/// Чем вооружён наёмник. Не украшение: игрок собирает билд руками и должен
/// видеть в бою последствие своего выбора, а не безымянную фигурку.
enum HeroWeapon { unarmed, oneHanded, twoHanded, shielded }

/// Что показать по снаряжению. Правило то же, по которому живёт бой:
/// двуручник занимает обе руки, и «щит» — это любой предмет в левой руке,
/// а не отдельный вид снаряжения.
HeroWeapon heroWeaponOf(Equipment gear) {
  final weapon = gear.at(0);
  if (weapon == null) return HeroWeapon.unarmed;
  if (weapon.twoHanded) return HeroWeapon.twoHanded;
  return gear.at(1) == null ? HeroWeapon.oneHanded : HeroWeapon.shielded;
}

Silhouette heroSilhouette(HeroWeapon weapon) => Silhouette(
      body: const Color(0xFFD9C8A9),
      accent: const Color(0xFF7FB069),
      aspect: 0.85,
      draw: (s) => _hero(s, weapon),
    );

/// Герой смотрит вправо — туда, откуда идёт волна.
void _hero(Sketch s, HeroWeapon weapon) {
  s.poly(const [
    Offset(-0.10, 0.82),
    Offset(-0.34, 0.24),
    Offset(-0.16, 0.06),
    Offset(-0.06, 0.60),
  ]);
  s.limb(-0.06, 0.34, -0.12, 0.0, 0.07);
  s.limb(0.08, 0.34, 0.14, 0.0, 0.07);
  s.poly(const [
    Offset(-0.16, 0.78),
    Offset(0.16, 0.78),
    Offset(0.11, 0.32),
    Offset(-0.11, 0.32),
  ]);
  s.circle(0.02, 0.88, 0.095);

  switch (weapon) {
    case HeroWeapon.unarmed:
      s.limb(0.14, 0.70, 0.26, 0.50, 0.06);
    case HeroWeapon.oneHanded:
      s.limb(0.14, 0.66, 0.26, 0.52, 0.05);
      s.limb(0.26, 0.48, 0.34, 0.92, 0.045, accent: true);
    case HeroWeapon.twoHanded:
      // Двуручник занимает оба слота — и в силуэте занимает всю фигуру.
      s.limb(-0.26, 0.10, 0.34, 1.02, 0.055, accent: true);
      s.limb(-0.06, 0.44, 0.10, 0.62, 0.05);
    case HeroWeapon.shielded:
      s.limb(0.14, 0.66, 0.26, 0.52, 0.05);
      s.limb(0.26, 0.48, 0.32, 0.86, 0.04, accent: true);
      s.oval(-0.18, 0.56, 0.20, 0.34, accent: true);
  }
}

/// Общая фигура для того, чего клиент не знает. Не заглушка ради заглушки:
/// новый моб в JSON должен появиться в бою, а не уронить экран.
void _humanoid(Sketch s) {
  s.limb(-0.08, 0.32, -0.12, 0.0, 0.07);
  s.limb(0.10, 0.32, 0.14, 0.0, 0.07);
  s.oval(0.0, 0.54, 0.34, 0.50);
  s.circle(0.0, 0.86, 0.11);
}

// --- Новые мобы ---------------------------------------------------------------

/// Каменный кулак: одна огромная рука. Броня растёт по ходу боя, и узнаётся он
/// именно по несоразмерности — бить его чем попало бесполезно.
void _stoneFist(Sketch s) {
  s.limb(-0.10, 0.30, -0.14, 0.0, 0.11);
  s.limb(0.14, 0.30, 0.18, 0.0, 0.11);
  s.oval(0.06, 0.52, 0.40, 0.46);
  s.circle(0.10, 0.86, 0.11);
  s.oval(-0.34, 0.44, 0.44, 0.44, accent: true);
  s.limb(-0.10, 0.56, -0.26, 0.48, 0.10);
}

/// Гнилой ревун: разинутая пасть и волны от неё. Пока он жив, пачка не
/// кончается, и это должно быть видно раньше, чем игрок поймёт это по цифрам.
void _rotHowler(Sketch s) {
  final f = math.sin(s.t * 2.6) * 0.04;
  s.limb(-0.06, 0.26, -0.12, 0.0, 0.07);
  s.limb(0.10, 0.26, 0.16, 0.0, 0.07);
  s.oval(0.04, 0.44, 0.34, 0.44);
  s.circle(-0.16, 0.74, 0.13);
  s.poly([
    const Offset(-0.26, 0.78),
    Offset(-0.46 - f, 0.72),
    Offset(-0.46 - f, 0.62),
    const Offset(-0.26, 0.68),
  ], accent: true);
  for (var i = 0; i < 3; i++) {
    s.circle(-0.52 - i * 0.10 - f, 0.70, 0.03 + i * 0.01, accent: true);
  }
}

/// Могильный рой: не фигура, а горсть фигурок. Их всегда много.
void _graveSwarm(Sketch s) {
  for (var i = 0; i < 4; i++) {
    final x = -0.28 + i * 0.19;
    final y = 0.10 + (i.isEven ? 0.0 : 0.12);
    s.oval(x, y + 0.16, 0.20, 0.16);
    s.circle(x - 0.10, y + 0.22, 0.055);
    s.limb(x, y + 0.10, x - 0.02, y, 0.03);
  }
}

/// Головня: горящий шар на тонких ногах. Взрывается при смерти — фитиль сверху
/// виден до того, как это случится впервые.
void _cinderling(Sketch s) {
  final f = math.sin(s.t * 5.0) * 0.05;
  s.limb(-0.06, 0.18, -0.10, 0.0, 0.035);
  s.limb(0.08, 0.18, 0.12, 0.0, 0.035);
  s.circle(0.0, 0.38, 0.22);
  s.poly([
    const Offset(-0.05, 0.60),
    Offset(0.02 + f, 0.86 + f),
    const Offset(0.07, 0.60),
  ], accent: true);
  s.circle(-0.10, 0.42, 0.035, accent: true);
}

/// Пепельный кузнец: молот и наковальня вместо плеча. Затвердевает по ходу боя.
void _forgeSmith(Sketch s) {
  s.limb(-0.10, 0.30, -0.14, 0.0, 0.09);
  s.limb(0.12, 0.30, 0.16, 0.0, 0.09);
  s.oval(0.02, 0.52, 0.38, 0.44);
  s.circle(-0.06, 0.86, 0.10);
  s.limb(0.22, 0.62, 0.42, 0.78, 0.05);
  s.poly(const [
    Offset(0.34, 0.90),
    Offset(0.56, 0.90),
    Offset(0.56, 0.70),
    Offset(0.34, 0.70),
  ], accent: true);
}

/// Инеевая тварь: длинная, стелющаяся, в шипах инея. Замедляет — и сама
/// выглядит медленной.
void _rimeHorror(Sketch s) {
  s.limb(-0.16, 0.20, -0.24, 0.0, 0.05);
  s.limb(0.02, 0.20, 0.06, 0.0, 0.05);
  s.limb(0.20, 0.20, 0.28, 0.0, 0.05);
  s.oval(0.02, 0.36, 0.62, 0.30);
  s.circle(-0.30, 0.42, 0.11);
  for (var i = 0; i < 4; i++) {
    final x = -0.20 + i * 0.16;
    s.poly([
      Offset(x - 0.04, 0.50),
      Offset(x, 0.72 - (i.isEven ? 0.0 : 0.08)),
      Offset(x + 0.04, 0.50),
    ], accent: true);
  }
}

/// Морозная пасть: почти вся — челюсть. Разгоняется, и чем дольше бой, тем
/// шире она открыта.
void _frostMaw(Sketch s) {
  final f = math.sin(s.t * 2.0) * 0.05;
  s.limb(-0.08, 0.22, -0.14, 0.0, 0.07);
  s.limb(0.10, 0.22, 0.16, 0.0, 0.07);
  s.oval(0.10, 0.42, 0.40, 0.40);
  s.poly([
    const Offset(-0.10, 0.56),
    Offset(-0.52, 0.62 + f),
    Offset(-0.52, 0.34 - f),
  ], accent: true);
  for (var i = 0; i < 3; i++) {
    s.poly([
      Offset(-0.20 - i * 0.10, 0.56),
      Offset(-0.24 - i * 0.10, 0.46),
      Offset(-0.28 - i * 0.10, 0.56),
    ]);
  }
}

/// Искровик: мелкий, быстрый, весь из зигзагов. Их много, и бьют они молнией.
void _sparkling(Sketch s) {
  final f = math.sin(s.t * 6.0) * 0.03;
  s.poly([
    const Offset(-0.14, 0.0),
    Offset(0.02 + f, 0.30),
    const Offset(-0.06, 0.30),
    Offset(0.14 + f, 0.62),
    const Offset(0.0, 0.34),
    const Offset(0.08, 0.34),
  ], accent: true);
  s.circle(-0.04, 0.44, 0.10);
  s.circle(-0.10, 0.48, 0.025, accent: true);
}

/// Громовой страж: щит на всю фигуру. Отражает — и щит об этом говорит.
void _stormWarden(Sketch s) {
  s.limb(-0.08, 0.30, -0.12, 0.0, 0.09);
  s.limb(0.14, 0.30, 0.18, 0.0, 0.09);
  s.oval(0.10, 0.50, 0.34, 0.44);
  s.circle(0.04, 0.84, 0.10);
  s.poly(const [
    Offset(-0.14, 0.86),
    Offset(-0.40, 0.70),
    Offset(-0.40, 0.28),
    Offset(-0.14, 0.14),
  ], accent: true);
  s.poly(const [
    Offset(-0.30, 0.62),
    Offset(-0.20, 0.50),
    Offset(-0.28, 0.50),
    Offset(-0.18, 0.36),
  ]);
}

/// Разрядник: катушка вместо туловища и дуги от неё. Снимает ману.
void _arcLeech(Sketch s) {
  final f = math.sin(s.t * 4.4) * 0.04;
  s.limb(-0.06, 0.24, -0.12, 0.0, 0.05);
  s.limb(0.10, 0.24, 0.16, 0.0, 0.05);
  for (var i = 0; i < 3; i++) {
    s.oval(0.02, 0.34 + i * 0.16, 0.34 - i * 0.06, 0.12);
  }
  s.circle(-0.14, 0.78, 0.09);
  for (var i = 0; i < 3; i++) {
    s.circle(-0.30 - i * 0.09, 0.74 + f, 0.026, accent: true);
  }
}

/// Пустотный жнец: коса и капюшон. Срезает сопротивления.
void _voidReaper(Sketch s) {
  s.limb(-0.06, 0.24, -0.12, 0.0, 0.06);
  s.limb(0.10, 0.24, 0.16, 0.0, 0.06);
  s.poly(const [
    Offset(-0.22, 0.86),
    Offset(0.22, 0.86),
    Offset(0.14, 0.24),
    Offset(-0.14, 0.24),
  ]);
  s.circle(-0.02, 0.90, 0.10);
  s.limb(0.24, 0.30, 0.28, 0.88, 0.035);
  s.poly(const [
    Offset(0.28, 0.88),
    Offset(-0.02, 1.04),
    Offset(0.10, 0.84),
  ], accent: true);
}

/// Иссушитель: воронка вместо груди. Пьёт ману и лечится от нанесённого.
void _manaEater(Sketch s) {
  final f = math.sin(s.t * 3.0) * 0.03;
  s.limb(-0.08, 0.26, -0.14, 0.0, 0.06);
  s.limb(0.10, 0.26, 0.16, 0.0, 0.06);
  s.oval(0.02, 0.46, 0.38, 0.44);
  s.circle(-0.04, 0.86, 0.10);
  s.oval(-0.16, 0.50 + f, 0.22, 0.22, accent: true);
  s.circle(-0.34, 0.52, 0.04, accent: true);
  s.circle(-0.46, 0.54, 0.025, accent: true);
}

/// Расколотая тень: две половины, между ними разрыв. Отражает.
void _riftShade(Sketch s) {
  final f = math.sin(s.t * 2.2) * 0.03;
  s.poly([
    Offset(-0.24 - f, 0.0),
    const Offset(-0.06, 0.30),
    const Offset(-0.10, 0.86),
    Offset(-0.30 - f, 0.56),
  ]);
  s.poly([
    Offset(0.24 + f, 0.0),
    const Offset(0.06, 0.30),
    const Offset(0.10, 0.86),
    Offset(0.30 + f, 0.56),
  ]);
  s.circle(0.0, 0.62, 0.05, accent: true);
  s.circle(0.0, 0.40, 0.03, accent: true);
}

// --- Новые боссы --------------------------------------------------------------

/// Громовой Владыка: корона из разрядов, руки в стороны. Глушит ману.
void _stormSovereign(Sketch s) {
  final f = math.sin(s.t * 3.6) * 0.03;
  s.limb(-0.12, 0.32, -0.18, 0.0, 0.10);
  s.limb(0.16, 0.32, 0.22, 0.0, 0.10);
  s.poly(const [
    Offset(-0.30, 0.84),
    Offset(0.30, 0.84),
    Offset(0.18, 0.30),
    Offset(-0.18, 0.30),
  ]);
  s.circle(-0.02, 0.92, 0.12);
  s.limb(-0.28, 0.78, -0.52, 0.90, 0.05);
  s.limb(0.28, 0.78, 0.52, 0.90, 0.05);
  for (var i = 0; i < 4; i++) {
    final x = -0.18 + i * 0.12;
    s.poly([
      Offset(x - 0.03, 1.02),
      Offset(x + 0.02, 1.02 + f),
      Offset(x + 0.05, 1.02),
    ], accent: true);
  }
}

/// Ледяной Патриарх: широкий, в наростах льда, с посохом. Лечит свиту.
void _frostPatriarch(Sketch s) {
  final f = math.sin(s.t * 1.6) * 0.03;
  s.limb(-0.14, 0.26, -0.20, 0.04, 0.10);
  s.limb(0.18, 0.26, 0.24, 0.04, 0.10);
  s.poly(const [
    Offset(-0.34, 0.76),
    Offset(0.34, 0.76),
    Offset(0.20, 0.24),
    Offset(-0.20, 0.24),
  ]);
  s.circle(0.0, 0.86, 0.12);
  s.limb(0.30, 0.18, 0.34, 0.86, 0.04);
  s.circle(0.34, 0.90, 0.07, accent: true);
  for (var i = 0; i < 3; i++) {
    final x = -0.26 + i * 0.24;
    s.poly([
      Offset(x - 0.05, 0.76),
      Offset(x, 0.90 + f - i * 0.04),
      Offset(x + 0.05, 0.76),
    ], accent: true);
  }
}
