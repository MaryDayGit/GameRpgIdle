import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/descent.dart';

/// Повтор спуска, который сейчас идёт.
///
/// Ран посчитан целиком в момент отправки, и показывать «живой бой» второй
/// симуляцией нельзя: она разошлась бы с уже записанным результатом, и игрок
/// увидел бы бой, которого не было. Поэтому здесь ПОВТОР — тот же сид, тот же
/// снимок снаряжения, тот же тик за тиком. Симуляция детерминирована, значит
/// повтор совпадает с оригиналом побитово (проверяется в `contract_test`).
///
/// Перемотка только вперёд дешёвая: догнать десятую минуту спуска — это
/// несколько тысяч тиков, то есть единицы миллисекунд. Назад — пересборка
/// с нуля, и это нормально: назад смотрят редко.
class DescentReplay {
  DescentReplay({required this.contract}) {
    _rebuild();
  }

  final Contract contract;

  /// Канал наблюдения за боем. Симуляция в него только пишет — бой не имеет
  /// права идти иначе оттого, что открыт экран (`core/sim/combat_feed.dart`).
  final CombatFeed _feed = CombatFeed();

  late DescentDriver _driver;

  DescentDriver get driver => _driver;
  HeroState get hero => _driver.hero;
  DescentSnapshot get snapshot => _driver.snapshot;

  List<EnemyInstance> get enemies => _driver.wave?.enemies ?? const [];

  /// Игровых секунд отыграно, включая текущий этаж.
  double get position => _driver.elapsedSeconds;

  void _rebuild() {
    _driver = DescentDriver(
      profile: contract.replayProfile(),
      seed: contract.seed,
      brandRank: contract.brandRank,
      backpackCapacityOverride: contract.mercenary.backpackSlots,
      // Числа Заставы берутся из СНИМКА контракта, а не с сегодняшней
      // Заставы: постройки улучшаются, пока наёмник внизу, и повтор по
      // новым числам показал бы не тот бой, что уже записан.
      salvageRate: contract.outpost.salvageRate,
      outpostLootQuality: contract.outpost.lootQuality,
      outpostLootQuantity: contract.outpost.lootQuantity,
      restHealBonus: contract.outpost.restHealBonus,
      // Приказ на развилку меняет выбранные модификаторы, а с ними и весь
      // спуск. Повтор с политикой по умолчанию показал бы бой, которого
      // не было, — и заметить это можно было бы только глазами.
      forkPolicy: contract.forkPolicy,
      // Решения игрока на развилках — часть спуска, и повтор обязан их знать.
      // Без них экран боя показал бы спуск, которого не было: тот же сид и
      // тот же снимок, но другой путь на каждой развилке. Ровно тот случай,
      // когда два построения одного и того же расходятся.
      forkChoices: List.of(contract.forkChoices),
      // Наёмник, дошедший до неразрешённой развилки, СТОИТ. Без этого повтор
      // проходил развилку сам и уходил дальше: на Заставе было «ждёт решения
      // перед этажом 6», а на экране боя — десятый этаж. Условие то же, что
      // и в `PlayerProfile._simulateSegment`: бюджет ожидания потрачен —
      // наёмник больше не встаёт нигде.
      pauseAtUnchosenFork: !contract.forkWaitingSpent,
      // Разлом дня действует на каждом этаже. Повтор без него — это другой
      // спуск: другие волны, другие враги, другое здоровье.
      riftModifier: contract.riftModifier,
      recordFloors: false,
      feed: _feed,
    );
    _builtChoices = contract.forkChoices.length;
    _builtWaiting = contract.forkWaitingSpent;
    _feed.clear();
  }

  /// Сколько решений было учтено при построении повтора. Игрок выбирает путь,
  /// не выходя с экрана боя, и повтор, построенный до выбора, с этой секунды
  /// показывает уже не тот спуск.
  int _builtChoices = 0;
  bool _builtWaiting = false;

  /// Не разошёлся ли повтор с контрактом. Дешевле проверить два числа, чем
  /// объяснять игроку, почему бой на экране не тот, что в журнале.
  bool get _stale =>
      _builtChoices != contract.forkChoices.length ||
      _builtWaiting != contract.forkWaitingSpent;

  /// Отматывает повтор к моменту `target` игровых секунд от начала спуска.
  ///
  /// Считаем по часам драйвера, включающим текущий этаж. По времени
  /// ЗАВЕРШЁННЫХ этажей перемотка всегда попадала бы на их границу — то есть
  /// на начало первой волны, где герой только что отдохнул. Наблюдатель видел
  /// бы вечные 100 % здоровья и нулевой прогресс волны, что и происходило.
  void seekTo(double target) {
    if (_stale || target < _driver.elapsedSeconds) _rebuild();

    var guard = 0;
    var ticks = 0;
    while (!_driver.finished && _driver.elapsedSeconds < target) {
      _driver.tick();
      ticks++;
      // Предохранитель: спуск на сотни этажей — это миллионы тиков, и
      // подвесить кадр на них проще, чем кажется.
      if (++guard > 2000000) break;
    }

    // Догонялка — не бой на глазах игрока. Записи, накопленные за перемотку,
    // относятся к минутам, которые уже прошли: проиграть их анимацией значит
    // показать залп ударов, которых сейчас нет.
    if (ticks > _liveTicks) _feed.clear();
  }

  /// Сколько тиков за кадр ещё считается «идёт прямо сейчас». Кадр при
  /// нормальной скорости — это один-два тика; двадцать даёт запас на просадку
  /// частоты, но заведомо меньше перемотки.
  static const _liveTicks = 20;

  /// Забирает накопленные события боя. Именно забирает: анимация удара
  /// проигрывается один раз.
  List<CombatBeat> takeBeats() => _feed.drain();

  /// Отматывает к моменту `now` по реальным часам.
  ///
  /// Игровые секунды, а не разница дат: стоя на развилке, наёмник не проходит
  /// этажи, и минута раздумий игрока уносила бы повтор на минуту вперёд от
  /// того места, где наёмник на самом деле стоит.
  void seekToTime(DateTime now) => seekTo(contract.simSecondsAt(now));
}
