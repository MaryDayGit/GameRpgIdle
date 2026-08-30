import '../balance/curves.dart';
import '../sim/rng.dart';
import 'tags.dart';

/// Результат одного расчёта урона.
class DamageResult {
  const DamageResult(this.amount, {required this.crit, required this.type});

  final double amount;
  final bool crit;
  final DamageType type;
}

/// Мультипликативная корзина (`more`).
///
/// Живёт в бою, а не в StatBlock: эти множители ситуативны (триггеры, пороги
/// HP, бафы). Разделение корзин `increased` / `more` — не косметика: без него
/// «+35 % урона Огнём» с шести источников либо ничего не значит,
/// либо ломает игру (GDD §3.3).
class MoreStack {
  final List<double> _values = [];

  void add(double fraction) => _values.add(fraction);

  void clear() => _values.clear();

  double get product {
    var p = 1.0;
    for (final v in _values) {
      p *= 1.0 + v;
    }
    return p;
  }

  bool get isEmpty => _values.isEmpty;
}

/// Формула урона (GDD §3.3).
///
/// raw    = (base + flatAdd) × (1 + Σ increased) × Π (1 + more)
/// crit   = × (1 + critMulti)
/// resist = × (1 − res/100), кап 75 %
/// armor  = × (1 − armor / (armor + 60 × 1.11^d_eff))
class DamageCalc {
  DamageCalc._();

  static DamageResult compute({
    required double base,
    required DamageType type,
    required Rng rng,
    double flatAdd = 0.0,
    double increased = 0.0,
    double more = 1.0,
    double critChance = 0.0,
    double critMulti = 0.0,
    double targetResist = 0.0,
    double targetArmor = 0.0,
    required int depth,
    bool canCrit = true,
    bool forceCrit = false,
  }) {
    var amount = (base + flatAdd) * (1.0 + increased) * more;

    // «Маска неизбежности»: крит не шанс, а правило. Бросок при этом всё
    // равно не делается — иначе поток случайности разъехался бы с повтором.
    final crit = canCrit && (forceCrit || (critChance > 0.0 && rng.chance(critChance)));
    if (crit) amount *= 1.0 + critMulti;

    final res = targetResist.clamp(double.negativeInfinity, Curves.resistCap);
    amount *= 1.0 - res / 100.0;

    amount *= 1.0 - Curves.armorMitigation(targetArmor, depth);

    return DamageResult(amount < 0.0 ? 0.0 : amount, crit: crit, type: type);
  }
}
