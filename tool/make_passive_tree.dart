import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:rift/core/content/passive_tree_def.dart';

/// Генератор дерева пассивок (`assets/content/passive_tree.json`).
///
/// Дерево описывается здесь, а не руками в JSON, по одной причине: у графа
/// есть геометрия. Шесть лучей по кругу, узлы на кольцах, перемычки между
/// соседними лучами — всё это в JSON пришлось бы расставлять координатами
/// вручную и переставлять при каждой правке. Здесь координаты считаются, а
/// правится СМЫСЛ: сколько колец, что в кластере, где перемычки.
///
///   dart run tool/make_passive_tree.dart
///
/// ## Три класса узлов, и это главное
///
/// Первая версия дерева состояла из одних процентов, а разменом с минусом был
/// каждый из двенадцати ключевых узлов. Живой прогон дал приговор: «дерево
/// странное и не глубокое, везде минуса, слабо чувствуется». Разбор:
/// прибавка к стату — это ползунок, а не выбор, потому что любой такой узел
/// заменяется любым другим той же величины; а размен, стоящий на каждом
/// конце, перестаёт быть событием.
///
/// Отсюда нынешнее устройство:
///
///  * **мелкий узел** (`stat`) — дорога. Его берут, чтобы пройти дальше;
///  * **крупный узел** (`notable`) — то, ради чего в ветку идут. Чистая
///    выгода без платы, и один в каждом кластере меняет ПРАВИЛО, а не число;
///  * **ключевой узел** (`keystone`) — ровно один на кластер, восемь на всё
///    дерево. Большой размен с настоящей платой. Их мало намеренно: размен
///    должен быть решением, а не рутиной.
void main(List<String> args) {
  final path = args.isEmpty ? 'assets/content/passive_tree.json' : args.first;

  final nodes = <Map<String, Object?>>[];
  final links = <List<String>>[];

  // Перемычки между лучами держим отдельно: экран рисует их дугой, а не
  // прямой. Прямая через сектор соседа выглядит как случайное пересечение —
  // именно это и было замечено в живом прогоне.
  final bridges = <List<String>>[];

  // Корень. Отсюда растёт всё: узел доступен, если сосед уже взят.
  nodes.add({
    'id': 'root',
    'ru': 'Наёмник',
    'text': 'Начало пути',
    'cluster': 'root',
    'kind': 'root',
    'x': 0,
    'y': 0,
  });

  for (var c = 0; c < _clusters.length; c++) {
    final cluster = _clusters[c];
    final angle = c * (2 * math.pi / _clusters.length) - math.pi / 2;

    String idAt(int ring, int branch) => '${cluster.id}_${ring}_$branch';

    for (var ring = 1; ring <= _rings; ring++) {
      // Первое кольцо — одна ветка, дальше расходится надвое, а с середины
      // втрое. Узлов в дереве должно быть заметно больше, чем очков: иначе
      // на потолке в 60 очков игрок берёт всё, и выбора снова нет.
      final branches = _branchesAt(ring);

      final step = _angularStep(ring, branches);

      for (var b = 0; b < branches; b++) {
        final theta = angle + (b - (branches - 1) / 2) * step;
        final radius = ring * _ringStep;

        final role = cluster.roleAt(ring, b);
        nodes.add({
          'id': idAt(ring, b),
          'ru': role.name,
          'text': role.text,
          'cluster': cluster.id,
          'kind': role.kind,
          if (role.stat != null) 'stat': role.stat,
          if (role.value != null) 'value': role.value,
          if (role.tag != null) 'tag': role.tag,
          if (role.penaltyStat != null) 'penaltyStat': role.penaltyStat,
          if (role.penalty != null) 'penalty': role.penalty,
          'icon': role.icon,
          if (role.rule != null) 'rule': role.rule,
          if (role.ruleValue != null) 'ruleValue': role.ruleValue,
          'x': _round(math.cos(theta) * radius),
          'y': _round(math.sin(theta) * radius),
        });

        // Связь с предыдущим кольцом: первое — с корнем, на развилках новые
        // ветки цепляются за ближайшую старую.
        if (ring == 1) {
          links.add(['root', idAt(ring, b)]);
        } else {
          final previous = _branchesAt(ring - 1);
          final parent = b.clamp(0, previous - 1);
          links.add([idAt(ring - 1, parent), idAt(ring, b)]);
        }
      }
    }

    // Перемычки к соседнему кластеру: без них восемь лучей — это восемь
    // отдельных линеек, а не дерево. Две штуки на разной высоте, чтобы
    // перейти можно было и рано, и поздно.
    final next = _clusters[(c + 1) % _clusters.length];
    for (final ring in _bridgeRings) {
      final last = _branchesAt(ring) - 1;
      bridges.add(['${cluster.id}_${ring}_$last', '${next.id}_${ring}_0']);
    }
  }

  final json = const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    '_comment': [
      'Сгенерировано `dart run tool/make_passive_tree.dart` — правьте генератор,',
      'а не этот файл. Координаты нужны экрану: дерево рисуется графом.',
      '',
      'kind=stat     -> дорога: мелкая прибавка к собранному билду;',
      'kind=notable  -> то, ради чего идут в ветку. Без платы; один на кластер',
      '                 меняет правило, а не число;',
      'kind=keystone -> размен: большой плюс и настоящая плата. Ровно один на',
      '                 кластер, восемь на всё дерево;',
      'kind=root     -> точка входа, ничего не даёт.',
    ],
    'nodes': nodes,
    'links': [
      for (final l in links) {'from': l[0], 'to': l[1]},
      for (final l in bridges) {'from': l[0], 'to': l[1], 'bridge': true},
    ],
  });

  File(path).writeAsStringSync('$json\n');
  stdout.writeln('$path: ${nodes.length} узлов, '
      '${links.length + bridges.length} связей '
      '(перемычек ${bridges.length})');
}

