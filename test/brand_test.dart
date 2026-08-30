import 'dart:convert';

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Клеймо Бездны (GDD §2.5) — добровольная сложность: мобы крепче, добычи и
/// Эха больше. Размен намеренно почти нейтральный, поэтому проверяется не
/// «стало лучше», а что рычаг вообще действует и что его нельзя выкрутить
/// дальше заслуженного.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('открытие рангов', () {
    test('ранг открывается достижением глубины, а не покупкой', () {
      // Глубины берутся из контента: это баланс, и он двигается вместе с
      // остальными кривыми. Тест держит ПРАВИЛО — «ранг открывает глубина, и
      // ни один не даётся раньше своего порога», — а не конкретные числа.
      final depths = Curves.brandUnlockDepths;

      expect(Curves.brandRankUnlocked(0), 0);
      for (var i = 0; i < depths.length; i++) {
        expect(Curves.brandRankUnlocked(depths[i] - 1), i,
            reason: 'на этаж раньше порога ранг ещё закрыт');
        expect(Curves.brandRankUnlocked(depths[i]), i + 1);
      }
      expect(Curves.brandRankUnlocked(999999), Curves.brandRanksByDepth,
          reason: 'рекордом выше списка глубин ранги не открываются');
    });

    test('видно, до чего осталось дойти', () {
      final depths = Curves.brandUnlockDepths;

      expect(Curves.brandNextUnlockDepth(0), depths.first);
      expect(Curves.brandNextUnlockDepth(depths.first), depths[1]);
      expect(Curves.brandNextUnlockDepth(depths.last), isNull,
          reason: 'дальше списка рекордом ничего не открывается');
    });
  });

  group('выставление', () {
    test('незаработанный ранг не ставится', () {
      // Молча обрезать его значило бы соврать игроку о том, на чём он пошёл.
      // Рекорд ровно на первом пороге: открыт первый ранг и ни одним больше.
      final p = PlayerProfile(maxDepthEver: Curves.brandUnlockDepths.first);

      expect(p.brandRankUnlocked, 1);
      expect(p.setBrandRank(2), isFalse);
      expect(p.brandRank, 0);

      expect(p.setBrandRank(1), isTrue);
      expect(p.brandRank, 1);
    });

    test('потерянный ранг не остаётся выставленным', () {
      // Рекорд не падает, но контент может: если порог поднимут патчем,
      // сейв не должен продолжать спускаться на ранге, которого больше нет.
      final p = PlayerProfile(maxDepthEver: 125, brandRank: 5);
      expect(p.brandRank, 5);

      final reset = PlayerProfile(maxDepthEver: 0, brandRank: 5);
      expect(reset.brandRank, 0);
    });

    test('Клеймо уходит в контракт снимком', () {
      final p = _veteran(maxDepth: 60, seed: 1)..setBrandRank(2);

      final contract = p.deploy(p.roster.reserve.first, seed: 4);
      expect(contract.brandRank, 2);
      expect(contract.result!.maxDepth, greaterThan(0));
    });
  });

  test('Клеймо действует: мобы крепче, Эха больше', () {
    // Если строки сходятся, рычаг косметический.
    final plain = _veteran(maxDepth: 125, seed: 2);
    final branded = _veteran(maxDepth: 125, seed: 2)..setBrandRank(5);

    // Спуск считается отрезками до развилок; при отправке готов только первый,
    // и на нём Клеймо ещё не успевает сказаться — два этажа одинаковы с ним и
    // без него. Сравнивать надо законченные спуски.
    final far = DateTime.now().toUtc().add(const Duration(days: 1));
    final ca = plain.deploy(plain.roster.reserve.first, seed: 77);
    final cb = branded.deploy(branded.roster.reserve.first, seed: 77);
    plain.refreshContracts(far);
    branded.refreshContracts(far);

    final a = ca.result!;
    final b = cb.result!;

    expect(b.maxDepth, lessThan(a.maxDepth),
        reason: 'мобы крепче — глубина ниже');

    // Награду сравниваем на ОДНОЙ глубине: Эхо растёт по экспоненте, и
    // делить его на достигнутый этаж бессмысленно — брендованный ран просто
    // не дошёл туда же.
    const depth = 50;
    expect(Curves.echo(depth, brandRank: 5),
        greaterThan(Curves.echo(depth) * 1.5),
        reason: 'Эхо за тот же этаж выше');
    expect(Curves.goldPerFloor(depth, brandRank: 5),
        greaterThan(Curves.goldPerFloor(depth)),
        reason: 'добычи за тот же этаж больше');
  });

  test('Клеймо переживает сейв', () {
    // Рекорд ровно на третьем пороге: открыто три ранга, третий и выставлен.
    final p = PlayerProfile(maxDepthEver: Curves.brandUnlockDepths[2])
      ..setBrandRank(3);

    final loaded = SaveData.decode(
      SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: p).encode(),
    );

    expect(loaded.profile.brandRank, 3);
    expect(loaded.profile.brandRankUnlocked, 3);
  });

  test('сейв без Клейма открывается нулевым рангом', () {
    // Старые сейвы поля не знают, и это правда: они игрались на нуле.
    final p = PlayerProfile(maxDepthEver: 80);
    final raw = jsonDecode(
      SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: p).encode(),
    ) as Map<String, dynamic>;
    (raw['profile'] as Map).remove('brandRank');

    final loaded = SaveData.decode(jsonEncode(raw));
    expect(loaded.profile.brandRank, 0);
  });

  group('лестница эндгейма', () {
    test('выше списка глубин ранг открывает дело, а не рекорд', () {
      // Глубина выходит на плато (замер `--campaign 50`), и привязать к ней
      // лестницу нельзя: рекорд больше не растёт, а сложность — может.
      final byDepth = Curves.brandRanksByDepth;
      final profile = PlayerProfile(maxDepthEver: 100000);

      expect(profile.brandRankUnlocked, byDepth,
          reason: 'рекорд открывает ровно столько, сколько обещал список');

      profile.bestDepthByBrand[byDepth] = Curves.brandProofDepth;
      expect(profile.brandRankUnlocked, byDepth + 1,
          reason: 'доказанный ранг открывает следующий');
    });

    test('недоказанный ранг не открывает следующий', () {
      final byDepth = Curves.brandRanksByDepth;
      final profile = PlayerProfile(maxDepthEver: 100000);

      profile.bestDepthByBrand[byDepth] = Curves.brandProofDepth - 1;
      expect(profile.brandRankUnlocked, byDepth);
    });

    test('доказательство записывается при заборе добычи', () {
      final p = _veteran(maxDepth: 125, seed: 11)..setBrandRank(2);
      final contract = p.deploy(p.roster.reserve.first, seed: 4);
      // Глубина читается ПОСЛЕ окончания спуска: при отправке посчитан только
      // отрезок до первой развилки.
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      final depth = contract.result!.maxDepth;
      p.collect(contract);

      expect(p.bestDepthByBrand[2], depth,
          reason: 'ранг помнит лучшую глубину, взятую на нём');
    });

    test('каждый доказанный ранг даёт очко дерева пассивок', () {
      // То, ради чего лестница существует: на плато расти больше нечему.
      final profile = PlayerProfile(maxDepthEver: 150);
      final before = profile.passivePoints;

      profile.bestDepthByBrand[1] = Curves.brandProofDepth;
      profile.bestDepthByBrand[2] = Curves.brandProofDepth;

      expect(profile.provenBrandRanks, 2);
      expect(profile.passivePoints, before + 2);
    });

    test('лестница переживает сейв', () {
      final profile = PlayerProfile(maxDepthEver: 150);
      profile.bestDepthByBrand[3] = 140;

      final loaded = SaveData.decode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
            .encode(),
      );

      expect(loaded.profile.bestDepthByBrand[3], 140);
      expect(loaded.profile.provenBrandRanks, 1);
    });

    test('видно, чем открывается следующий ранг', () {
      final young = PlayerProfile(maxDepthEver: 10);
      expect(young.nextBrandRequirement?.atBrand, isNull,
          reason: 'сначала держит рекорд');

      final veteran = PlayerProfile(maxDepthEver: 100000);
      final need = veteran.nextBrandRequirement;
      expect(need?.atBrand, Curves.brandRanksByDepth,
          reason: 'дальше держит недоказанный ранг');
      expect(need?.depth, Curves.brandProofDepth);
    });
  });
}

/// Профиль игрока, который уже ходил глубоко: рекорд задаётся конструктором,
/// потому что снаружи он растёт только забором добычи.
PlayerProfile _veteran({required int maxDepth, required int seed}) {
  final profile = PlayerProfile(maxDepthEver: maxDepth, gold: 10000);
  final rng = Rng.stream(seed, 0, 0, RngPurpose.tavern);
  profile.roster.reserve
      .add(MercFactory.roll(rng, tavernLevel: 0, idPrefix: 'brand$seed'));
  return profile;

}