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
/// ## Вторая версия
///
/// Первая палитра была честной, но сухой: чистые тоны без пространства, 22 кГц
/// и ровно один файл на звук. На телефоне это давало две беды, и обе слышны
/// за первую же минуту боя.
///
/// * **Одинаковость.** Удар звучит по нескольку раз в секунду, и один и тот
///   же файл, повторённый сто раз, превращается в метроном — ухо перестаёт
///   слышать удар и начинает слышать повтор. Теперь у частых звуков по три
///   дубля: тот же удар, чуть выше или ниже и с другим шумом.
/// * **Сухость.** Звук без хвоста обрывается, как выключенный, и игра
///   звучит пустой комнатой. Короткое отражение (`_room`) даёт звукам место,
///   где они звучат, — подземелье, а не микрофон у динамика.
///
/// Громкость и длина по-прежнему по роли: частое тихо и коротко, редкое имеет
/// право звучать. Игра идёт по десять минут фоном, и звук, который хочется
/// выключить на третьей минуте, хуже тишины.
void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'app/assets/audio' : args.first);
  dir.createSync(recursive: true);

  final sounds = <String, Float64List>{};

  // Три дубля частого звука: основной и два со сдвигом высоты. Сдвиг — пара
  // процентов: больше, и дубли слышатся разными ударами, меньше — одинаковыми.
  void takes(String name, Float64List Function(int take) make) {
    sounds[name] = make(0);
    sounds['${name}_1'] = make(1);
    sounds['${name}_2'] = make(2);
  }

  const detune = [1.0, 0.955, 1.045];

  // --- Бой: удары ----------------------------------------------------------

  // Удар оружием: глухой толчок с хрустом. Самый частый — самый тихий.
  takes('hit', (t) => _room(_mix([
        _tone(freq: 170 * detune[t], to: 95, seconds: 0.08, attack: 0.001,
            decay: 0.06, gain: 0.9),
        _lowpass(_noise(seconds: 0.06, decay: 0.035, gain: 0.7, seed: t), 0.5),
        _highpass(_noise(seconds: 0.02, decay: 0.012, gain: 0.35, seed: t + 9),
            0.6),
      ], gain: 0.5), wet: 0.12, size: 0.35));

  // Огонь: толчок и потрескивание, догорающее следом.
  takes('hitFire', (t) => _room(_mix([
        _tone(freq: 140 * detune[t], to: 80, seconds: 0.09, attack: 0.002,
            decay: 0.07),
        _lowpass(_noise(seconds: 0.14, decay: 0.09, gain: 0.6, seed: t), 0.3),
        _crackle(seconds: 0.18, density: 0.012, gain: 0.35, seed: t),
      ], gain: 0.45), wet: 0.15, size: 0.4));

  // Холод: стеклянный звон — высокий, сухой, со звенящим призвуком.
  takes('hitCold', (t) => _room(_mix([
        _tone(freq: 1320 * detune[t], to: 1040, seconds: 0.12, attack: 0.001,
            decay: 0.1, gain: 0.34),
        _tone(freq: 2640 * detune[t], to: 2380, seconds: 0.08, attack: 0.001,
            decay: 0.06, gain: 0.16),
        _tone(freq: 3960 * detune[t], seconds: 0.05, attack: 0.001,
            decay: 0.04, gain: 0.08),
        _highpass(_noise(seconds: 0.04, decay: 0.03, gain: 0.35, seed: t), 0.6),
      ], gain: 0.42), wet: 0.22, size: 0.55));

  // Молния: сухой разряд с треском, самый короткий.
  takes('hitLightning', (t) => _room(_mix([
        _highpass(_noise(seconds: 0.05, decay: 0.03, gain: 0.95, seed: t), 0.72),
        _crackle(seconds: 0.07, density: 0.05, gain: 0.5, seed: t + 3),
        _tone(freq: 2200 * detune[t], to: 900, seconds: 0.05, attack: 0.001,
            decay: 0.04, gain: 0.22),
        _tone(freq: 300 * detune[t], to: 200, seconds: 0.07, attack: 0.001,
            decay: 0.06, gain: 0.3),
      ], gain: 0.4), wet: 0.1, size: 0.3));

  // Пустота: тон уходит вниз и затягивает. Без атаки — он не бьёт.
  takes('hitVoid', (t) => _room(_mix([
        _tone(freq: 320 * detune[t], to: 55, seconds: 0.18, attack: 0.012,
            decay: 0.15, triangle: true, gain: 0.55),
        _tone(freq: 322 * detune[t] * 1.5, to: 80, seconds: 0.16,
            attack: 0.015, decay: 0.13, gain: 0.18),
        _lowpass(_noise(seconds: 0.14, decay: 0.12, gain: 0.35, seed: t), 0.15),
      ], gain: 0.42), wet: 0.3, size: 0.7));

  // Крит: удар и звонкий «дзынь» сверху. Слышно, не глядя на экран.
  takes('crit', (t) => _room(_mix([
        _tone(freq: 240 * detune[t], to: 120, seconds: 0.11, attack: 0.001,
            decay: 0.09),
        _tone(freq: 988 * detune[t], to: 880, seconds: 0.18, attack: 0.001,
            decay: 0.16, gain: 0.32),
        _tone(freq: 1976 * detune[t], seconds: 0.1, attack: 0.001, decay: 0.08,
            gain: 0.12),
        _noise(seconds: 0.05, decay: 0.035, gain: 0.35, seed: t),
      ], gain: 0.55), wet: 0.2, size: 0.5));

  // Гибель моба: короткий оседающий тон с пыльным хвостом.
  takes('kill', (t) => _room(_mix([
        _tone(freq: 440 * detune[t], to: 150, seconds: 0.2, attack: 0.004,
            decay: 0.17, gain: 0.8),
        _lowpass(_noise(seconds: 0.22, decay: 0.18, gain: 0.3, seed: t), 0.2),
      ], gain: 0.4), wet: 0.2, size: 0.5));

  // Попадание по герою: низкий и мутный, чтобы не спутать с ударом героя.
  takes('hurt', (t) => _room(_mix([
        _tone(freq: 115 * detune[t], to: 65, seconds: 0.16, attack: 0.002,
            decay: 0.14, triangle: true),
        _lowpass(_noise(seconds: 0.1, decay: 0.08, gain: 0.45, seed: t), 0.25),
      ], gain: 0.52), wet: 0.12, size: 0.35));

  // --- Бой: события --------------------------------------------------------

  // Способность: подъём с искрой. Удар падает, заклинание поднимается.
  sounds['cast'] = _room(_mix([
    _tone(freq: 440, to: 880, seconds: 0.2, attack: 0.008, decay: 0.17,
        gain: 0.45),
    _delay(_tone(freq: 880, to: 1320, seconds: 0.16, attack: 0.004,
        decay: 0.14, gain: 0.22), 0.05),
    _highpass(_noise(seconds: 0.12, decay: 0.1, gain: 0.15), 0.8),
  ], gain: 0.4), wet: 0.3, size: 0.6);

  // Босс: рык из глубины. Длинный и низкий — он и звучит раз за волну.
  sounds['boss'] = _room(_mix([
    _tone(freq: 82, to: 49, seconds: 1.1, attack: 0.04, decay: 1.0,
        triangle: true, gain: 0.8),
    _tone(freq: 123, to: 73, seconds: 1.0, attack: 0.06, decay: 0.9,
        gain: 0.35),
    _tremolo(_lowpass(_noise(seconds: 0.95, decay: 0.8, gain: 0.5), 0.08),
        rate: 18, depth: 0.6),
  ], gain: 0.55), wet: 0.35, size: 0.9);

  // Босс повержен: тяжёлый удар и победный подъём. Самое крупное событие боя.
  sounds['bossDown'] = _room(_mix([
    _tone(freq: 98, to: 55, seconds: 0.5, attack: 0.002, decay: 0.45,
        triangle: true, gain: 0.7),
    _lowpass(_noise(seconds: 0.4, decay: 0.3, gain: 0.5), 0.12),
    _delay(_chord([392, 494, 587], seconds: 0.9, gain: 0.3), 0.18),
    _delay(_tone(freq: 784, seconds: 0.8, attack: 0.01, decay: 0.7,
        gain: 0.2), 0.34),
  ], gain: 0.5), wet: 0.35, size: 0.85);

  // Этаж пройден: короткий светлый подъём. Отмечает шаг вниз, не прерывая боя.
  sounds['floor'] = _room(_mix([
    _tone(freq: 523, seconds: 0.1, attack: 0.004, decay: 0.09, gain: 0.4),
    _delay(_tone(freq: 784, seconds: 0.18, attack: 0.004, decay: 0.16,
        gain: 0.35), 0.07),
  ], gain: 0.4), wet: 0.3, size: 0.6);

  // Развилка: вопрос. Два тона, второй не разрешается — звук ждёт ответа.
  sounds['fork'] = _room(_mix([
    _chord([440, 554], seconds: 0.3, gain: 0.35),
    _delay(_chord([466, 587], seconds: 0.5, gain: 0.35), 0.22),
    _delay(_tone(freq: 1175, seconds: 0.35, attack: 0.01, decay: 0.3,
        gain: 0.08), 0.24),
  ], gain: 0.45), wet: 0.4, size: 0.8);

  // Гибель наёмника: длинный спад. Ран закончился — звуку можно длиться.
  sounds['death'] = _room(_mix([
    _tone(freq: 294, to: 58, seconds: 1.2, attack: 0.01, decay: 1.1,
        triangle: true),
    _tone(freq: 147, to: 37, seconds: 1.2, attack: 0.02, decay: 1.1,
        gain: 0.5),
    _delay(_chord([220, 262, 330], seconds: 1.0, gain: 0.12), 0.25),
  ], gain: 0.55), wet: 0.4, size: 0.9);

  // --- Застава -------------------------------------------------------------

  // Отправка вниз: два тона вверх и шорох верёвки.
  sounds['deploy'] = _room(_mix([
    _tone(freq: 330, seconds: 0.12, attack: 0.005, decay: 0.1, gain: 0.55),
    _delay(_tone(freq: 494, seconds: 0.2, attack: 0.005, decay: 0.18), 0.1),
    _lowpass(_noise(seconds: 0.35, decay: 0.3, gain: 0.18), 0.1),
  ], gain: 0.5), wet: 0.25, size: 0.55);

  // Добыча забрана: три ноты вверх. Главная награда игры.
  sounds['reward'] = _room(_mix([
    _tone(freq: 587, seconds: 0.14, attack: 0.004, decay: 0.12, gain: 0.5),
    _delay(_tone(freq: 784, seconds: 0.22, attack: 0.004, decay: 0.2), 0.08),
    _delay(_chord([1046, 1318], seconds: 0.45, gain: 0.3), 0.16),
    _delay(_sparkle(seconds: 0.4, gain: 0.12), 0.18),
  ], gain: 0.45), wet: 0.3, size: 0.6);

  // Покупка: монеты. Узел древа, постройка, крафт — всё, что стоит золота
  // или Эха. Раньше звучало той же фанфарой, что и добыча, и фанфара на
  // каждое нажатие в Кузнице перестала что-либо значить.
  sounds['buy'] = _room(_mix([
    _coin(0.0, 2093),
    _coin(0.06, 2349),
    _coin(0.11, 1976),
    _tone(freq: 392, seconds: 0.08, attack: 0.002, decay: 0.06, gain: 0.2),
  ], gain: 0.4), wet: 0.2, size: 0.4);

  // Реликт: редкая находка — аккорд с долгим звоном.
  sounds['relic'] = _room(_mix([
    _chord([523, 659, 784, 1046], seconds: 1.2, gain: 0.26),
    _delay(_sparkle(seconds: 1.0, gain: 0.18), 0.05),
    _tone(freq: 131, seconds: 0.9, attack: 0.02, decay: 0.8, gain: 0.25,
        triangle: true),
  ], gain: 0.45), wet: 0.45, size: 0.95);

  var bytes = 0;
  for (final entry in sounds.entries) {
    final file = File('${dir.path}/${entry.key}.wav');
    file.writeAsBytesSync(_wav(_normalize(entry.value)));
    bytes += file.lengthSync();
    stdout.writeln('${file.path}: ${file.lengthSync()} байт');
  }
  stdout.writeln('Всего ${sounds.length} звуков, ${(bytes / 1024).round()} КБ');
}

