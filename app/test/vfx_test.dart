import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift_app/game/combat_animation.dart';
import 'package:rift_app/game/vfx.dart';

/// Эффекты боя глазами не проверишь, а числами — можно.
///
/// Вопросы у теста не про красоту: гаснут ли частицы, не растёт ли их список
/// без конца, затухает ли тряска, различает ли игра стихии. Всё это видно
/// только в долгом бою на телефоне — то есть тогда, когда чинить уже поздно.
void main() {
  test('частицы гаснут сами', () {
    final vfx = Vfx()..hit(const Offset(10, 10), DamageType.fire);
    expect(vfx.particleCount, greaterThan(0));

    // Секунда — больше самой длинной искры. Всё, что переживёт её, будет жить
    // до конца боя и копиться кадр за кадром.
    for (var i = 0; i < 60; i++) {
      vfx.tick(1 / 60);
    }
    expect(vfx.particleCount, 0);
  });

  test('список частиц не растёт без конца', () {
    final vfx = Vfx();

    // Бой идёт по десять минут, и волна из пяти бьёт по нескольку раз в
    // секунду. Без потолка список растёт ровно до тех пор, пока кадр не
    // начнёт заикаться, — а заметит это игрок, а не тест.
    for (var i = 0; i < 500; i++) {
      vfx.hit(const Offset(10, 10), DamageType.cold, crit: true);
    }
    expect(vfx.particleCount, lessThanOrEqualTo(Vfx.maxParticles));
  });

  test('цифр урона не больше, чем помещается на экран', () {
    final vfx = Vfx();
    for (var i = 0; i < 100; i++) {
      vfx.number(const Offset(10, 10), 42.0);
    }
    expect(vfx.numberCount, lessThanOrEqualTo(Vfx.maxNumbers));
  });

  test('урон меньше единицы цифру не рождает', () {
    // Горение тикает десять раз в секунду долями единицы. Столб нулей над
    // мобом — это не информация, а помеха.
    final vfx = Vfx()..number(const Offset(0, 0), 0.4);
    expect(vfx.numberCount, 0);
  });

  test('тряска затухает и копится с потолком', () {
    final vfx = Vfx()..kick(4.0);
    final first = vfx.shakeAmount;
    expect(first, greaterThan(0.0));

    vfx.kick(4.0);
    expect(vfx.shakeAmount, greaterThan(first), reason: 'два крита ощутимее');

    for (var i = 0; i < 30; i++) {
      vfx.kick(20.0);
    }
    expect(vfx.shakeAmount, lessThanOrEqualTo(14.0),
        reason: 'боссовая волна не должна превращать экран в дрожь');

    for (var i = 0; i < 120; i++) {
      vfx.tick(1 / 60);
    }
    expect(vfx.shakeAmount, lessThan(0.05));
    expect(vfx.offset, Offset.zero);
  });

  test('новая волна не донесёт искры прошлой', () {
    final vfx = Vfx()
      ..hit(const Offset(10, 10), DamageType.voidType)
      ..number(const Offset(10, 10), 30.0)
      ..kick(5.0)
      ..clear();

    expect(vfx.particleCount, 0);
    expect(vfx.numberCount, 0);
    expect(vfx.shakeAmount, 0.0);
  });

  test('у каждой стихии свой цвет, и физический удар бесцветен', () {
    final glows = {
      for (final type in DamageType.values) lookForDamage(type).glow,
    };
    expect(glows, hasLength(DamageType.values.length),
        reason: 'две стихии с одним цветом — это одна стихия на экране');

    // Физический удар самый частый. Цветная вспышка на каждом ударе оружия
    // превратила бы бой в гирлянду, на фоне которой стихия ничего не значит.
    final plain = lookForDamage(DamageType.physical).glow;
    expect(plain.r, closeTo(plain.g, 0.2));
    expect(plain.g, closeTo(plain.b, 0.2));
  });

  test('крит виден крупнее обычного удара', () {
    final plain = Vfx()..hit(const Offset(0, 0), DamageType.physical);
    final crit = Vfx()..hit(const Offset(0, 0), DamageType.physical, crit: true);

    expect(crit.particleCount, greaterThan(plain.particleCount));
  });

  group('замах', () {
    test('удар начинается с движения НАЗАД', () {
      // Глаз читает удар по подготовке к нему. Фигура, прыгающая вперёд без
      // замаха, выглядит сдвинутой картинкой, а не ударившей.
      final anim = FigureAnim()..strike();
      anim.tick(swingSeconds * 0.15);
      expect(anim.lunge, lessThan(0.0));
    });

    test('выпад приходит ПОСЛЕ замаха и сильнее его', () {
      // Порядок и есть смысл анимации: сначала назад, потом вперёд. Проверяется
      // по всей кривой, а не в одной точке, — точка запомнила бы сегодняшние
      // длительности фаз и падала бы от любой их правки, ничего не говоря о
      // том, сломалось ли движение.
      final anim = FigureAnim()..strike();
      var minAt = 0.0;
      var maxAt = 0.0;
      var lowest = 0.0;
      var highest = 0.0;

      for (var step = 0; step < 40; step++) {
        final t = step / 40 * swingSeconds;
        if (anim.lunge < lowest) {
          lowest = anim.lunge;
          minAt = t;
        }
        if (anim.lunge > highest) {
          highest = anim.lunge;
          maxAt = t;
        }
        anim.tick(swingSeconds / 40);
      }

      expect(lowest, lessThan(-0.2), reason: 'замах назад должен быть виден');
      expect(highest, greaterThan(0.8), reason: 'выпад должен доставать цель');
      expect(maxAt, greaterThan(minAt), reason: 'сначала замах, потом удар');
    });

    test('фигура возвращается в стойку сама', () {
      final anim = FigureAnim()..strike();
      anim.tick(swingSeconds * 1.1);
      expect(anim.swinging, isFalse);
      expect(anim.lunge, 0.0);
    });
  });
}
