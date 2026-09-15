import 'dart:math' as math;

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/echo_tree.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/codec.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Отзвук глубины (GDD §8.3.1, раунд 40).
///
/// К тридцать пятому контракту древо выкуплено, а спуск приносит миллиарды
/// Эха. Бесконечный узел обязан три вещи: открываться только за древом,
/// продолжать его лестницу цен и умножать силу так же, как ранг.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  List<String> allNodes() => [
        for (final branch in ContentPack.current.echoTree)
          for (final node in branch.nodes) node.id,
      ];

  test('закрыт, пока древо не выкуплено', () {
    final tree = EchoTree(bought: allNodes().skip(1));
    expect(tree.resonanceOpen, isFalse);
    expect(tree.buyResonance(1 << 60), isNull);
    expect(tree.resonance, 0);
  });

  test('первый уровень продолжает лестницу цен древа', () {
    final tree = EchoTree(bought: allNodes());
    expect(tree.resonanceOpen, isTrue);
    expect(tree.resonanceCost, closeTo(tree.nextNodeCost, 1e-6),
        reason: 'столько стоил бы следующий узел, будь он в древе');

    final first = tree.resonanceCost;
    final left = tree.buyResonance(first.ceil() + 10);
    expect(left, isNotNull);
    expect(tree.resonance, 1);
    expect(tree.resonanceCost,
        closeTo(first * Curves.echoResonanceCostGrowth, first * 1e-9));
  });

  test('множит силу наёмника, как ранг', () {
    HeroProfile hero(int resonance) => HeroProfile(
          tree: EchoTree(bought: allNodes(), resonance: resonance),
        );

    final base = hero(0).aggregate();
    final boosted = hero(10).aggregate();
    final k = EchoTree(resonance: 10).resonanceMultiplier;

    expect(k,
        closeTo(math.pow(1.0 + Curves.echoResonancePower, 10), 1e-12),
        reason: 'умножает, а не прибавляет: каждый уровень весит одинаково');
    expect(boosted.maxHp, closeTo(base.maxHp * k, 1e-6));
    expect(boosted.attackDamage, closeTo(base.attackDamage * k, 1e-6));
    expect(boosted.resistFire, base.resistFire,
        reason: 'сопротивления — доли, их множитель силы не трогает');
  });

  test('уровень входит в снимок контракта и в сейв', () {
    final profile = PlayerProfile(maxDepthEver: 40)
      ..tree.resonance = 0;
    for (final id in allNodes()) {
      profile.echo = 1 << 40;
      profile.tree.buy(id, profile.echo);
    }
    profile.tree.resonance = 7;
    final merc = MercFactory.roll(Rng(3));
    profile.roster.reserve.add(merc);

    final contract = profile.deploy(merc, seed: 1,
        now: DateTime.utc(2026, 9, 15));
    expect(contract.echoResonance, 7);
    expect(contract.replayProfile().tree!.resonance, 7);

    final loaded = SaveCodec.decodeProfile(
        SaveCodec.encodeProfile(profile), SaveIssues());
    expect(loaded.tree.resonance, 7);
    expect(loaded.contracts.single.echoResonance, 7);
  });

  test('автоматика вкладывает остаток Эха в Отзвук', () {
    final profile = PlayerProfile(tree: EchoTree(bought: allNodes()));
    profile.echo = (profile.tree.resonanceCost * 10).ceil();

    profile.autoSpendEcho();
    expect(profile.tree.resonance, greaterThan(1));
    expect(profile.echo, lessThan(profile.tree.resonanceCost));
  });
}
