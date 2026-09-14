import 'dart:math' as math;
import 'dart:ui';

import 'package:rift/core/model/tags.dart';

/// Как выглядит стихия.
///
/// Один источник на вспышку, искры и цифру урона. Раздельные палитры разъехались
/// бы при первой же правке, и удар Холодом светился бы синим, а искры от него
/// летели бы белые — то есть игрок видел бы два разных удара вместо одного.
class ElementLook {
  const ElementLook(this.core, this.glow);

  /// Сердцевина вспышки — почти белая: в неё смотрит глаз.
  final Color core;

  /// Цвет искр и цифры. Он и опознаётся как «это была Молния».
  final Color glow;
}

/// Палитра стихий.
///
/// Физический удар нарочно бесцветный: он самый частый, и цветная вспышка на
/// каждом ударе оружия превратила бы бой в гирлянду, на фоне которой стихия
/// перестала бы что-либо значить.
ElementLook lookForDamage(DamageType type) => switch (type) {
      DamageType.physical =>
        const ElementLook(Color(0xFFFFF3DC), Color(0xFFE8D2A8)),
      DamageType.fire =>
        const ElementLook(Color(0xFFFFE9B0), Color(0xFFFF7A2F)),
      DamageType.cold =>
        const ElementLook(Color(0xFFE6FAFF), Color(0xFF6FC8E8)),
      DamageType.lightning =>
        const ElementLook(Color(0xFFFFFBDC), Color(0xFFFFD84A)),
      DamageType.voidType =>
        const ElementLook(Color(0xFFF0E4FF), Color(0xFFA66BFF)),
    };

/// Одна живая частица.
///
/// Обычный изменяемый объект, а не запись: частиц в кадре сотни, и создавать
/// новый объект на каждый тик значило бы отдать сборщику мусора самое горячее
/// место в цикле отрисовки. Отжившие не выбрасываются, а переиспользуются —
/// см. [Vfx._take].
class Particle {
  double x = 0.0;
  double y = 0.0;
  double vx = 0.0;
  double vy = 0.0;

  /// Сколько осталось жить и сколько было дано. Доля одного к другому — это
  /// и прозрачность, и размер: частица гаснет, а не исчезает.
  double life = 0.0;
  double span = 1.0;

  double size = 1.0;

  /// Тяга вниз. У искр она есть, у дыма и пепла — отрицательная: он всплывает.
  double gravity = 0.0;

  /// Трение: доля скорости, теряемая за секунду. Без него искры улетают за
  /// экран по прямой и читаются как дождь, а не как брызги от удара.
  double drag = 0.0;

  Color color = const Color(0xFFFFFFFF);

  bool get alive => life > 0.0;

  /// Доля прожитого: 1 — только что родилась, 0 — вот-вот исчезнет.
  double get fade => span <= 0.0 ? 0.0 : (life / span).clamp(0.0, 1.0);

  void tick(double dt) {
    if (life <= 0.0) return;
    life -= dt;
    vy += gravity * dt;
    final keep = math.max(0.0, 1.0 - drag * dt);
    vx *= keep;
    vy *= keep;
    x += vx * dt;
    y += vy * dt;
  }
}

/// Всплывающее число урона.
class DamageNumber {
  double x = 0.0;
  double y = 0.0;
  double life = 0.0;
  double span = 1.0;
  int value = 0;
  bool crit = false;
  Color color = const Color(0xFFFFFFFF);

  bool get alive => life > 0.0;
  double get fade => span <= 0.0 ? 0.0 : (life / span).clamp(0.0, 1.0);

  void tick(double dt) {
    if (life <= 0.0) return;
    life -= dt;
    // Всплывает замедляясь: число, ползущее равномерно, читается как
    // элемент интерфейса, а не как след удара.
    y -= (18.0 + 26.0 * fade) * dt;
  }
}

