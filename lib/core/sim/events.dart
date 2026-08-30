/// Типы боевых событий. Триггерные аффиксы и пассивные способности
/// подписываются на них (GDD §5.2, `docs/02-TECH.md` §2.3).
enum GameEventType {
  onTick,
  onWaveStart,
  onAbilityCast,
  onHit,
  onCrit,
  onKill,
  onDamageTaken,
  onHpBelow,
}

/// Контекст события. Поля намеренно слабо типизированы через `Object?`:
/// боевые сущности живут в `sim/combat.dart`, и шина не должна о них знать —
/// иначе `core/sim` перестанет быть переиспользуемым в офлайн-модели.
class EventContext {
  EventContext(this.type, {this.source, this.target, this.amount = 0.0});

  final GameEventType type;
  final Object? source;
  final Object? target;
  final double amount;
}

typedef TriggerListener = void Function(EventContext ctx);

class _Subscription {
  _Subscription(this.listener, this.label);

  final TriggerListener listener;
  final String label;
}

/// Шина событий с предохранителями от рекурсии.
///
/// Комбинация «при крите сбросить кулдаун» + «крит накладывает горение» +
/// критующее горение образует петлю. При невезучем сиде это зависание на тике,
/// а в офлайне — зависание при открытии приложения, то есть краш глазами
/// игрока (`docs/01-ANALYSIS.md` §6). Отсюда два жёстких лимита.
class EventBus {
  EventBus({
    this.maxCascadeDepth = 4,
    this.maxTriggersPerTick = 64,
  });

  /// Максимальная вложенность каскада событий.
  final int maxCascadeDepth;

  /// Бюджет срабатываний на один тик.
  final int maxTriggersPerTick;

  final Map<GameEventType, List<_Subscription>> _subs = {};

  int _cascade = 0;
  int _spentThisTick = 0;

  /// Диагностика для балансировщика: превышения — признак аномалии баланса,
  /// а не нормальной работы. Ненулевые значения обязаны попадать в отчёт.
  int cascadeOverflows = 0;
  int budgetOverflows = 0;
  int totalTriggers = 0;

  void subscribe(GameEventType type, TriggerListener listener, String label) {
    (_subs[type] ??= []).add(_Subscription(listener, label));
  }

  void clearSubscriptions() {
    _subs.clear();
  }

  /// Снимает подписки с этой меткой.
  ///
  /// Нужна, чтобы пересборка триггеров при смене снаряжения не сносила чужие
  /// подписки заодно. Сброс всей шины работал, только пока подписчик был один,
  /// — а это допущение, о котором забывают ровно тогда, когда оно перестаёт
  /// быть верным.
  void unsubscribe(String label) {
    for (final list in _subs.values) {
      list.removeWhere((sub) => sub.label == label);
    }
  }

  /// Вызывается ровно один раз в начале каждого тика симуляции.
  void beginTick() {
    _spentThisTick = 0;
    _cascade = 0;
  }

  void emit(EventContext ctx) {
    final subs = _subs[ctx.type];
    if (subs == null || subs.isEmpty) return;

    if (_cascade >= maxCascadeDepth) {
      cascadeOverflows++;
      return;
    }

    _cascade++;
    try {
      for (final sub in subs) {
        if (_spentThisTick >= maxTriggersPerTick) {
          budgetOverflows++;
          return;
        }
        _spentThisTick++;
        totalTriggers++;
        sub.listener(ctx);
      }
    } finally {
      _cascade--;
    }
  }

  bool get hasAnomalies => cascadeOverflows > 0 || budgetOverflows > 0;

  void resetDiagnostics() {
    cascadeOverflows = 0;
    budgetOverflows = 0;
    totalTriggers = 0;
  }
}
