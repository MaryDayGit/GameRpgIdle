import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/descent.dart';

/// Живой спуск: то же ядро, что считает офлайн, но идущее на глазах.
///
/// Дев-проба §3.1 из `docs/05-ANDROID-PORT.md`: доказывает, что пошаговый
/// драйвер втыкается в кадровый цикл Flutter без обёрток и без второй копии
/// боевой математики. Настоящий боевой экран — Фаза 5 и своё UI/UX.
class LiveDescentPanel extends StatefulWidget {
  const LiveDescentPanel({super.key});

  @override
  State<LiveDescentPanel> createState() => _LiveDescentPanelState();
}

class _LiveDescentPanelState extends State<LiveDescentPanel>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  DescentDriver? _driver;
  Duration _last = Duration.zero;
  double _speed = 1.0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
  }

  @override
  void dispose() {
    // Остановить обязательно: Ticker.dispose() на активном тикере падает
    // ассертом, а спуск на середине — это норма, а не исключение.
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    final driver = _driver;
    if (driver == null) return;

    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    // Ускорение — это больше тиков за кадр, а не более длинный тик.
    driver.advance(dt * _speed);

    if (driver.finished) {
      _ticker.stop();
      _running = false;
    }
    setState(() {});
  }

  void _start() {
    setState(() {
      _driver = DescentDriver(
        profile: HeroProfile(powerMultiplier: 3.0),
        seed: DateTime.now().millisecondsSinceEpoch % 100000,
      );
      _last = Duration.zero;
      _running = true;
    });
    _ticker.stop();
    _ticker.start();
  }

  void _toggle() {
    if (_driver == null) return;
    setState(() {
      if (_running) {
        _ticker.stop();
        _running = false;
      } else {
        _last = Duration.zero;
        _ticker.start();
        _running = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    final s = driver?.snapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _start,
              child: const Text('Новый спуск'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: driver == null || driver.finished ? null : _toggle,
              child: Text(_running ? 'Пауза' : 'Дальше'),
            ),
            const Spacer(),
            for (final speed in const [1.0, 2.0, 4.0, 20.0])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  label: Text('×${speed.toStringAsFixed(0)}'),
                  selected: _speed == speed,
                  onSelected: (_) => setState(() => _speed = speed),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (s == null)
          const Text('Спуск не начат.',
              style: TextStyle(color: Colors.white54, fontSize: 12))
        else ...[
          Text(
            s.finished
                ? 'Ран окончен: глубина ${driver!.result.maxDepth}, '
                    '${driver.result.ending.name}'
                : 'Этаж ${s.depth} · волна ${s.waveIndex}/${s.waveCount}'
                    '${s.isBossWave ? " · БОСС" : ""}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${s.enemyName} · живых ${s.enemiesAlive} · '
            '${(s.totalSeconds / 60).toStringAsFixed(1)} мин',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          _Bar(label: 'HP героя', value: s.heroHpFraction),
          const SizedBox(height: 6),
          _Bar(label: 'Волна', value: s.waveProgress),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: value, minHeight: 8),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(value * 100).round()} %',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