/// Колец в каждом кластере.
///
/// Девять, а не семь: при потолке в 60 очков дерево из ста узлов выкупается
/// больше чем наполовину — это не выбор, а список покупок. Здесь узлов
/// вдвое больше очков, и дорога до конца луча стоит девяти шагов.
const _rings = 9;

/// Кольца, на которых кластеры сшиты перемычками.
const _bridgeRings = [3, 6];

const _ringStep = 84;

/// Сколько веток на кольце. Дерево расширяется к краю: у центра выбор
/// «в какой луч», у края — «какой конец луча».
int _branchesAt(int ring) {
  if (ring <= 1) return 1;
  if (ring <= 3) return 2;
  return 3;
}

/// Крупный узел на середине пути. Первая награда за то, что игрок пошёл в
/// этот луч, — и она приходит раньше, чем кончится терпение.
const _middleRing = 4;

/// Второй крупный узел: длинная дорога обязана окупаться и на середине
/// второй половины, иначе конец луча выглядит недостижимым.
const _secondRing = 7;

/// Сколько лучей в дереве. Числом, а не `_clusters.length`: константа
/// нужна геометрии до того, как список объявлен.
const int _clusterCount = 13;

/// Угловой шаг между соседними ветками одного луча.
///
/// ## Почему это считается длиной дуги, а не углом
///
/// Прежняя версия задавала разброс долей сектора: `sectorHalf * (0.10 + 0.28
/// * ring / rings)`. Доля сектора — это УГОЛ, а расстояние между кружками на
/// экране — длина дуги, то есть угол, умноженный на радиус. На девятом
/// кольце радиус в девять раз больше, чем на первом, и один и тот же угол
/// давал там просторный веер, а у центра — кашу: на втором кольце соседние
/// узлы стояли в 13 единицах друг от друга при радиусе кружка в 14.5. Кружки
/// пересекались почти целиком.
///
/// Живой прогон назвал это «ветки и ноды наезжают друг на друга».
///
/// ## Правило
///
/// Идеальная упаковка кольца — равномерная: все узлы кольца на одинаковом
/// угловом шаге `2π / n`. Тогда расстояние ВНУТРИ луча равно расстоянию
/// МЕЖДУ лучами, и теснее уже не сделать никак.
///
/// От равномерного шага отступаем в две стороны:
///
/// * **вниз** — поджимаем веер до [_fanTightening], чтобы между лучами была
///   видимая щель и дерево читалось как тринадцать ветвей, а не как решётка;
/// * **вверх** — но не теснее, чем позволяют сами кружки: шаг обязан дать
///   [_requiredGap] единиц дуги.
///
/// На внутренних кольцах побеждает второе ограничение (там места ровно
/// столько, сколько есть), на внешних — первое.
double _angularStep(int ring, int branches) {
  if (branches <= 1) return 0.0;

  final radius = (ring * _ringStep).toDouble();
  final uniform = 2 * math.pi / (_clusterCount * branches);
  final needed = _requiredGap(ring, branches) / radius;

  return math.max(uniform * _fanTightening, needed);
}

/// Насколько веер луча поджат относительно равномерной раскладки.
///
/// Единица — равномерная решётка без щелей между лучами. Ниже — видимая
/// щель, но и меньше места внутри луча.
const double _fanTightening = 0.82;

