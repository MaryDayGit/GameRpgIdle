import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Генератор иконки приложения.
///
/// Инструмент, а не тест: живёт в `tool/`, запускается руками, когда иконку
/// надо перерисовать.
///
///   flutter test tool/make_icon.dart
///
/// Через `flutter test` — потому что рисовать умеет только движок Flutter,
/// а ему нужна привязка. Иконка рисуется тем же кодом, что фигуры в бою и
/// снаряжение в сетке: расселина между двух плит и клинок, уходящий вниз.
/// Свой рисунок вместо дефолтной синей «F» — по той же причине, что и
/// остальная графика: чужой файл это лицензия и вторая правда о том, как
/// игра выглядит.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('иконка приложения', () async {
    const launcher = {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };
    for (final entry in launcher.entries) {
      final bytes = await _render(entry.value.toDouble(), full: true);
      File('android/app/src/main/res/${entry.key}/ic_launcher.png')
          .writeAsBytesSync(bytes);
    }

    // Передний план адаптивной иконки рисуется на 108 dp: система обрежет
    // его маской своей формы, поэтому важное живёт в центре.
    const adaptive = {
      'mipmap-mdpi': 108,
      'mipmap-hdpi': 162,
      'mipmap-xhdpi': 216,
      'mipmap-xxhdpi': 324,
      'mipmap-xxxhdpi': 432,
    };
    for (final entry in adaptive.entries) {
      final bytes = await _render(entry.value.toDouble(), full: false);
      File('android/app/src/main/res/${entry.key}/ic_launcher_foreground.png')
          .writeAsBytesSync(bytes);
    }
  });
}

Future<Uint8List> _render(double size, {required bool full}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  const background = Color(0xFF15100E);
  const stone = Color(0xFF3A312D);
  const rift = Color(0xFFC7643F);
  const blade = Color(0xFFD9C8A9);

  if (full) {
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size, size), Paint()..color = background);
  }

  final scale = full ? size : size * 0.62;
  final offset = full ? 0.0 : (size - scale) / 2;

  canvas.save();
  canvas.translate(offset, offset);

  Offset at(double x, double y) => Offset(x * scale, y * scale);
  void poly(List<Offset> points, Color color) {
    final first = at(points.first.dx, points.first.dy);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = at(p.dx, p.dy);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  // Две плиты во весь кадр, между ними — светящаяся расселина. Плиты
  // упираются в края: рамка по периметру превращала бы иконку в картинку
  // в рамке, а маска лаунчера всё равно срежет углы.
  poly(const [Offset(-0.02, -0.02), Offset(0.40, -0.02), Offset(0.30, 0.50),
      Offset(0.42, 1.02), Offset(-0.02, 1.02)], stone);
  poly(const [Offset(1.02, -0.02), Offset(0.60, -0.02), Offset(0.70, 0.50),
      Offset(0.58, 1.02), Offset(1.02, 1.02)], stone);
  poly(const [Offset(0.40, -0.02), Offset(0.60, -0.02), Offset(0.70, 0.50),
      Offset(0.58, 1.02), Offset(0.42, 1.02), Offset(0.30, 0.50)], rift);

  // Клинок остриём вниз — наёмник уходит в расселину. Узкий: расселина
  // должна светиться по обе стороны, иначе иконка читается мечом, а не
  // спуском.
  poly(const [Offset(0.50, 0.88), Offset(0.455, 0.58), Offset(0.475, 0.30),
      Offset(0.525, 0.30), Offset(0.545, 0.58)], blade);
  canvas.drawRect(
    Rect.fromCenter(
        center: at(0.5, 0.28), width: 0.22 * scale, height: 0.045 * scale),
    Paint()..color = blade,
  );
  canvas.drawCircle(at(0.5, 0.19), 0.045 * scale, Paint()..color = blade);

  canvas.restore();

  final image = await recorder.endRecording().toImage(
        size.round(),
        size.round(),
      );
  final data = await image.toByteData(format: ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