const _rate = 32000;

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
    // Скольжение по экспоненте, а не по прямой: ухо слышит высоту в
    // интервалах, и прямое скольжение звучало бы как «падает в конце».
    final f = to == null ? freq : freq * math.pow(to / freq, k);

    phase += 2 * math.pi * f / _rate;
    final wave = triangle
        ? 2 / math.pi * math.asin(math.sin(phase))
        : math.sin(phase);

    out[i] = wave * gain * _envelope(t, seconds, attack, decay);
  }
  return out;
}

/// Несколько тонов разом, с лёгкой расстройкой: живой аккорд, а не орган.
Float64List _chord(List<double> freqs,
    {required double seconds, double gain = 1.0}) {
  return _mix([
    for (final (i, f) in freqs.indexed)
      _tone(
        freq: f * (1.0 + (i.isEven ? 0.002 : -0.002)),
        seconds: seconds,
        attack: 0.006 + i * 0.004,
        decay: seconds * 0.85,
        gain: gain,
      ),
  ]);
}

/// Звон монеты: высокий тон с быстрым затуханием и металлическим призвуком.
Float64List _coin(double at, double freq) => _delay(
      _mix([
        _tone(freq: freq, seconds: 0.12, attack: 0.001, decay: 0.1,
            gain: 0.5),
        _tone(freq: freq * 2.76, seconds: 0.06, attack: 0.001, decay: 0.05,
            gain: 0.18),
      ]),
      at,
    );