/// Сколько единиц дуги нужно между центрами соседних узлов кольца.
///
/// Считается из радиусов кружков, которыми их рисует экран, а не назначается:
/// число, взятое на глаз, разъезжается с рисованием при первой же правке
/// размеров. Пара «крупный + ключевой» на девятом кольце — самая толстая.
double _requiredGap(int ring, int branches) {
  var worst = 0.0;
  for (var b = 0; b + 1 < branches; b++) {
    final gap = _drawRadius(_kindAt(ring, b, branches)) +
        _drawRadius(_kindAt(ring, b + 1, branches)) +
        _nodeMargin;
    if (gap > worst) worst = gap;
  }
  return worst;
}

/// Радиус кружка В ЕДИНИЦАХ КОНТЕНТА.
///
/// Экран рисует узлы в пикселях и множит координаты на свой масштаб; здесь
/// делается обратное преобразование. Если размеры на экране изменятся, а
/// здесь нет — раскладка снова слипнется, поэтому валидатор контента
/// проверяет итоговые расстояния независимо от генератора.
double _drawRadius(String kind) => switch (kind) {
      'root' => 17.0 / _screenScale,
      'keystone' => 16.0 / _screenScale,
      'notable' => 13.0 / _screenScale,
      _ => 9.0 / _screenScale,
    };

/// Масштаб экрана дерева. Единственное определение — в ядре
/// (`passive_tree_def.dart`): по нему же считает проверка контента и рисует
/// экран. Своя копия здесь означала бы, что раскладка и проверка могут
/// разъехаться порознь.
const double _screenScale = treeScreenScale;

/// Просвет между кружками, в единицах контента (≈9 пикселей).
const double _nodeMargin = 14.0;

/// Какого класса узел стоит на этом месте. Повторяет решение `roleAt`, но
/// без содержимого: геометрия одна на все лучи, а наполнение у каждого своё.
String _kindAt(int ring, int branch, int branches) {
  if (ring == _rings) {
    if (branch == 2) return 'keystone';
    return 'notable';
  }
  if ((ring == _middleRing || ring == _secondRing) && branch == 1) {
    return 'notable';
  }
  return 'stat';
}

int _round(double v) => v.round();

/// Что за узел стоит на кольце.
class _Role {
  const _Role(
    this.name,
    this.text, {
    this.kind = 'stat',
    this.icon = 'dot',
    this.stat,
    this.value,
    this.penaltyStat,
    this.penalty,
    this.rule,
    this.ruleValue,
    this.tag,
  });

  final String name;
  final String text;
  final String kind;

  /// Что нарисовано в узле. Рисует клиент кодом — по той же причине, по
  /// которой рисуются силуэты мобов и иконки вещей: лицензии, вес пакета и
  /// второй источник истины.
  final String icon;
  final String? stat;
  final double? value;

  /// Тег для узлов на `tagDamage`. Без него такой узел молча не даёт ничего.
  final String? tag;
  final String? penaltyStat;
  final double? penalty;

  /// Правило вместо числа — то, ради чего билд строят.
  final String? rule;
  final double? ruleValue;
}

/// Кластер — луч дерева со своей темой.
class _Cluster {
  const _Cluster({
    required this.id,
    required this.smalls,
    required this.middle,
    required this.second,
    required this.notable,
    required this.ruleNotable,
    required this.keystone,
  });

  final String id;

  /// Мелкие узлы кластера. Их несколько, и они РАЗНЫЕ.
  ///
  /// Первая версия дерева ставила в луч один и тот же узел двадцать раз
  /// подряд — «+8 % к максимуму HP», «+8 % к максимуму HP», ещё восемнадцать
  /// раз. Живой прогон назвал это «не разнообразным», и он прав: одинаковые
  /// узлы — это не дорога, а счётчик.
  final List<_Role> smalls;

  /// Крупный узел на середине пути: первая награда за то, что игрок пошёл
  /// в этот луч, — и она приходит раньше, чем кончится терпение.
  final _Role middle;

  /// Второй крупный узел, дальше по лучу. Другой, а не тот же самый.
  final _Role second;

  /// Крупный узел на конце средней ветки.
  final _Role notable;

  /// Крупный узел, меняющий правило. Один на кластер: правило, стоящее на
  /// каждом шагу, перестаёт быть событием.
  final _Role ruleNotable;

  /// Единственный размен кластера.
  final _Role keystone;

