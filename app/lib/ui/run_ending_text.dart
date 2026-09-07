import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/sim/descent.dart';

/// Исход спуска одним словом — для карточки на Заставе и заголовков.
/// Сам журнал живёт в `journal_screen.dart`.
///
/// Согласуется с наёмником там, где язык этого требует: половина имён в пуле
/// женские, и «Мирена Последняя погиб» — это ровно то «странное слово», на
/// которое пожаловался живой прогон. Английскому глагол по роду не
/// согласуется, и род там просто не спрашивается.
String endingWord(RunEnding ending, [Gender gender = Gender.masculine]) {
  final she = gender == Gender.feminine;

  return switch (ending) {
    RunEnding.death =>
      Phrase(she ? 'погибла' : 'погиб', 'fell').text,
    RunEnding.stalled => Phrase(
        she ? 'упёрлась в стену' : 'упёрся в стену', 'hit a wall').text,
    RunEnding.timeCap => Phrase(
        she ? 'вышло время' : 'вышло время',
        'out of time').text,
    RunEnding.floorCap => Phrase(
        she ? 'дошла до дна' : 'дошёл до дна',
        'reached the bottom').text,
    RunEnding.recalled =>
      Phrase(she ? 'отозвана' : 'отозван', 'called back').text,
    // Спуск не кончился — наёмник стоит на развилке. Слово в настоящем
    // времени намеренно: остальные исходы уже случились, этот происходит.
    RunEnding.atFork => const Phrase('на развилке', 'at a fork').text,
  };
}