/// Искристый хвост: рассыпь коротких высоких нот.
Float64List _sparkle({required double seconds, double gain = 1.0}) {
  final rng = _Rng(77);
  final layers = <Float64List>[];
  const notes = [2093.0, 2349.0, 2637.0, 3136.0, 3520.0];
  for (var i = 0; i < 9; i++) {
    layers.add(_delay(
      _tone(
        freq: notes[rng.next(notes.length)],
        seconds: 0.08,
        attack: 0.001,
        decay: 0.07,
        gain: gain * (1.0 - i / 12),
      ),
      seconds * i / 10,
    ));
  }
  return _mix(layers);
}

/// Шум — то, что делает удар ударом, а не нотой.
///
/// [seed] разный у дублей: одинаковый шум под разной высотой тона всё равно
/// выдаёт повтор.
Float64List _noise({
  required double seconds,
  required double decay,
  double gain = 1.0,
  int seed = 0,
}) {
  final samples = (seconds * _rate).round();
  final out = Float64List(samples);
  final rng = _Rng(0x9E3779B9 ^ (seed * 7919));
  for (var i = 0; i < samples; i++) {
    out[i] = rng.signed() * gain * _envelope(i / _rate, seconds, 0.001, decay);
  }
  return out;
}

/// Треск: редкие короткие щелчки. Огонь потрескивает, разряд трещит — и то и
/// другое не шум, а россыпь отдельных событий.
Float64List _crackle({
  required double seconds,
  required double density,
  double gain = 1.0,
  int seed = 0,
}) {
  final samples = (seconds * _rate).round();
  final out = Float64List(samples);
  final rng = _Rng(0x51ED270B ^ (seed * 104729));
  for (var i = 0; i < samples; i++) {
    if (rng.unit() > density) continue;
    final len = 20 + rng.next(60);
    final amp = gain * (0.4 + rng.unit() * 0.6) *
        math.exp(-3.0 * i / samples);
    for (var j = 0; j < len && i + j < samples; j++) {
      out[i + j] += rng.signed() * amp * math.exp(-j / (len * 0.3));
    }
  }
  return out;
}