  _Role roleAt(int ring, int branch) {
    // Конец луча: правило — налево, размен — направо, крупный узел — прямо.
    // Так у каждой ветки свой конец, и выбирать приходится не «сколько
    // процентов», а «чем этот билд будет отличаться».
    if (ring == _rings) {
      if (branch == 0) return ruleNotable;
      if (branch == 2) return keystone;
      return notable;
    }
    // Крупные узлы на середине — только на средней ветке: иначе на кольце
    // стояло бы три награды подряд и дорога перестала бы стоить очков.
    if (ring == _middleRing && branch == 1) return middle;
    if (ring == _secondRing && branch == 1) return second;

    // Мелкие узлы чередуются по кольцу и ветке: соседние узлы дороги
    // отличаются друг от друга, и луч читается как путь, а не как счётчик.
    return smalls[(ring + branch) % smalls.length];
  }
}

/// Восемь лучей. Темы намеренно пересекаются с тегами способностей и
/// аффиксов: дерево должно усиливать билд, который игрок уже собирает, а не
/// звать в отдельную игру.
///
/// В каждом луче три РАЗНЫХ мелких узла: они чередуются по кольцам, и дорога
/// читается как путь, а не как двадцать копий одного счётчика.
const _clusters = [
  _Cluster(
    id: 'flesh',
    smalls: [
      _Role('Жила', '+8 % к максимуму HP',
          icon: 'heart', stat: 'maxHpPct', value: 0.08),
      _Role('Плотная кожа', '+40 к максимуму HP',
          icon: 'hide', stat: 'maxHp', value: 40.0),
      _Role('Ровное дыхание', '+1.5 восстановления HP в секунду',
          icon: 'breath', stat: 'hpRegen', value: 1.5),
    ],
    middle: _Role('Второе сердце', '+20 % к максимуму HP',
        kind: 'notable', icon: 'heart', stat: 'maxHpPct', value: 0.20),
    second: _Role('Крепкие кости', '+120 к максимуму HP',
        kind: 'notable', icon: 'bone', stat: 'maxHp', value: 120.0),
    notable: _Role('Живучесть', '+26 % к максимуму HP',
        kind: 'notable', icon: 'heart', stat: 'maxHpPct', value: 0.26),
    ruleNotable: _Role(
      'Второе дыхание',
      'Убийство восстанавливает 2 % максимума HP',
      kind: 'notable',
      icon: 'drop',
      rule: 'killHeal',
      ruleValue: 0.02,
    ),
    keystone: _Role(
      'Кровь за силу',
      '+45 % к урону, но −30 % к максимуму HP',
      kind: 'keystone',
      icon: 'drop',
      stat: 'increasedDamage',
      value: 0.45,
      penaltyStat: 'maxHpPct',
      penalty: 0.30,
    ),
  ),
  _Cluster(
    id: 'stone',
    smalls: [
      _Role('Панцирь', '+10 % к броне',
          icon: 'shield', stat: 'armorPct', value: 0.10),
      _Role('Пластина', '+35 к броне',
          icon: 'plate', stat: 'armor', value: 35.0),
      _Role('Устойчивость', '+8 к сопротивлению пустоте',
          icon: 'ward', stat: 'resistVoid', value: 8.0),
    ],
    middle: _Role('Скала', '+24 % к броне',
        kind: 'notable', icon: 'shield', stat: 'armorPct', value: 0.24),
    second: _Role('Бастион', '+12 % к максимуму HP',
        kind: 'notable', icon: 'plate', stat: 'maxHpPct', value: 0.12),
    notable: _Role('Утёс', '+30 % к броне',
        kind: 'notable', icon: 'shield', stat: 'armorPct', value: 0.30),
    ruleNotable: _Role(
      'Каменная вера',
      '8 % брони считается сопротивлением всем стихиям',
      kind: 'notable',
      icon: 'ward',
      rule: 'armorToResist',
      ruleValue: 0.08,
    ),
    keystone: _Role(
      'Каменная кожа',
      '+70 % к броне, но −25 % к урону',
      kind: 'keystone',
      icon: 'plate',
      stat: 'armorPct',
      value: 0.70,
      penaltyStat: 'increasedDamage',
      penalty: 0.25,
    ),
  ),
  _Cluster(
    id: 'fang',
    smalls: [
      _Role('Клык', '+8 % к урону',
          icon: 'fang', stat: 'increasedDamage', value: 0.08),
      _Role('Заточка', '+14 к урону оружия',
          icon: 'blade', stat: 'attackDamage', value: 14.0),
      _Role('Хватка', '+7 % к урону Ударами',
          icon: 'claw', stat: 'tagDamage', value: 0.07, tag: 'strike'),
    ],
    middle: _Role('Хищник', '+20 % к урону',
        kind: 'notable', icon: 'fang', stat: 'increasedDamage', value: 0.20),
    second: _Role('Ярость', '+10 % к скорости атаки',
        kind: 'notable',
        icon: 'claw',
        stat: 'increasedAttackSpeed',
        value: 0.10),
    // Узел на теге, а не на общем «+% к урону»: луч Клыка — это оружейная
    // сборка, и у неё, как у стихий, должен быть свой множитель. Уже́ общего,
    // зато крупнее — в этом и состоит размен.
    notable: _Role('Свирепость', '+32 % к физическому урону',
        kind: 'notable', icon: 'blade', stat: 'tagDamage', value: 0.32,
        tag: 'physical'),
    ruleNotable: _Role(
      'Отчаяние',
      'Ниже половины здоровья вы бьёте на 25 % сильнее',
      kind: 'notable',
      icon: 'fang',
      rule: 'lowLifeDamage',
      ruleValue: 0.25,
    ),
    keystone: _Role(
      'Безрассудство',
      '+55 % к урону, но −35 % к броне',
      kind: 'keystone',
      icon: 'blade',
      stat: 'increasedDamage',
      value: 0.55,
      penaltyStat: 'armorPct',
      penalty: 0.35,
    ),
  ),
  _Cluster(
    id: 'spark',
    smalls: [
      _Role('Искра', '+2 % к шансу критического удара',
          icon: 'spark', stat: 'critChance', value: 0.02),
      _Role('Точность', '+15 % к урону критических ударов',
          icon: 'eye', stat: 'critMulti', value: 0.15),
      _Role('Взгляд', '+1.5 % к шансу критического удара',
          icon: 'eye', stat: 'critChance', value: 0.015),
    ],
    middle: _Role('Точный глаз', '+5 % к шансу критического удара',
        kind: 'notable', icon: 'eye', stat: 'critChance', value: 0.05),
    second: _Role('Хладнокровие', '+45 % к урону критических ударов',
        kind: 'notable', icon: 'spark', stat: 'critMulti', value: 0.45),
    notable: _Role('Смертельный расчёт', '+6 % к шансу критического удара',
        kind: 'notable', icon: 'eye', stat: 'critChance', value: 0.06),
    ruleNotable: _Role(
      'Охотник на медленных',
      'По замедленным целям удар всегда критический',
      kind: 'notable',
      icon: 'spark',
      rule: 'critVsSlowed',
      ruleValue: 1.0,
    ),
    keystone: _Role(
      'Жажда крови',
      '+90 % к урону критических ударов, но −30 % к скорости атаки',
      kind: 'keystone',
      icon: 'spark',
      stat: 'critMulti',
      value: 0.90,
      penaltyStat: 'increasedAttackSpeed',
      penalty: 0.30,
    ),
  ),
  _Cluster(
    id: 'wind',
    smalls: [
      _Role('Порыв', '+5 % к скорости атаки',
          icon: 'wind', stat: 'increasedAttackSpeed', value: 0.05),
      _Role('Лёгкость', '−4 % ко времени перезарядки',
          icon: 'feather', stat: 'cooldownReduction', value: 0.04),
      _Role('Ритм', '+7 % к урону Атаками',
          icon: 'wind', stat: 'tagDamage', value: 0.07, tag: 'attack'),
    ],
    middle: _Role('Вихрь', '+13 % к скорости атаки',
        kind: 'notable',
        icon: 'wind',
        stat: 'increasedAttackSpeed',
        value: 0.13),
    second: _Role('Сквозняк', '−15 % ко времени перезарядки',
        kind: 'notable',
        icon: 'feather',
        stat: 'cooldownReduction',
        value: 0.15),
    notable: _Role('Буря', '+16 % к скорости атаки',
        kind: 'notable',
        icon: 'wind',
        stat: 'increasedAttackSpeed',
        value: 0.16),
    ruleNotable: _Role(
      'Первый удар',
      'Первый удар по новой волне сильнее на 60 %',
      kind: 'notable',
      icon: 'feather',
      rule: 'firstStrike',
      ruleValue: 0.60,
    ),
    keystone: _Role(
      'Рваный ритм',
      '+35 % к скорости атаки, но −30 % к множителю крита',
      kind: 'keystone',
      icon: 'wind',
      stat: 'increasedAttackSpeed',
      value: 0.35,
      penaltyStat: 'critMulti',
      penalty: 0.30,
    ),
  ),
  _Cluster(
    id: 'mind',
    smalls: [
      _Role('Сосредоточенность', '+12 к максимуму маны',
          icon: 'mana', stat: 'maxMana', value: 12.0),
      _Role('Ясность', '+0.5 восстановления маны в секунду',
          icon: 'spiral', stat: 'manaRegen', value: 0.5),
      _Role('Медитация', '+18 к максимуму маны',
          icon: 'mana', stat: 'maxMana', value: 18.0),
    ],
    middle: _Role('Ясный ум', '+1 восстановления маны в секунду',
        kind: 'notable', icon: 'spiral', stat: 'manaRegen', value: 1.0),
    second: _Role('Глубокий сосуд', '+45 к максимуму маны',
        kind: 'notable', icon: 'mana', stat: 'maxMana', value: 45.0),
    notable: _Role('Поток мысли', '+1.5 восстановления маны в секунду',
        kind: 'notable', icon: 'spiral', stat: 'manaRegen', value: 1.5),
    ruleNotable: _Role(
      'Сила разума',
      '+1 % к урону за каждые 20 маны в запасе',
      kind: 'notable',
      icon: 'mana',
      rule: 'manaToDamage',
      ruleValue: 0.0005,
    ),
    keystone: _Role(
      'Расточительство',
      '−35 % ко времени перезарядки, но −60 к максимуму маны',
      kind: 'keystone',
      icon: 'spiral',
      stat: 'cooldownReduction',
      value: 0.35,
      penaltyStat: 'maxMana',
      penalty: 60.0,
    ),
  ),
  _Cluster(
    id: 'hunt',
    smalls: [
      _Role('Намётанный глаз', '+5 % к количеству добычи',
          icon: 'coin', stat: 'lootQuantity', value: 0.05),
      _Role('Кошель', '+12 % к находимому золоту',
          icon: 'purse', stat: 'goldFind', value: 0.12),
      _Role('Чутьё', '+4 % к качеству добычи',
          icon: 'gem', stat: 'lootQuality', value: 0.04),
    ],
    middle: _Role('Чутьё на золото', '+20 % к находимому золоту',
        kind: 'notable', icon: 'purse', stat: 'goldFind', value: 0.20),
    second: _Role('Знаток', '+15 % к качеству добычи',
        kind: 'notable', icon: 'gem', stat: 'lootQuality', value: 0.15),
    notable: _Role('Добытчик', '+18 % к количеству добычи',
        kind: 'notable', icon: 'coin', stat: 'lootQuantity', value: 0.18),
    ruleNotable: _Role(
      'Тяжёлая поступь',
      '4 % максимума HP считается бронёй',
      kind: 'notable',
      icon: 'plate',
      rule: 'hpToArmor',
      ruleValue: 0.04,
    ),
    keystone: _Role(
      'Мародёр',
      '+40 % к количеству добычи, но −25 % к максимуму HP',
      kind: 'keystone',
      icon: 'coin',
      stat: 'lootQuantity',
      value: 0.40,
      penaltyStat: 'maxHpPct',
      penalty: 0.25,
    ),
  ),
  _Cluster(
    id: 'leech',
    smalls: [
      _Role('Пиявка', '+0.8 % вампиризма',
          icon: 'leech', stat: 'leech', value: 0.008),
      _Role('Жажда', '+7 % к урону Кровью',
          icon: 'chalice', stat: 'tagDamage', value: 0.07, tag: 'blood'),
      _Role('Кровосток', '+1.2 восстановления HP в секунду',
          icon: 'breath', stat: 'hpRegen', value: 1.2),
    ],
    middle: _Role('Кровосос', '+2 % вампиризма',
        kind: 'notable', icon: 'leech', stat: 'leech', value: 0.02),
    second: _Role('Насыщение', '+2.5 % вампиризма',
        kind: 'notable', icon: 'chalice', stat: 'leech', value: 0.025),
    notable: _Role('Ненасытная кровь', '+3 % вампиризма',
        kind: 'notable', icon: 'leech', stat: 'leech', value: 0.03),
    ruleNotable: _Role(
      'Кровь на клинке',
      'Критический удар восстанавливает 1 % максимума HP',
      kind: 'notable',
      icon: 'chalice',
      rule: 'critHeal',
      ruleValue: 0.01,
    ),
    keystone: _Role(
      'Ненасытность',
      '+6 % вампиризма, но −30 % к максимуму HP',
      kind: 'keystone',
      icon: 'leech',
      stat: 'leech',
      value: 0.06,
      penaltyStat: 'maxHpPct',
      penalty: 0.30,
    ),
  ),
  // --- Стихии ----------------------------------------------------------------
  //
  // Пять лучей, которых в дереве не было вовсе. Живой прогон дал приговор:
  // «на вещах есть модификатор урона к огню, а умений огня нет, и строить
  // билд не с чего». Половина ответа — умения (их стало 55), вторая половина
  // здесь: тег усиливается тем, что игрок ВЫБИРАЕТ, а не тем, что выпало.
  //
  // Дерево — надёжный источник теговой силы, снаряжение — случайный.
  //
  // Проценты здесь ВДВОЕ крупнее общих «+% к урону», и это не щедрость, а
  // арифметика. Общий узел усиливает всё, включая автоатаку, которой наносится
  // львиная доля урона; теговый — только то, что несёт его тег. Замер `--tree`
  // на равных числах дал стихийным лучам +18 этажей против +33 у Клыка: узел
  // той же величины, но уже́ по охвату, — это узел, который никогда не берут.
  // То есть мёртвый контент, а не выбор.
  _Cluster(
    id: 'ember',
    smalls: [
      _Role('Уголёк', '+15 % к урону Огнём',
          icon: 'flame', stat: 'tagDamage', value: 0.15, tag: 'fire'),
      _Role('Жар', '+7 к сопротивлению огню',
          icon: 'ward', stat: 'resistFire', value: 7.0),
      _Role('Тлеющий след', '+13 % к длительному урону',
          icon: 'ember', stat: 'tagDamage', value: 0.13, tag: 'duration'),
    ],
    middle: _Role('Костёр', '+34 % к урону Огнём',
        kind: 'notable', icon: 'flame', stat: 'tagDamage', value: 0.34,
        tag: 'fire'),
    second: _Role('Горнило', '+26 % к урону Чарами',
        kind: 'notable', icon: 'rune', stat: 'tagDamage', value: 0.26,
        tag: 'spell'),
    notable: _Role('Пожарище', '+45 % к урону Огнём',
        kind: 'notable', icon: 'flame', stat: 'tagDamage', value: 0.45,
        tag: 'fire'),
    ruleNotable: _Role(
      'Тлеющий уголь',
      'Длительный урон на 35 % сильнее',
      kind: 'notable',
      icon: 'ember',
      rule: 'dotMoreDamage',
      ruleValue: 0.35,
    ),
    keystone: _Role(
      'Выжженная земля',
      '+130 % к урону Огнём, но −35 % к максимуму HP',
      kind: 'keystone',
      icon: 'flame',
      stat: 'tagDamage',
      value: 1.30,
      tag: 'fire',
      penaltyStat: 'maxHpPct',
      penalty: 0.35,
    ),
  ),
  _Cluster(
    id: 'frost',
    smalls: [
      _Role('Иней', '+15 % к урону Холодом',
          icon: 'snowflake', stat: 'tagDamage', value: 0.15, tag: 'cold'),
      _Role('Стужа', '+7 к сопротивлению холоду',
          icon: 'ward', stat: 'resistCold', value: 7.0),
      _Role('Ледяная крошка', '+13 % к урону Снарядами',
          icon: 'icicle', stat: 'tagDamage', value: 0.13, tag: 'projectile'),
    ],
    middle: _Role('Наст', '+34 % к урону Холодом',
        kind: 'notable', icon: 'snowflake', stat: 'tagDamage', value: 0.34,
        tag: 'cold'),
    second: _Role('Панцирь льда', '+14 % к броне',
        kind: 'notable', icon: 'icicle', stat: 'armorPct', value: 0.14),
    notable: _Role('Вечная мерзлота', '+45 % к урону Холодом',
        kind: 'notable', icon: 'snowflake', stat: 'tagDamage', value: 0.45,
        tag: 'cold'),
    ruleNotable: _Role(
      'Стылая хватка',
      'Ваши удары замедляют цель на 20 %',
      kind: 'notable',
      icon: 'icicle',
      rule: 'chillOnHit',
      ruleValue: 0.20,
    ),
    keystone: _Role(
      'Ледяное сердце',
      '+130 % к урону Холодом, но −30 % к скорости атаки',
      kind: 'keystone',
      icon: 'snowflake',
      stat: 'tagDamage',
      value: 1.30,
      tag: 'cold',
      penaltyStat: 'increasedAttackSpeed',
      penalty: 0.30,
    ),
  ),
  _Cluster(
    id: 'storm',
    smalls: [
      _Role('Статика', '+15 % к урону Молнией',
          icon: 'bolt', stat: 'tagDamage', value: 0.15, tag: 'lightning'),
      _Role('Заземление', '+7 к сопротивлению молнии',
          icon: 'ward', stat: 'resistLightning', value: 7.0),
      _Role('Гул', '+13 % к урону по области',
          icon: 'cloud', stat: 'tagDamage', value: 0.13, tag: 'area'),
    ],
    middle: _Role('Раскат', '+34 % к урону Молнией',
        kind: 'notable', icon: 'bolt', stat: 'tagDamage', value: 0.34,
        tag: 'lightning'),
    second: _Role('Ветер перед бурей', '−12 % ко времени перезарядки',
        kind: 'notable', icon: 'cloud', stat: 'cooldownReduction',
        value: 0.12),
    notable: _Role('Громовержец', '+45 % к урону Молнией',
        kind: 'notable', icon: 'bolt', stat: 'tagDamage', value: 0.45,
        tag: 'lightning'),
    ruleNotable: _Role(
      'Перескок',
      'Урон Молнией задевает вторую цель — на 35 % от нанесённого',
      kind: 'notable',
      icon: 'bolt',
      rule: 'shockSplash',
      ruleValue: 0.35,
    ),
    keystone: _Role(
      'Буревестник',
      '+130 % к урону Молнией, но −40 % к броне',
      kind: 'keystone',
      icon: 'cloud',
      stat: 'tagDamage',
      value: 1.30,
      tag: 'lightning',
      penaltyStat: 'armorPct',
      penalty: 0.40,
    ),
  ),
  _Cluster(
    id: 'abyss',
    smalls: [
      _Role('Шёпот', '+15 % к урону Пустотой',
          icon: 'rift', stat: 'tagDamage', value: 0.15, tag: 'voidTag'),
      _Role('Отрешённость', '+7 к сопротивлению пустоте',
          icon: 'ward', stat: 'resistVoid', value: 7.0),
      _Role('Дурной глаз', '+13 % к урону Проклятиями',
          icon: 'skull', stat: 'tagDamage', value: 0.13, tag: 'curse'),
    ],
    middle: _Role('Провал', '+34 % к урону Пустотой',
        kind: 'notable', icon: 'rift', stat: 'tagDamage', value: 0.34,
        tag: 'voidTag'),
    second: _Role('Немой зов', '+26 % к урону Тотемами',
        kind: 'notable', icon: 'skull', stat: 'tagDamage', value: 0.26,
        tag: 'totem'),
    notable: _Role('Голодная тьма', '+45 % к урону Пустотой',
        kind: 'notable', icon: 'rift', stat: 'tagDamage', value: 0.45,
        tag: 'voidTag'),
    ruleNotable: _Role(
      'Печать увядания',
      'По проклятым целям вы бьёте на 30 % сильнее',
      kind: 'notable',
      icon: 'skull',
      rule: 'curseMoreDamage',
      ruleValue: 0.30,
    ),
    keystone: _Role(
      'Пустой сосуд',
      '+130 % к урону Пустотой, но −45 к максимуму маны',
      kind: 'keystone',
      icon: 'rift',
      stat: 'tagDamage',
      value: 1.30,
      tag: 'voidTag',
      penaltyStat: 'maxMana',
      penalty: 45.0,
    ),
  ),
  _Cluster(
    id: 'arcane',
    smalls: [
      _Role('Наговор', '+15 % к урону Чарами',
          icon: 'rune', stat: 'tagDamage', value: 0.15, tag: 'spell'),
      _Role('Знание', '+3 к силе чар',
          icon: 'orb', stat: 'spellPower', value: 3.0),
      _Role('Шёпот строк', '+10 к максимуму маны',
          icon: 'mana', stat: 'maxMana', value: 10.0),
    ],
    middle: _Role('Формула', '+7 к силе чар',
        kind: 'notable', icon: 'orb', stat: 'spellPower', value: 7.0),
    second: _Role('Свод заклятий', '+30 % к урону Чарами',
        kind: 'notable', icon: 'rune', stat: 'tagDamage', value: 0.30,
        tag: 'spell'),
    notable: _Role('Высокое искусство', '+11 к силе чар',
        kind: 'notable', icon: 'orb', stat: 'spellPower', value: 11.0),
    ruleNotable: _Role(
      'Ум как сосуд',
      '+1 к силе чар за каждые 8 маны в запасе',
      kind: 'notable',
      icon: 'mana',
      rule: 'manaToSpellPower',
      ruleValue: 0.125,
    ),
    keystone: _Role(
      'Отречение от стали',
      '+145 % к урону Чарами, но −50 % к скорости атаки',
      kind: 'keystone',
      icon: 'rune',
      stat: 'tagDamage',
      value: 1.45,
      tag: 'spell',
      penaltyStat: 'increasedAttackSpeed',
      penalty: 0.50,
    ),
  ),
];

