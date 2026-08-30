import 'package:flutter/foundation.dart' show compute;
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/descent.dart';

import '../data/content.dart';

/// Запрос на спуск. Только простые поля: объект уходит в другой изолят,
/// а туда нельзя передать замыкание (`HeroProfile.traitStats` — как раз оно).
class SimRequest {
  const SimRequest({
    required this.seed,
    required this.content,
    this.floorCap = 100000,
    this.powerMultiplier = 1.0,
    this.brandRank = 0,
    this.backpackCapacity = 12,
  });

  final int seed;

  /// Сырой контент. Разбирается уже внутри изолята — см. `ContentBundle.apply`.
  final Map<String, Object?> content;
  final int floorCap;
  final double powerMultiplier;
  final int brandRank;
  final int backpackCapacity;
}

/// Плоский результат для UI. Специально не отдаём `RunResult` наружу:
/// экранам не нужны 300 записей об этажах, а изоляту дешевле не копировать их.
class SimSummary {
  const SimSummary({
    required this.maxDepth,
    required this.ending,
    required this.totalSeconds,
    required this.echo,
    required this.gold,
    required this.itemsFound,
    required this.anomalies,
    required this.haulItems,
    required this.haulBestIlvl,
    required this.salvagedCount,
    required this.avgFloorSecondsLast5,
    required this.wallClockMs,
  });

  final int maxDepth;
  final RunEnding ending;
  final double totalSeconds;
  final int echo;
  final double gold;
  final int itemsFound;
  final int anomalies;
  final int haulItems;
  final int haulBestIlvl;
  final int salvagedCount;
  final double avgFloorSecondsLast5;

  /// Сколько реального времени заняла симуляция. Это и есть главная метрика
  /// переносимости на телефон: офлайн-догонялка не должна вешать старт.
  final int wallClockMs;
}

/// Гоняет спуск в фоновом изоляте.
///
/// На вебе `compute` вырождается в вызов на том же изоляте — это допустимо
/// для дев-экрана, но на Android/iOS работает как надо и не роняет кадры.
Future<SimSummary> runDescent(SimRequest request) =>
    compute(_runDescent, request);

SimSummary _runDescent(SimRequest request) {
  // Статики ядра в этом изоляте ещё не настроены — настраиваем (см. content.dart).
  ContentBundle.apply(request.content);

  final profile = HeroProfile(powerMultiplier: request.powerMultiplier);
  final sim = DescentSimulator(
    profile: profile,
    seed: request.seed,
    brandRank: request.brandRank,
    backpackCapacityOverride: request.backpackCapacity,
  );

  final started = DateTime.now();
  final result = sim.run(floorCap: request.floorCap, recordFloors: true);
  final elapsed = DateTime.now().difference(started).inMilliseconds;

  return SimSummary(
    maxDepth: result.maxDepth,
    ending: result.ending,
    totalSeconds: result.totalSeconds,
    echo: result.echo,
    gold: result.gold,
    itemsFound: result.itemsFound,
    anomalies: result.anomalies,
    haulItems: result.haul.itemCount,
    haulBestIlvl: result.haul.bestIlvl,
    salvagedCount: result.haul.salvagedCount,
    avgFloorSecondsLast5: result.avgFloorSecondsLast5,
    wallClockMs: elapsed,
  );
}
