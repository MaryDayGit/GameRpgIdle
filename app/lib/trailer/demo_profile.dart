import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/rng.dart';

/// Застава, в которой уже жили.
///
/// Снимать трейлер с чистого листа нельзя: пустой сундук, один Оборванец и
/// ноль золота показывают не игру, а её первую минуту. Профиль для съёмки
/// прогоняется НАСТОЯЩЕЙ кампанией — тем же циклом, которым балансировщик
/// меряет прогрессию, — поэтому в кадр попадает то, что игра выдаёт сама, а
/// не красивые числа, выставленные руками. Показать в трейлере то, чего игра
/// не выдаёт, — это обещание, за которое платит первый же скачавший.
///
/// Сид фиксирован. Дубль, снятый завтра, обязан показать ту же Заставу, что
/// снятый сегодня: иначе неудачный кусок нельзя переснять, можно только
/// перемонтировать весь ролик.
abstract final class DemoProfile {
  /// Порядок вложений в Заставу. Тот же, что у балансировщика: сначала то,
  /// что кормит цикл (Таверна, Оружейная), потом то, что его углубляет.
  static const _buildOrder = [
    Building.tavern,
    Building.armory,
    Building.vault,
    Building.campfire,
    Building.altar,
    Building.forge,
    Building.cartographer,
    Building.shardBench,
  ];

  /// Профиль после [runs] спусков.
  ///
  /// Четырнадцать — не круглое число, а найденное: на десяти сундук ещё
  /// наполовину пуст, на двадцати Клеймо уводит глубину туда, где подписи
  /// в кадре перестают помещаться в строку.
  static PlayerProfile build({int seed = 20260907, int runs = 14}) {
    final player = PlayerProfile();

    // Стартовый наёмник выдаётся даром — как и живому игроку, которому иначе
    // нечем начать.
    player.roster.reserve.add(Mercenary(
      id: 'starter',
      name: 'Corwin the Rusted',
      rank: MercRank.ragged,
      trait: MercTrait.hardy,
    ));

    for (var i = 0; i < runs; i++) {
      final rng = Rng.stream(seed, i, 0, RngPurpose.offline);

      // 1. Таверна. Живой игрок жмёт обновление, пока не увидит того, кого
      // может позволить; автоматика обязана вести себя так же, иначе она
      // упирается в тупик, которого в игре нет.
      List<Mercenary> affordable() => player.tavernCandidates
          .where((m) => player.hireCostOf(m) <= player.gold)
          .toList()
        ..sort((a, b) => b.rank.index.compareTo(a.rank.index));

      player.refreshTavern(rng);
      var rerolls = 0;
      while (affordable().isEmpty && ++rerolls <= 20) {
        player.refreshTavern(rng);
      }
      final pool = affordable();
      if (pool.isNotEmpty) player.hire(pool.first);
      if (player.roster.reserve.isEmpty) break;

      // 2. Вниз идёт лучший из резерва, по лестнице Клейма.
      player.roster.reserve
          .sort((a, b) => b.rank.index.compareTo(a.rank.index));
      final merc = player.roster.reserve.first;
      player.setBrandRank(player.brandRankUnlocked);
      final contract = player.deploy(merc, seed: seed + i * 7919);

      // 3. Спуск проходится до конца. Развилки отвечает присутствующий
      // игрок: трейлер снимается про того, кто в игре, а не про того, кто
      // оставил приказ и ушёл.
      _finish(player, contract);
      player.collect(contract);
      player.autoSortLoot();
      player.autoSpendEcho();

      // 4. Золото вкладывается в Заставу, но с резервом на следующий задаток:
      // иначе Застава растёт, а вниз идти некому.
      for (final b in _buildOrder) {
        while (player.gold -
                    Roster.hireCost(MercRank.blade,
                        maxDepthEver: player.maxDepthEver) >
                player.outpost.upgradeCost(b) &&
            player.canUpgradeBuilding(b)) {
          if (!player.upgradeBuilding(b)) break;
        }
      }
    }

    // Резерв под съёмку: отправку показывать не на ком, если последний
    // наёмник ушёл вниз в последнем прогоне. Двое — чтобы список наёмников
    // в кадре был списком, а не одной строкой.
    _refillRoster(player, seed);

    return player;
  }

  /// Доводит спуск до конца, отвечая на каждой развилке.
  static void _finish(PlayerProfile player, Contract contract) {
    var now = contract.startedAtUtc;
    var guard = 0;
    while (guard++ < 500) {
      now = contract.segmentEndsAtUtc!.add(const Duration(seconds: 1));
      player.refreshContracts(now);
      if (!contract.atFork) break;
      if (!player.chooseFork(contract, Fork.boldIndex, now)) break;
    }
    // Сутки сверх — добить контракт, если наёмник встал не на развилке.
    player.refreshContracts(now.add(const Duration(days: 1)));
  }

  static void _refillRoster(PlayerProfile player, int seed) {
    var guard = 0;
    while (player.roster.reserve.length < 2 && guard++ < 40) {
      player.refreshTavern(Rng.stream(seed, 900 + guard, 0, RngPurpose.offline));
      final pool = player.tavernCandidates
          .where((m) => player.hireCostOf(m) <= player.gold)
          .toList()
        ..sort((a, b) => b.rank.index.compareTo(a.rank.index));
      if (pool.isEmpty) break;
      player.hire(pool.first);
    }
  }
}
