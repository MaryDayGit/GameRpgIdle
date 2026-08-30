import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Генератор звуков игры.
///
/// Звуки синтезируются кодом, а не скачиваются, по той же причине, что фигуры
/// в бою рисуются кодом: чужой файл — это лицензия, вес пакета и второй
/// источник правды о том, как игра звучит. Здесь источник один — этот файл,
/// а `.wav` в ассетах его вывод.
///
/// Запуск: `dart run tool/make_sounds.dart`
///
/// Палитра нарочно узкая: глухой удар, звонкий крит, оседающий тон смерти.
/// Игра идёт по десять минут фоном, и звук, который хочется выключить на
/// третьей минуте, хуже тишины.
void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'app/assets/audio' : args.first);
  dir.createSync(recursive: true);

  final sounds = <String, Float64List>{
    // Удар: короткий глухой толчок. Звучит по нескольку раз в секунду,
    // поэтому он самый тихий и самый короткий в наборе.
    'hit': _mix([
      _tone(freq: 180, to: 120, seconds: 0.07, attack: 0.002, decay: 0.06),
      _noise(seconds: 0.05, decay: 0.04, gain: 0.35),
    ], gain: 0.45),

    // Крит: тот же удар, но с призвуком сверху — отличается на слух, не
    // становясь вторым звуком.
    'crit': _mix([
      _tone(freq: 260, to: 150, seconds: 0.10, attack: 0.002, decay: 0.09),
      _tone(freq: 880, to: 660, seconds: 0.09, attack: 0.001, decay: 0.08,
          gain: 0.30),
      _noise(seconds: 0.06, decay: 0.05, gain: 0.30),
    ], gain: 0.55),

    // Гибель моба: короткий оседающий тон.
    'kill': _mix([
      _tone(freq: 420, to: 160, seconds: 0.16, attack: 0.004, decay: 0.15),
    ], gain: 0.4),

    // Попадание по герою: низкий и мутный, чтобы не спутать с ударом героя.
    'hurt': _mix([
      _tone(freq: 110, to: 70, seconds: 0.14, attack: 0.003, decay: 0.13,
          triangle: true),
      _noise(seconds: 0.08, decay: 0.07, gain: 0.25),
    ], gain: 0.5),

    // Гибель наёмника: длинный спад. Единственный звук, который имеет право
    // длиться — ран закончился.
    'death': _mix([
      _tone(freq: 300, to: 60, seconds: 0.9, attack: 0.01, decay: 0.85,
          triangle: true),
      _tone(freq: 150, to: 40, seconds: 0.9, attack: 0.02, decay: 0.85,
          gain: 0.5),
    ], gain: 0.55),

    // Отправка вниз: два тона вверх — «пошёл».
    'deploy': _mix([
      _tone(freq: 330, seconds: 0.10, attack: 0.005, decay: 0.09, gain: 0.6),
      _delay(
          _tone(freq: 495, seconds: 0.16, attack: 0.005, decay: 0.15), 0.09),
    ], gain: 0.5),

    // Награда: забрать добычу, купить узел, скрафтить. Один звук на все
    // приобретения — их и объединяет одно: игрок что-то получил.
    'reward': _mix([
      _tone(freq: 587, seconds: 0.12, attack: 0.004, decay: 0.11, gain: 0.5),
      _delay(_tone(freq: 784, seconds: 0.20, attack: 0.004, decay: 0.19), 0.08),
      _delay(
          _tone(freq: 1046, seconds: 0.26, attack: 0.004, decay: 0.25,
              gain: 0.45),
          0.16),
    ], gain: 0.45),
  };

  for (final entry in sounds.entries) {
    final file = File('${dir.path}/${entry.key}.wav');
    file.writeAsBytesSync(_wav(entry.value));
    stdout.writeln('${file.path}: ${file.lengthSync()} байт');
  }
}

const _rate = 22050;

/// Тон с затуханием и, при желании, скольжением частоты.
///
/// Треугольная волна вместо синуса там, где нужен «грязный» звук: чистый
/// синус на низких частотах звучит как гудок прибора, а не как удар.
Float64List _tone({
  required double freq,
  double? to,
  required double seconds,
  required double attack,
  required double decay,
  double gain = 1.0,
  bool triangle = false,
}) {
  final samples = (seconds * _rate).round();
  final out = Float64List(samples);
  var phase = 0.0;

  for (var i = 0; i < samples; i++) {
    final t = i / _rate;
    final k = samples == 1 ? 0.0 : i / (samples - 1);
    final f = to == null ? freq : freq + (to - freq) * k;

    phase += 2 * math.pi * f / _rate;
    final wave = triangle
        ? 2 / math.pi * math.asin(math.sin(phase))
        : math.sin(phase);

    out[i] = wave * gain * _envelope(t, seconds, attack, decay);
  }
  return out;
}

/// Шум — то, что делает удар ударом, а не нотой.
Float64List _noise({
  required double seconds,
  required double decay,
  double gain = 1.0,
}) {
  final samples = (seconds * _rate).round();
  final out = Float64List(samples);

  // Свой генератор, а не `Random()`: набор звуков обязан получаться
  // одинаковым при каждом запуске, иначе ассеты «меняются» на пустом месте.
  var state = 0x9E3779B9;
  for (var i = 0; i < samples; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;

    final value = (state & 0xFFFF) / 0x7FFF - 1.0;
    out[i] = value * gain * _envelope(i / _rate, seconds, 0.001, decay);
  }
  return out;
}

double _envelope(double t, double total, double attack, double decay) {
  if (t < attack) return t / attack;
  final rest = (t - attack) / math.max(decay, 1e-6);
  return math.exp(-3.5 * rest);
}

/// Сдвигает звук во времени: из этого собираются двух- и трёхнотные сигналы.
Float64List _delay(Float64List source, double seconds) {
  final offset = (seconds * _rate).round();
  final out = Float64List(source.length + offset);
  for (var i = 0; i < source.length; i++) {
    out[i + offset] = source[i];
  }
  return out;
}

/// Складывает слои и мягко ограничивает результат.
///
/// Ограничитель — не украшение: сумма трёх слоёв легко выходит за единицу,
/// и в 16-битном wav это не «громко», а треск от переполнения.
Float64List _mix(List<Float64List> layers, {double gain = 1.0}) {
  final length = layers.fold(0, (m, l) => math.max(m, l.length));
  final out = Float64List(length);

  for (final layer in layers) {
    for (var i = 0; i < layer.length; i++) {
      out[i] += layer[i];
    }
  }
  for (var i = 0; i < length; i++) {
    final v = out[i] * gain;
    out[i] = v / (1.0 + v.abs() * 0.4);
  }
  return out;
}

/// 16-битный моно WAV. Формат выбран за то, что его играет всё и без
/// декодера: звуки короткие, и экономить тут нечего.
Uint8List _wav(Float64List samples) {
  final data = ByteData(44 + samples.length * 2);
  var offset = 0;

  void ascii(String s) {
    for (final c in s.codeUnits) {
      data.setUint8(offset++, c);
    }
  }

  void u32(int v) {
    data.setUint32(offset, v, Endian.little);
    offset += 4;
  }

  void u16(int v) {
    data.setUint16(offset, v, Endian.little);
    offset += 2;
  }

  ascii('RIFF');
  u32(36 + samples.length * 2);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // моно
  u32(_rate);
  u32(_rate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(samples.length * 2);

  for (final s in samples) {
    final clamped = s.clamp(-1.0, 1.0);
    data.setInt16(offset, (clamped * 32767).round(), Endian.little);
    offset += 2;
  }
  return data.buffer.asUint8List();
}