/// Вспышка в точке удара: самый короткий и самый заметный из эффектов.
///
/// Отдельно от искр, потому что отвечает за другое. Искры рассказывают, ЧЕМ
/// ударили, — они разлетаются и живут полсекунды. Вспышка сообщает, что удар
/// СОСТОЯЛСЯ, и живёт одно мгновение: глаз ловит именно её, а искры дочитывает
/// уже после.
class Impact {
  double x = 0.0;
  double y = 0.0;
  double radius = 0.0;
  double life = 0.0;
  double span = 1.0;
  bool ring = false;
  Color color = const Color(0xFFFFFFFF);

  bool get alive => life > 0.0;
  double get fade => span <= 0.0 ? 0.0 : (life / span).clamp(0.0, 1.0);

  void tick(double dt) {
    if (life > 0.0) life -= dt;
  }
}

/// Эффекты боя: искры, пепел, цифры урона и тряска камеры.
///
/// Отдельно от сцены по той же причине, по которой отдельно раскладка волны и
/// анимации фигур: рисование не возвращает чисел и не проверяется ничем, а это
/// состояние — возвращает. Тест спрашивает «гаснут ли частицы», «не растёт ли
/// список без конца», «затухает ли тряска», и ответы на это не зависят от того,
/// как оно выглядит.
///
/// Никакой связи с симуляцией здесь нет и быть не может: эффекты рождаются из
/// уже случившихся событий боя (`CombatFeed`) и ни на что не влияют. Иначе бой
/// шёл бы иначе, когда на него смотрят.
class Vfx {
  Vfx({int seed = 7}) : _rng = math.Random(seed);

  final math.Random _rng;

  final List<Particle> _particles = [];
  final List<DamageNumber> _numbers = [];
  final List<Impact> _impacts = [];

  /// Потолок частиц. Не украшение, а требование к телефону: бой идёт по
  /// десять минут, волна из пяти мобов бьёт по нескольку раз в секунду, и
  /// список без потолка растёт ровно до тех пор, пока кадр не начнёт
  /// заикаться. Лишнее не рождается — самое старое переиспользуется.
  static const maxParticles = 260;

  /// Цифр на экране заведомо меньше, но правило то же: в пачке из пяти каждый
  /// тик приносит пять чисел, и без потолка они превращаются в столб.
  static const maxNumbers = 18;

  /// Текущая амплитуда тряски в пикселях.
  double _shake = 0.0;

  /// Фаза тряски. Своё время, а не время сцены: тряска обязана затухать
  /// одинаково независимо от того, сколько игра уже идёт.
  double _shakeTime = 0.0;

  int get particleCount => _particles.where((p) => p.alive).length;
  int get impactCount => _impacts.where((i) => i.alive).length;
  int get numberCount => _numbers.where((n) => n.alive).length;
  double get shakeAmount => _shake;

  /// Свободная частица: сначала отжившая, потом новая, и только пока есть
  /// место. Дойдя до потолка, самая старая уступает место новой — иначе
  /// на плотном бою перестают появляться именно свежие удары, то есть ровно
  /// те, которые игрок сейчас и смотрит.
  Particle _take() {
    for (final p in _particles) {
      if (!p.alive) return p;
    }
    if (_particles.length < maxParticles) {
      final p = Particle();
      _particles.add(p);
      return p;
    }
    var oldest = _particles.first;
    for (final p in _particles) {
      if (p.fade < oldest.fade) oldest = p;
    }
    return oldest;
  }

  Impact _impact() {
    for (final i in _impacts) {
      if (!i.alive) return i;
    }
    if (_impacts.length < 12) {
      final i = Impact();
      _impacts.add(i);
      return i;
    }
    return _impacts.reduce((a, b) => a.fade < b.fade ? a : b);
  }

  double _spread(double amount) => (_rng.nextDouble() * 2.0 - 1.0) * amount;

