import 'package:flutter/material.dart';
import 'package:rift/core/sim/descent.dart';

import '../data/content.dart';
import 'flame_probe.dart';
import 'live_descent_panel.dart';
import 'sim_runner.dart';

/// Дев-экран, а не игровой UI.
///
/// Его единственная задача — доказать, что ядро из пакета `rift` крутится
/// на телефоне без единой правки: контент грузится из ассетов, спуск считается
/// в фоновом изоляте, Flame рисует поверх. Настоящие экраны (инвентарь, древо,
/// журнал отсутствия) делаются отдельно и по своему UI/UX.
class CoreProbeScreen extends StatefulWidget {
  const CoreProbeScreen({super.key, required this.content});

  final ContentBundle content;

  @override
  State<CoreProbeScreen> createState() => _CoreProbeScreenState();
}

class _CoreProbeScreenState extends State<CoreProbeScreen> {
  final _seed = TextEditingController(text: '42');
  double _power = 1.0;
  bool _busy = false;
  SimSummary? _last;
  Object? _error;

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await runDescent(SimRequest(
        seed: int.tryParse(_seed.text) ?? 42,
        content: widget.content.raw,
        powerMultiplier: _power,
      ));
      if (mounted) setState(() => _last = summary);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ядро · проба')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: battleProbeWidget(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Flame рисует сцену, ядро считает бой. Графика — заглушка.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const Divider(height: 32),
          const Text('Живой спуск — пошаговый драйвер в кадровом цикле',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 8),
          const LiveDescentPanel(),
          const Divider(height: 32),
          const Text('Батч-прогон — то же ядро, посчитанное мгновенно',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 8),
          TextField(
            controller: _seed,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Сид рана',
              helperText: 'Один сид — один и тот же ран. Детерминизм ядра.',
            ),
          ),
          const SizedBox(height: 16),
          Text('Множитель силы билда: ×${_power.toStringAsFixed(1)}'),
          Slider(
            value: _power,
            min: 1.0,
            max: 8.0,
            divisions: 14,
            label: '×${_power.toStringAsFixed(1)}',
            onChanged: (v) => setState(() => _power = v),
          ),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: Text(_busy ? 'Считаю…' : 'Спуск'),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Text('Ошибка: $_error',
                style: const TextStyle(color: Colors.redAccent))
          else if (_last != null)
            _SummaryTable(summary: _last!),
        ],
      ),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.summary});

  final SimSummary summary;

  static const _endings = {
    RunEnding.death: 'гибель',
    RunEnding.floorCap: 'потолок этажей',
    RunEnding.timeCap: 'лимит времени',
    RunEnding.stalled: 'стена (волна не убивается)',
  };

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rows = <(String, String)>[
      ('Глубина', '${s.maxDepth}'),
      ('Финал', _endings[s.ending] ?? '${s.ending}'),
      ('Игровое время', '${(s.totalSeconds / 60).toStringAsFixed(1)} мин'),
      ('Средний этаж (5)', '${s.avgFloorSecondsLast5.toStringAsFixed(1)} с'),
      ('Эхо', '${s.echo}'),
      ('Золото', s.gold.toStringAsFixed(0)),
      ('Найдено предметов', '${s.itemsFound}'),
      ('Донесено / лучший ilvl', '${s.haulItems} / ${s.haulBestIlvl}'),
      ('Распылено', '${s.salvagedCount}'),
      ('Аномалии шины', '${s.anomalies}'),
      ('Счёт на устройстве', '${s.wallClockMs} мс'),
    ];

    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
      children: [
        for (final (label, value) in rows)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            Text(value,
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontSize: 13)),
          ]),
      ],
    );
  }
}
