import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Канал наблюдения — единственное место, где показ трогает симуляцию.
/// Проверяется ровно одно: не трогает.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  RunResult run(int seed, {CombatFeed? feed}) {
    final driver = DescentDriver(
      profile: HeroProfile(),
      seed: seed,
      feed: feed,
    );
    while (!driver.finished) {
      driver.tick();
      // Наблюдатель забирает записи каждый кадр — иначе накопитель растёт
      // весь ран, и «не влияет» перестаёт быть правдой хотя бы по памяти.
      feed?.drain();
    }
    return driver.result;
  }

  test('бой не идёт иначе оттого, что на него смотрят', () {
    // Шину событий подписывать было нельзя: у неё бюджет срабатываний на тик,
    // и лишний слушатель отнимал бы его у чьего-то триггера. Здесь это
    // проверяется на результате целого спуска.
    for (final seed in [1, 7, 12345, 99991]) {
      final silent = run(seed);
      final watched = run(seed, feed: CombatFeed());

      expect(watched.maxDepth, silent.maxDepth, reason: 'сид $seed: глубина');
      expect(watched.ending, silent.ending, reason: 'сид $seed: исход');
      expect(watched.totalSeconds, silent.totalSeconds,
          reason: 'сид $seed: время');
      expect(watched.gold, silent.gold, reason: 'сид $seed: золото');
      expect(watched.echo, silent.echo, reason: 'сид $seed: эхо');
      expect(watched.itemsFound, silent.itemsFound,
          reason: 'сид $seed: находки');
      expect(watched.haul.itemCount, silent.haul.itemCount,
          reason: 'сид $seed: рюкзак');
      expect(watched.killedBy, silent.killedBy, reason: 'сид $seed: убийца');
    }
  });

  test('записывается то, что видно в бою', () {
    final feed = CombatFeed(capacity: 100000);
    final driver = DescentDriver(
      profile: HeroProfile(),
      seed: 42,
      recordFloors: false,
      floorCap: 1,
      feed: feed,
    );
    while (!driver.finished) {
      driver.tick();
    }

    final kinds = feed.drain().map((b) => b.kind).toSet();
    expect(kinds, contains(BeatKind.heroSwing));
    expect(kinds, contains(BeatKind.enemyHit));
    expect(kinds, contains(BeatKind.enemyDied));
  });

  test('смерть моба названа по имени прямо в записи', () {
    // Наблюдатель забирает записи кадром позже, и к тому моменту волны может
    // уже не быть: экран показывал «„“ пал» с пустым именем. Запись обязана
    // быть самодостаточной.
    final feed = CombatFeed(capacity: 100000);
    final driver = DescentDriver(
      profile: HeroProfile(),
      seed: 3,
      recordFloors: false,
      floorCap: 1,
      feed: feed,
    );
    while (!driver.finished) {
      driver.tick();
    }

    final deaths =
        feed.drain().where((b) => b.kind == BeatKind.enemyDied).toList();
    expect(deaths, isNotEmpty);
    for (final beat in deaths) {
      expect(beat.name, isNotEmpty, reason: '$beat');
    }
  });

  test('удар всегда указывает на моба из волны', () {
    // Индекс — это то, по чему сцена находит фигуру. Промах по индексу
    // подсветил бы соседа, и попадания читались бы как случайные вспышки.
    final feed = CombatFeed(capacity: 100000);
    final driver = DescentDriver(
      profile: HeroProfile(),
      seed: 5,
      recordFloors: false,
      floorCap: 3,
      feed: feed,
    );
    while (!driver.finished) {
      driver.tick();
    }

    var waveSize = 0;
    var checked = 0;
    for (final beat in feed.drain()) {
      switch (beat.kind) {
        case BeatKind.waveStarted:
          waveSize = beat.amount.round();
          expect(waveSize, greaterThan(0));
        case BeatKind.heroSwing:
        case BeatKind.enemyHit:
        case BeatKind.enemyDied:
        case BeatKind.heroHurt:
          expect(beat.index, greaterThanOrEqualTo(0), reason: '$beat');
          expect(beat.index, lessThan(waveSize),
              reason: '$beat: волна из $waveSize');
          checked++;
        case BeatKind.heroCast:
          expect(beat.id, isNotEmpty);
        case BeatKind.heroDied:
          break;
      }
    }
    expect(checked, greaterThan(0));
  });

  group('накопитель', () {
    test('забранное не выдаётся дважды', () {
      // Иначе один удар анимируется каждый кадр, пока идёт бой.
      final feed = CombatFeed()..add(const CombatBeat(BeatKind.heroSwing));
      expect(feed.drain(), hasLength(1));
      expect(feed.drain(), isEmpty);
    });

    test('переполнение теряет старое, а не новое', () {
      // Наблюдатель догоняет спуск тысячами тиков за кадр: показывать надо
      // последнее, что случилось, а не первое.
      final feed = CombatFeed(capacity: 4);
      for (var i = 0; i < 20; i++) {
        feed.add(CombatBeat(BeatKind.enemyHit, index: i));
      }

      final beats = feed.drain();
      expect(beats, hasLength(4));
      expect(beats.map((b) => b.index), [16, 17, 18, 19]);
    });
  });
}