/// Однополюсный фильтр: глушит верх.
Float64List _lowpass(Float64List source, double k) {
  final out = Float64List(source.length);
  var last = 0.0;
  for (var i = 0; i < source.length; i++) {
    last += (source[i] - last) * k;
    out[i] = last;
  }
  return out;
}

/// Обратный ему: оставляет верх.
Float64List _highpass(Float64List source, double k) {
  final low = _lowpass(source, 1.0 - k);
  final out = Float64List(source.length);
  for (var i = 0; i < source.length; i++) {
    out[i] = source[i] - low[i];
  }
  return out;
}

/// Дрожание громкости: из ровного гула делает рык.
Float64List _tremolo(Float64List source,
    {required double rate, required double depth}) {
  final out = Float64List(source.length);
  for (var i = 0; i < source.length; i++) {
    final lfo = 1.0 - depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate * i / _rate));
    out[i] = source[i] * lfo;
  }
  return out;
}

double _envelope(double t, double total, double attack, double decay) {
  if (t < attack) return t / attack;
  final rest = (t - attack) / math.max(decay, 1e-6);
  // Последние миллисекунды доводятся до нуля: обрыв на ненулевом отсчёте
  // слышен щелчком в конце каждого звука.
  final tail = ((total - t) / 0.004).clamp(0.0, 1.0);
  return math.exp(-3.5 * rest) * tail;
}

