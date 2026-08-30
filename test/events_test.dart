import 'package:rift/core/sim/events.dart';
import 'package:test/test.dart';

void main() {
  test('слушатель получает событие', () {
    final bus = EventBus();
    var calls = 0;
    bus.subscribe(GameEventType.onHit, (_) => calls++, 'test');
    bus.beginTick();
    bus.emit(EventContext(GameEventType.onHit));
    expect(calls, 1);
  });

  test('каскад обрывается на заданной глубине', () {
    // Реальная петля из дизайна: «при крите сбросить кулдаун» + «крит
    // накладывает горение» + критующее горение. Без предохранителя это
    // зависание на тике, а в офлайне — краш при открытии приложения.
    final bus = EventBus(maxCascadeDepth: 4, maxTriggersPerTick: 10000);
    var depth = 0;
    var maxSeen = 0;
    bus.subscribe(GameEventType.onCrit, (_) {
      depth++;
      if (depth > maxSeen) maxSeen = depth;
      bus.emit(EventContext(GameEventType.onCrit));
      depth--;
    }, 'infinite_loop');

    bus.beginTick();
    bus.emit(EventContext(GameEventType.onCrit));

    expect(maxSeen, lessThanOrEqualTo(4));
    expect(bus.cascadeOverflows, greaterThan(0));
  });

  test('бюджет на тик ограничивает число срабатываний', () {
    final bus = EventBus(maxCascadeDepth: 100, maxTriggersPerTick: 16);
    var calls = 0;
    bus.subscribe(GameEventType.onHit, (_) => calls++, 'counter');

    bus.beginTick();
    for (var i = 0; i < 100; i++) {
      bus.emit(EventContext(GameEventType.onHit));
    }

    expect(calls, 16);
    expect(bus.budgetOverflows, greaterThan(0));
  });

  test('beginTick восстанавливает бюджет', () {
    final bus = EventBus(maxTriggersPerTick: 4);
    var calls = 0;
    bus.subscribe(GameEventType.onTick, (_) => calls++, 'counter');

    for (var tick = 0; tick < 3; tick++) {
      bus.beginTick();
      for (var i = 0; i < 10; i++) {
        bus.emit(EventContext(GameEventType.onTick));
      }
    }

    expect(calls, 12);
  });

  test('превышения видны как аномалии, а не проглатываются', () {
    final bus = EventBus(maxTriggersPerTick: 1);
    bus.subscribe(GameEventType.onKill, (_) {}, 'noop');
    bus.beginTick();
    bus.emit(EventContext(GameEventType.onKill));
    bus.emit(EventContext(GameEventType.onKill));
    expect(bus.hasAnomalies, isTrue);
  });

  test('событие без подписчиков не тратит бюджет', () {
    final bus = EventBus(maxTriggersPerTick: 2);
    bus.subscribe(GameEventType.onHit, (_) {}, 'noop');
    bus.beginTick();
    for (var i = 0; i < 50; i++) {
      bus.emit(EventContext(GameEventType.onWaveStart));
    }
    bus.emit(EventContext(GameEventType.onHit));
    expect(bus.budgetOverflows, 0);
  });
}
