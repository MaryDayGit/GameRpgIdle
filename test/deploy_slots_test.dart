import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Второй слот спуска.
///
/// Это не удобство, а удвоение числа решений: игрок собирает два разных
/// билда и выбирает, кого куда послать. Открывает его Таверна — значит слот
/// это цель, а не покупка.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  PlayerProfile playerWith({required int tavern, int mercs = 2}) {
    final profile = PlayerProfile(
      outpost: Outpost({Building.tavern: tavern}),
      maxDepthEver: 200,
      gold: 1e6,
    );
    for (var i = 0; i < mercs; i++) {
      profile.roster.reserve
          .add(MercFactory.roll(Rng(i + 1), idPrefix: 'slot$i'));
    }
    return profile;
  }

  test('пока Таверна низкая, слот один', () {
    final profile = playerWith(tavern: Tuning.secondSlotLevel - 1);

    expect(profile.deploySlots, 1);
    expect(profile.canDeploy, isTrue);

    profile.deploy(profile.roster.reserve.first, seed: 1);
    expect(profile.canDeploy, isFalse,
        reason: 'второй наёмник ждёт, пока вернётся первый');
  });

  test('Таверна открывает второй слот', () {
    final profile = playerWith(tavern: Tuning.secondSlotLevel);
    expect(profile.deploySlots, 2);

    final first = profile.roster.reserve.first;
    final second = profile.roster.reserve.last;
    expect(first, isNot(same(second)));

    profile.deploy(first, seed: 1);
    expect(profile.canDeploy, isTrue, reason: 'второй слот свободен');

    profile.deploy(second, seed: 2);
    expect(profile.canDeploy, isFalse);
    expect(profile.roster.deployed, hasLength(2));
  });

  test('два спуска идут независимо', () {
    // Каждый контракт — свой сид, своя добыча, свой снимок Заставы. Если бы
    // они делили состояние, второй наёмник приносил бы добычу первого.
    final profile = playerWith(tavern: Tuning.secondSlotLevel);

    final a = profile.deploy(profile.roster.reserve.first, seed: 11);
    final b = profile.deploy(profile.roster.reserve.first, seed: 22);

    // Спуски доводятся до конца: при отправке посчитан только отрезок до
    // первой развилки, а два первых этажа у разных сидов вполне могут
    // совпасть — сравнивать надо целые раны.
    profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

    expect(a.seed, isNot(b.seed));
    expect(profile.contracts, hasLength(2));

    // Глубина квантуется этажами и у одинаковых билдов может совпасть —
    // сравнивать надо то, что непрерывно и принадлежит конкретному рану.
    expect(a.result!.haul, isNot(same(b.result!.haul)));
    expect(
      a.result!.totalSeconds != b.result!.totalSeconds ||
          a.result!.gold != b.result!.gold,
      isTrue,
      reason: 'разные сиды обязаны дать разные раны',
    );
  });

  test('добыча забирается по одному контракту', () {
    final profile = playerWith(tavern: Tuning.secondSlotLevel);
    final a = profile.deploy(profile.roster.reserve.first, seed: 5);
    final b = profile.deploy(profile.roster.reserve.first, seed: 6);

    profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
    profile.collect(a);

    expect(profile.contracts, hasLength(1),
        reason: 'закрыт только первый контракт');
    expect(profile.contracts.single, same(b));
    expect(profile.canDeploy, isTrue, reason: 'слот освободился');
  });

  test('слот нельзя занять сверх открытого', () {
    final profile = playerWith(tavern: Tuning.secondSlotLevel, mercs: 3);
    profile.deploy(profile.roster.reserve.first, seed: 1);
    profile.deploy(profile.roster.reserve.first, seed: 2);

    expect(profile.canDeploy, isFalse);
    expect(
      () => profile.deploy(profile.roster.reserve.first, seed: 3),
      throwsA(isA<StateError>()),
      reason: 'молча проглотить отправку значило бы потерять наёмника',
    );
  });
}