  /// Брызги от попадания: короткие быстрые искры цвета стихии.
  ///
  /// [scale] — рост фигуры в пикселях: искры на боссе обязаны быть крупнее,
  /// чем на падальщике, иначе удар по большому выглядит слабее удара по мелкому.
  void hit(Offset at, DamageType type, {bool crit = false, double scale = 60.0}) {
    final look = lookForDamage(type);
    final count = crit ? 28 : 12;
    final speed = scale * (crit ? 3.4 : 2.2);

    // Вспышка в точке удара. Первая версия обходилась одними искрами, и на
    // снимке было видно, почему этого мало: одиннадцать точек, разлетевшихся
    // за восьмую долю секунды, читаются как сор, а не как попадание.
    _impact()
      ..x = at.dx
      ..y = at.dy
      ..radius = scale * (crit ? 0.42 : 0.26)
      ..life = crit ? 0.16 : 0.11
      ..span = crit ? 0.16 : 0.11
      ..ring = false
      ..color = look.core;

    // Крит добавляет расходящееся кольцо: удар, который игрок обязан
    // заметить, не должен отличаться от обычного только размером пятна.
    if (crit) {
      _impact()
        ..x = at.dx
        ..y = at.dy
        ..radius = scale * 0.85
        ..life = 0.26
        ..span = 0.26
        ..ring = true
        ..color = look.glow;
    }

    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final power = 0.35 + _rng.nextDouble() * 0.65;
      _take()
        ..x = at.dx + _spread(scale * 0.06)
        ..y = at.dy + _spread(scale * 0.06)
        ..vx = math.cos(angle) * speed * power
        ..vy = math.sin(angle) * speed * power * 0.8
        ..life = 0.18 + _rng.nextDouble() * (crit ? 0.34 : 0.18)
        ..span = 0.5
        ..size = scale * (crit ? 0.042 : 0.032) * (0.6 + _rng.nextDouble())
        ..gravity = scale * 3.0
        ..drag = 3.4
        // Сердцевина у трети искр: однотонный веер читается как пятно, а
        // разнояркий — как брызги.
        ..color = i % 3 == 0 ? look.core : look.glow;
    }
  }

  /// Гибель: фигура осыпается. Частицы своего цвета, а не стихии, — уходит
  /// именно ЭТОТ противник, и узнаётся он по цвету.
  void death(Offset at, Color color, {double scale = 60.0}) {
    for (var i = 0; i < 16; i++) {
      final angle = -math.pi / 2 + _spread(1.1);
      _take()
        ..x = at.dx + _spread(scale * 0.22)
        ..y = at.dy - _rng.nextDouble() * scale * 0.75
        ..vx = math.cos(angle) * scale * 0.9 * _rng.nextDouble()
        ..vy = math.sin(angle) * scale * 0.7 * _rng.nextDouble()
        ..life = 0.5 + _rng.nextDouble() * 0.6
        ..span = 1.1
        ..size = scale * 0.026 * (0.5 + _rng.nextDouble())
        // Прах всплывает, а не падает: осыпающийся вниз силуэт читается как
        // обвал, всплывающий — как «его больше нет».
        ..gravity = -scale * 0.55
        ..drag = 1.3
        ..color = color;
    }
  }

  /// Пыль подземелья: редкие медленные пылинки в полосе боя.
  ///
  /// Единственный эффект, который живёт без событий. Без него неподвижная
  /// сцена между волнами читается как замерший кадр — «игра повисла», а не
  /// «наёмник идёт дальше».
  void ambient(Size field, double dt) {
    // Вероятность на кадр, а не «каждые N кадров»: на медленном телефоне
    // второе даёт вдвое меньше пыли, чем на быстром.
    if (_rng.nextDouble() > dt * 5.5) return;
    _take()
      ..x = _rng.nextDouble() * field.width
      ..y = field.height * (0.35 + _rng.nextDouble() * 0.6)
      ..vx = _spread(5.0)
      ..vy = -3.0 - _rng.nextDouble() * 6.0
      ..life = 2.4 + _rng.nextDouble() * 2.0
      ..span = 4.4
      ..size = 0.7 + _rng.nextDouble() * 1.0
      ..gravity = 0.0
      ..drag = 0.1
      ..color = const Color(0x66D9C8A9);
  }

  /// Цифра урона. Единицы урона на глубине сотни — тысячи, поэтому число
  /// округляется: три знака после запятой в бою никто не читает.
  void number(Offset at, double amount, {bool crit = false,
      DamageType type = DamageType.physical}) {
    if (amount < 1.0) return;

    final color = crit ? const Color(0xFFFFD08A) : lookForDamage(type).glow;

    // Частые удары по одной цели складываются в одну растущую цифру.
    //
    // Автоатака бьёт по нескольку раз в секунду, и отдельная цифра на каждый
    // удар давала над стражем кашу из одинаковых «49915», налезающих друг на
    // друга: старые всплывают ровно туда, где рождаются новые, и никакой
    // сдвиг это не лечит. Сумма читается сразу и честно показывает темп.
    // Крит не сливается: он и должен выпрыгнуть отдельно.
    if (!crit) {
      for (final n in _numbers) {
        if (!n.alive || n.crit || n.color != color) continue;
        if (n.fade < 0.45) continue;
        if ((n.x - at.dx).abs() > 48.0 || (n.y - at.dy).abs() > 60.0) continue;
        n
          ..value += amount.round()
          ..life = n.span;
        return;
      }
    }

    var slot = _numbers.where((n) => !n.alive).firstOrNull;
    if (slot == null && _numbers.length < maxNumbers) {
      slot = DamageNumber();
      _numbers.add(slot);
    }
    slot ??= _numbers.reduce((a, b) => a.fade < b.fade ? a : b);

    // Свежие цифры рядом сдвигают новую выше. Без этого удары по одной цели
    // ложились друг на друга, и над стражем висела нечитаемая стопка —
    // «49915» поверх «46615» поверх «49915». Молодыми считаются те, что ещё
    // не успели всплыть на высоту строки.
    var stack = 0;
    for (final n in _numbers) {
      if (identical(n, slot) || !n.alive || n.fade < 0.55) continue;
      if ((n.x - at.dx).abs() < 48.0 && (n.y - at.dy).abs() < 70.0) stack++;
    }
    final lift = (stack % 4) * 17.0;
    final side = (stack ~/ 4).isOdd ? 26.0 : 0.0;

    slot
      ..x = at.dx + _spread(14.0) + side
      ..y = at.dy - lift
      ..value = amount.round()
      ..crit = crit
      ..life = crit ? 0.95 : 0.7
      ..span = crit ? 0.95 : 0.7
      ..color = color;
  }

  /// Толчок камеры. Копится, а не заменяется: два крита подряд обязаны
  /// тряхнуть сильнее одного, — но с потолком, иначе боссовая волна
  /// превращает экран в дрожь, на которой ничего не разобрать.
  void kick(double amount) {
    _shake = math.min(_shake + amount, 14.0);
  }

  /// Смещение камеры на этом кадре.
  ///
  /// Затухающая синусоида, а не случайное дрожание: случайное читается как
  /// сломавшийся экран, затухающее — как удар.
  Offset get offset {
    if (_shake <= 0.01) return Offset.zero;
    return Offset(
      math.sin(_shakeTime * 61.0) * _shake,
      math.cos(_shakeTime * 47.0) * _shake * 0.6,
    );
  }

  void tick(double dt) {
    for (final p in _particles) {
      p.tick(dt);
    }
    for (final i in _impacts) {
      i.tick(dt);
    }
    for (final n in _numbers) {
      n.tick(dt);
    }
    if (_shake > 0.0) {
      _shakeTime += dt;
      // Экспоненциальное затухание: тряска обязана кончиться быстро и сама.
      _shake = math.max(0.0, _shake - _shake * 9.0 * dt - 0.6 * dt);
    }
  }

  /// Всё гаснет разом: новая волна не должна донести искры от предыдущей.
  void clear() {
    for (final p in _particles) {
      p.life = 0.0;
    }
    for (final n in _numbers) {
      n.life = 0.0;
    }
    for (final i in _impacts) {
      i.life = 0.0;
    }
    _shake = 0.0;
  }

  void render(Canvas canvas) {
    // Вспышки — ПОД искрами: искра, пропавшая в собственной вспышке, не
    // сообщает, чем ударили.
    for (final i in _impacts) {
      if (!i.alive) continue;
      final fade = i.fade;
      final center = Offset(i.x, i.y);
      if (i.ring) {
        canvas.drawCircle(
          center,
          i.radius * (1.0 - fade * 0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 + 3.0 * fade
            ..color = i.color.withValues(alpha: 0.55 * fade),
        );
      } else {
        // Радиус падает вместе с жизнью: вспышка схлопывается в точку удара,
        // а не расплывается пятном.
        final r = i.radius * (0.45 + 0.55 * fade);
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..shader = Gradient.radial(center, r, [
              i.color.withValues(alpha: 0.85 * fade),
              i.color.withValues(alpha: 0.0),
            ]),
        );
      }
    }

    final paint = Paint();
    for (final p in _particles) {
      if (!p.alive) continue;
      final fade = p.fade;
      paint.color = p.color.withValues(alpha: p.color.a * fade);
      canvas.drawCircle(Offset(p.x, p.y), p.size * (0.4 + 0.6 * fade), paint);
    }
  }

  /// Цифры рисуются отдельно от искр и ПОСЛЕ фигур: число, спрятанное за
  /// силуэтом босса, не сообщает ничего.
  void renderNumbers(Canvas canvas) {
    for (final n in _numbers) {
      if (!n.alive) continue;
      final fade = n.fade;
      // Крит выпрыгивает: первые мгновения он крупнее и оседает к своему
      // размеру. Одинаковое по размеру число на протяжении всей жизни
      // читалось надписью, а не ударом.
      final pop = n.crit ? 1.0 + 0.35 * math.max(0.0, (n.fade - 0.8) / 0.2) : 1.0;
      final size = (n.crit ? 21.0 : 14.5) * pop;
      final text = n.crit ? '${n.value}!' : '${n.value}';

      // Обводка — отдельным проходом под числом. Одна тень не спасала число
      // на светлой вспышке: край растворялся ровно в момент удара.
      final outline = ParagraphBuilder(ParagraphStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        textAlign: TextAlign.center,
      ))
        ..pushStyle(TextStyle(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.crit ? 4.0 : 3.0
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF0B0706).withValues(alpha: 0.85 * fade),
        ))
        ..addText(text);
      final outlined = outline.build()
        ..layout(const ParagraphConstraints(width: 120.0));
      canvas.drawParagraph(outlined, Offset(n.x - 60.0, n.y));

      final builder = ParagraphBuilder(ParagraphStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        textAlign: TextAlign.center,
      ))
        ..pushStyle(TextStyle(
          color: n.color.withValues(alpha: fade),
          // Тень под цифрой обязательна: светлое число на светлой вспышке
          // иначе пропадает ровно в тот момент, когда оно интереснее всего.
          shadows: [
            Shadow(
                color: const Color(0xFF000000).withValues(alpha: 0.6 * fade),
                blurRadius: 2.0,
                offset: const Offset(0, 1)),
          ],
        ))
        ..addText(text);

      final paragraph = builder.build()
        ..layout(const ParagraphConstraints(width: 120.0));
      canvas.drawParagraph(paragraph, Offset(n.x - 60.0, n.y));
    }
  }
}