/// Сдвигает звук во времени.
Float64List _delay(Float64List source, double seconds) {
  final offset = (seconds * _rate).round();
  final out = Float64List(source.length + offset);
  for (var i = 0; i < source.length; i++) {
    out[i + offset] = source[i];
  }
  return out;
}

/// Короткое пространство: четыре гребенчатых и два всепропускающих фильтра.
///
/// Схема Шрёдера — самая дешёвая реверберация, какая бывает, и для звуков
/// длиной в десятые доли секунды другой не нужно. [size] растягивает
/// задержки: удар звучит в тесном коридоре, босс — в зале. [wet] — сколько
/// отражения подмешано: у частых звуков мало, иначе бой превращается в гул.
Float64List _room(Float64List dry, {double wet = 0.2, double size = 0.5}) {
  final tail = (0.25 + size * 0.5) * _rate;
  final length = dry.length + tail.round();
  final input = Float64List(length)..setRange(0, dry.length, dry);

  const combMs = [29.7, 37.1, 41.1, 43.7];
  const allpassMs = [5.0, 1.7];
  final feedback = 0.62 + size * 0.22;

  final sum = Float64List(length);
  for (final ms in combMs) {
    final d = (ms * (0.6 + size) * _rate / 1000).round();
    final buf = Float64List(d);
    var idx = 0;
    var damp = 0.0;
    for (var i = 0; i < length; i++) {
      final y = buf[idx];
      damp += (y - damp) * 0.45;
      buf[idx] = input[i] + damp * feedback;
      idx = (idx + 1) % d;
      sum[i] += y / combMs.length;
    }
  }

  var wetSignal = sum;
  for (final ms in allpassMs) {
    final d = (ms * _rate / 1000).round();
    final buf = Float64List(d);
    var idx = 0;
    final out = Float64List(length);
    for (var i = 0; i < length; i++) {
      final b = buf[idx];
      final v = wetSignal[i] + b * 0.5;
      buf[idx] = v;
      out[i] = b - v * 0.5;
      idx = (idx + 1) % d;
    }
    wetSignal = out;
  }

  final out = Float64List(length);
  for (var i = 0; i < length; i++) {
    out[i] = input[i] * (1.0 - wet * 0.5) + wetSignal[i] * wet;
  }
  // Хвост затухает до нуля к концу файла, а не обрывается.
  final fade = (0.08 * _rate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return _trim(out);
}

/// Отрезает тишину в конце: хвост реверберации дописывает сотни миллисекунд
/// нулей, и файл весит больше, чем звучит.
Float64List _trim(Float64List s) {
  var end = s.length;
  while (end > 1 && s[end - 1].abs() < 1e-4) {
    end--;
  }
  return Float64List.sublistView(s, 0, end);
}

/// Складывает слои и мягко ограничивает результат.
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

/// Поднимает пик до общего уровня. Слои и пространство сдвигают громкость
/// по-разному, и без выравнивания звуки одной роли звучали бы вразнобой;
/// разница по ролям задаётся громкостью проигрывания (`data/feedback.dart`).
Float64List _normalize(Float64List s) {
  var peak = 0.0;
  for (final v in s) {
    peak = math.max(peak, v.abs());
  }
  if (peak < 1e-6) return s;
  final k = 0.89 / peak;
  return Float64List.fromList([for (final v in s) v * k]);
}

/// Детерминированный генератор: набор звуков обязан получаться одинаковым
/// при каждом запуске, иначе ассеты «меняются» на пустом месте.
class _Rng {
  _Rng(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int _step() {
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    return _state & 0xFFFFFFFF;
  }

  double unit() => _step() / 0xFFFFFFFF;
  double signed() => unit() * 2.0 - 1.0;
  int next(int bound) => _step() % bound;
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
