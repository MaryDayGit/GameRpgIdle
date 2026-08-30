import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Инвариант: у игрока всегда есть ход.
///
/// Новая игра начинается с нулём золота и одним бесплатным наёмником.
/// Единственный источник золота — добыча. Значит, отозванный на втором этаже
/// наёмник оставляет игрока без наёмников, без денег на самого дешёвого и
/// без способа заработать — игра кончилась, не сказав об этом.
///
/// Тест держит не отдельный симптом («отзыв на первом ране»), а само
/// состояние: нет наёмников, нет добычи, нет денег.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  test('без наёмников и без золота ход всё равно есть', () {
    final profile = PlayerProfile();

    expect(profile.isStranded, isTrue);
    final free = profile.volunteer;
    expect(free, isNotNull, reason: 'Таверна обязана дать добровольца');
    expect(profile.hireCostOf(free!), 0.0);
    expect(profile.tavernCandidates, contains(free));

    expect(profile.hire(free), isTrue);
    expect(profile.roster.reserve, contains(free));
    expect(profile.gold, 0.0, reason: 'даром — значит даром');
  });

  test('доброволец исчезает, как только наёмник есть', () {
    final profile = PlayerProfile.newGame(seed: 1);

    expect(profile.roster.reserve, isNotEmpty);
    expect(profile.isStranded, isFalse);
    expect(profile.volunteer, isNull);
    expect(profile.tavernCandidates, profile.roster.candidates);
  });

  test('пока добыча ждёт получения, доброволец не нужен', () {
    // Наёмник внизу (или уже погиб, но добыча не забрана) — ход у игрока
    // есть, и это не тот случай, ради которого доброволец существует.
    final profile = PlayerProfile.newGame(seed: 2);
    profile.deploy(profile.roster.reserve.first, seed: 5);

    expect(profile.roster.reserve, isEmpty);
    expect(profile.gold, 0.0);
    expect(profile.isStranded, isFalse, reason: 'наёмник ещё в контракте');
    expect(profile.volunteer, isNull);
  });

  test('доброволец не мигает: пока он нужен, он один и тот же', () {
    // Экран перестраивается каждый кадр. Доброволец, который каждый раз новый,
    // читался бы как поломка.
    final profile = PlayerProfile();
    final first = profile.volunteer!;

    expect(profile.volunteer!.id, first.id);
    expect(profile.volunteer!.name, first.name);
  });

  test('деньги есть — доброволец не появляется, а найм стоит своё', () {
    final profile = PlayerProfile(gold: 1000);
    profile.refreshTavern(Rng(3));

    expect(profile.isStranded, isFalse);
    expect(profile.volunteer, isNull);
    for (final candidate in profile.tavernCandidates) {
      expect(profile.hireCostOf(candidate), greaterThan(0.0));
    }
  });

  test('доброволец всегда Оборванец, даже при полной Таверне', () {
    // Иначе на восьмом уровне Таверны даром доставалась бы Легенда.
    final profile = PlayerProfile(
      outpost: Outpost({Building.tavern: Building.maxLevel}),
      maxDepthEver: 200,
    );

    expect(profile.volunteer!.rank, MercRank.ragged);
  });

  test('обеднеть можно и на двадцатом ране — доброволец придёт и там', () {
    // Состояние, а не «первый ран»: рекорд большой, задаток вырос, а золота
    // не осталось.
    final profile = PlayerProfile(maxDepthEver: 150);

    expect(profile.isStranded, isTrue);
    expect(profile.hireCostOf(profile.volunteer!), 0.0);
  });
}
