import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift_app/game/silhouettes.dart';

/// Бестиарий живёт в JSON, а силуэты — в коде. Это ровно та связь, которая
/// рвётся молча: моб добавляется контентом, картинка не добавляется никем,
/// и в бою появляется безымянная фигура-заглушка, которую никто не заметит,
/// пока игрок не спросит, почему все враги выглядят одинаково.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final content = jsonDecode(
    File('assets/content/enemies.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final ids = [
    for (final group in ['enemies', 'bosses'])
      for (final e in content[group] as List) (e as Map)['id'] as String,
  ];

  test('у каждого моба из контента свой силуэт', () {
    expect(ids, isNotEmpty);

    final missing = ids.where((id) => !knownSilhouetteIds.contains(id));
    expect(missing, isEmpty,
        reason: 'нет силуэта для $missing — в бою это будет заглушка');
  });

  test('силуэтов не больше, чем мобов', () {
    // Обратная сторона той же связи: удалённый из контента моб оставляет
    // мёртвый код, который никто не откроет и не удалит.
    final orphans = knownSilhouetteIds.where((id) => !ids.contains(id));
    expect(orphans, isEmpty, reason: 'силуэт без моба: $orphans');
  });

  test('каждый силуэт рисуется — и живой, и мёртвый', () {
    for (final id in ids) {
      final look = silhouetteFor(id);
      expect(() => _render(look), returnsNormally, reason: id);
      expect(() => _render(look.dead), returnsNormally, reason: id);
    }
    expect(() => _render(unknownSilhouette), returnsNormally);
  });

  test('фигура помещается в свою рамку в любой фазе анимации', () {
    // Ширина силуэта — то, по чему сцена расставляет волну. Если фигура рисует
    // себя шире заявленного, соседи налезают друг на друга, и пачка из пяти
    // читается одним пятном. Замер идёт по нескольким моментам времени:
    // пламя и щупальца шевелятся, и разъезжаются они не в нулевой фазе.
    for (final id in [...ids, '']) {
      final look = silhouetteFor(id);
      const height = 100.0;

      for (final t in [0.0, 0.4, 0.9, 1.7, 2.6, 3.3]) {
        final bounds = _boundsOf(look, t);
        expect(bounds.height, lessThanOrEqualTo(height * 1.15),
            reason: '$id в фазе $t');
        expect(bounds.width, lessThanOrEqualTo(height * look.aspect * 1.02),
            reason: '$id в фазе $t шире объявленного aspect=${look.aspect}');
      }
    }
  });

  group('оружие героя видно в силуэте', () {
    test('пустые руки', () {
      expect(heroWeaponOf(Equipment()), HeroWeapon.unarmed);
    });

    test('одноручник без левой руки', () {
      final gear = Equipment()..equipTo(0, _item(GearKind.weapon));
      expect(heroWeaponOf(gear), HeroWeapon.oneHanded);
    });

    test('одноручник со щитом', () {
      final gear = Equipment()
        ..equipTo(0, _item(GearKind.weapon))
        ..equipTo(1, _item(GearKind.offhand));
      expect(heroWeaponOf(gear), HeroWeapon.shielded);
    });

    test('двуручник', () {
      final gear = Equipment()
        ..equipTo(0, _item(GearKind.weapon, twoHanded: true));
      expect(heroWeaponOf(gear), HeroWeapon.twoHanded);
    });
  });
}

Item _item(GearKind kind, {bool twoHanded = false}) => Item(
      kind: kind,
      ilvl: 10,
      rarity: Rarity.common,
      affixes: const [],
      twoHanded: twoHanded,
    );

void _render(Silhouette look) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  look.draw(Sketch(
    canvas: canvas,
    feet: const Offset(200, 300),
    height: 100,
    t: 1.7,
    body: look.body,
    accent: look.accent,
  ));
  recorder.endRecording().dispose();
}

/// Границы нарисованного. Считаются перехватом самих вызовов рисования:
/// картинку не измерить, а обещание «фигура шириной aspect» проверить надо.
Rect _boundsOf(Silhouette look, double t) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.saveLayer(null, Paint());

  final probe = _Bounds();
  look.draw(Sketch(
    canvas: probe,
    feet: Offset.zero,
    height: 100,
    t: t,
    body: look.body,
    accent: look.accent,
  ));

  canvas.restore();
  recorder.endRecording().dispose();
  return probe.bounds;
}

/// Холст, который ничего не рисует, а только запоминает, куда его просили
/// рисовать. Так проверяется геометрия фигуры без сравнения картинок.
class _Bounds implements Canvas {
  Rect bounds = Rect.zero;
  var _empty = true;

  void _add(Rect r) {
    bounds = _empty ? r : bounds.expandToInclude(r);
    _empty = false;
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _add(Rect.fromCircle(center: c, radius: radius));

  @override
  void drawOval(Rect rect, Paint paint) => _add(rect);

  @override
  void drawRect(Rect rect, Paint paint) => _add(rect);

  @override
  void drawPath(Path path, Paint paint) => _add(path.getBounds());

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _add(
        Rect.fromPoints(p1, p2).inflate(paint.strokeWidth / 2),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
