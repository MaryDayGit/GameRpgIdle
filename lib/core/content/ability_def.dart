import '../model/stat_key.dart';
import '../model/tags.dart';
import 'json_node.dart';
import 'params.dart';
import 'text_template.dart';

/// Активная кастуется автоматически по приоритету слота, если кулдаун готов.
/// Пассивная работает всегда. Конкурируют они за один пул из четырёх слотов —
/// в этом и состоит выбор (GDD §3.3).
///
/// Аура работает всегда, как пассивка, но **резервирует ману**: её доля
/// вычитается из запаса навсегда, пока аура в слоте. Это второй, куда более
/// острый смысл маны: активка тратит бюджет на секунду, аура забирает его
/// насовсем. Слот и запас маны — две разные цены за одно и то же место.
enum AbilityType { active, passive, aura }

/// Реализация способности. Значение перечисления — контракт с рантаймом:
/// новый `kind` в JSON без ветки в симуляции обязан валить загрузку, а не
/// молча превращаться в способность, которая ничего не делает.
enum AbilityKind {
  directDamage,
  curse,
  dot,
  auraSlow,

  /// Аура, дающая стат постоянно: то же, что `statTradeoff`, но за резерв
  /// маны и без платы другим статом.
  auraStat,
  buff,
  conditionalLeech,
  critApplyDot,
  statTradeoff,
  repeatAttack,
  corpseExplosion,

  /// Добивание: по цели ниже порога здоровья урон умножается.
  execute,

  /// Цепь: бьёт по нескольким целям с затуханием.
  chainDamage,

  /// Лечение: возвращает долю максимума HP.
  heal,

  /// Шипы: часть полученного урона возвращается ударившему.
  thorns,

  /// Защита на низком здоровье: ниже порога получаемый урон срезан.
  lowLifeGuard,

  /// Пропитка оружия стихией: автоатака начинает бить не физическим уроном,
  /// а стихийным — и получает её тег.
  ///
  /// Это главный мост между двумя осями. Без него игрок, нашедший три вещи с
  /// «+% к урону Огнём», не мог применить их к тому, чем наносит львиную долю
  /// урона: автоатака была физической всегда, и огненная сборка на оружии
  /// была невозможна в принципе.
  infusion,

  /// Тотем: стоит своё время и бьёт с своим интервалом.
  ///
  /// Единственный источник урона, который работает, пока герой занят другим.
  /// Тег «Тотем» до него не усиливал ничего — тотемом называлась одна
  /// способность, и та была баффом.
  summonTotem,

  /// Шанс повторить каст чар — зеркало `repeatAttack` для второй оси.
  ///
  /// Без него у сборки на чарах не было множителя частоты: оружейник берёт
  /// скорость атаки, а чародею брать было нечего.
  repeatSpell,
}

/// Схема параметров для каждого `kind`.
const Map<AbilityKind, List<ParamSpec>> abilityParamSpecs = {
  AbilityKind.directDamage: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.integer('targets'),
    ParamSpec.number('bonusVsSlowed', optional: true),
  ],
  AbilityKind.curse: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.number('duration'),
    ParamSpec.number('damageTakenIncrease'),
  ],
  AbilityKind.dot: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.number('duration'),
    ParamSpec.number('dpsFraction'),
  ],
  AbilityKind.auraSlow: [
    ParamSpec.number('slow'),
  ],
  AbilityKind.auraStat: [
    ParamSpec.text('stat'),
    ParamSpec.number('value'),
  ],
  AbilityKind.buff: [
    ParamSpec.text('stat'),
    ParamSpec.number('value'),
    ParamSpec.number('duration'),
  ],
  AbilityKind.conditionalLeech: [
    ParamSpec.number('threshold'),
    ParamSpec.number('leechMultiplier'),
  ],
  AbilityKind.critApplyDot: [
    ParamSpec.number('duration'),
    ParamSpec.number('dpsFraction'),
  ],
  AbilityKind.statTradeoff: [
    ParamSpec.number('armorPct'),
    ParamSpec.number('attackSpeedPct'),
  ],
  AbilityKind.repeatAttack: [
    ParamSpec.number('chance'),
  ],
  AbilityKind.corpseExplosion: [
    ParamSpec.number('fractionOfMaxHp'),
  ],
  AbilityKind.execute: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.number('threshold'),
    ParamSpec.number('bonusBelow'),
  ],
  AbilityKind.chainDamage: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.integer('targets'),
    ParamSpec.number('falloff'),
  ],
  AbilityKind.heal: [
    ParamSpec.number('fractionOfMaxHp'),
  ],
  AbilityKind.thorns: [
    ParamSpec.number('fractionReturned'),
  ],
  AbilityKind.lowLifeGuard: [
    ParamSpec.number('threshold'),
    ParamSpec.number('lessDamageTaken'),
  ],
  AbilityKind.infusion: [
    ParamSpec.number('moreDamage'),
  ],
  AbilityKind.summonTotem: [
    ParamSpec.number('weaponMultiplier'),
    ParamSpec.number('duration'),
    ParamSpec.number('interval'),
    ParamSpec.integer('targets'),
  ],
  AbilityKind.repeatSpell: [
    ParamSpec.number('chance'),
  ],
};

class AbilityDef implements TaggedSource {
  const AbilityDef({
    required this.id,
    required this.name,
    required this.tags,
    required this.type,
    required this.kind,
    required this.cooldown,
    required this.manaCost,
    required this.manaReserve,
    required this.damageType,
    required this.params,
    required this.isStarter,
    required this.text,
  });

  final String id;
  final String name;
  @override
  final List<Tag> tags;
  final AbilityType type;
  final AbilityKind kind;

  /// Секунды. У пассивных — 0.
  final double cooldown;

  /// Доля запаса маны, которую аура держит занятой. У остальных — 0.
  ///
  /// Доля, а не число: запас маны плоский и растёт только от вложений
  /// игрока, и аура должна забирать ТУ ЖЕ часть бюджета независимо от того,
  /// сколько его набрано. Иначе к сотому этажу резерв стал бы бесплатным.
  final double manaReserve;

  /// Сколько маны стоит каст. У пассивных — 0.
  ///
  /// Кулдаун ограничивает способность поодиночке, мана — все вместе: это
  /// разные вопросы, «как часто» и «сколько их сразу», и потому оба нужны.
  final double manaCost;

  final DamageType damageType;
  final Params params;

  /// Входит ли в стартовый набор нового аккаунта (GDD §10).
  final bool isStarter;

  /// Описание с плейсхолдерами по именам параметров — см. [TextTemplate].
  final String text;

  bool get isActive => type == AbilityType.active;
  bool get isAura => type == AbilityType.aura;

  /// Растёт от силы чар, а не от урона оружия.
  ///
  /// Форма — это ось снаряжения, а не украшение описания: она отвечает на
  /// вопрос «что искать в сундуке под эту способность».
  bool get isSpell => tags.contains(Tag.spell);

  static const _keys = {
    'id', 'ru', 'text', 'tags', 'type', 'kind', 'cooldown', 'damageType',
    'params', 'starter', 'mana', 'reserve',
  };

  static AbilityDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final kind = node.enumByName('kind', AbilityKind.values,
        or: AbilityKind.directDamage)!;
    final type =
        node.enumByName('type', AbilityType.values, or: AbilityType.active)!;

    final params = readParams(node, abilityParamSpecs[kind] ?? const []);

    // Перекрёстная проверка: `stat` в параметрах обязан быть настоящим статом.
    if ((kind == AbilityKind.buff || kind == AbilityKind.auraStat) &&
        params.has('stat')) {
      final name = params.str('stat');
      if (!StatKey.values.any((s) => s.name == name)) {
        node.issues.add('${node.path}.params.stat',
            'неизвестный стат «$name»');
      }
      // Свёртка аур умеет не всякий стат, и стат, которого она не знает,
      // молча не дал бы ничего — как это уже случалось с маной в `scaled`.
      const auraStats = {
        'increasedDamage', 'increasedAttackSpeed', 'armorPct', 'maxHpPct',
        'leech', 'critChance', 'critMulti', 'hpRegen', 'manaRegen',
        'attackDamage', 'spellPower', 'cooldownReduction',
        'resistFire', 'resistCold', 'resistLightning', 'resistVoid',
      };
      if (kind == AbilityKind.auraStat && !auraStats.contains(name)) {
        node.issues.add('${node.path}.params.stat',
            'аура не умеет стат «$name»: свёртка аур его не складывает');
      }
    }

    _checkTags(node, kind, type,
        node.enumList('tags', Tag.values),
        node.enumByName('damageType', DamageType.values,
            or: DamageType.physical)!);

    checkTemplate(
      node,
      'text',
      node.str('text', or: ''),
      {for (final spec in abilityParamSpecs[kind] ?? const []) spec.key},
    );

    final cooldown = node.dbl('cooldown', or: 0.0);
    if (type == AbilityType.active && cooldown <= 0.0) {
      node.issues.add('${node.path}.cooldown',
          'активная способность с нулевой перезарядкой кастуется каждый тик');
    }

    final mana = node.dbl('mana', or: 0.0);
    if (type == AbilityType.active && mana <= 0.0) {
      node.issues.add('${node.path}.mana',
          'бесплатная активка не участвует в бюджете маны — либо цена, '
          'либо это пассивка');
    }
    if (type != AbilityType.active && mana != 0.0) {
      node.issues.add('${node.path}.mana',
          'способность не кастуется, платить ей нечем');
    }

    final reserve = node.dbl('reserve', or: 0.0);
    if (type == AbilityType.aura && (reserve <= 0.0 || reserve >= 1.0)) {
      node.issues.add('${node.path}.reserve',
          'аура обязана резервировать долю маны в пределах (0, 1): '
          'аура без резерва — это пассивка, а с резервом в единицу она '
          'выключает все способности разом');
    }
    if (type != AbilityType.aura && reserve != 0.0) {
      node.issues.add('${node.path}.reserve',
          'резервировать ману умеет только аура');
    }
    if (type == AbilityType.aura && cooldown != 0.0) {
      node.issues.add('${node.path}.cooldown',
          'аура работает всегда, перезаряжать нечего');
    }

    return AbilityDef(
      id: node.str('id'),
      name: node.str('ru'),
      tags: node.enumList('tags', Tag.values),
      type: type,
      kind: kind,
      cooldown: cooldown,
      manaCost: mana,
      manaReserve: reserve,
      damageType:
          node.enumByName('damageType', DamageType.values,
              or: DamageType.physical)!,
      params: params,
      isStarter: node.flag('starter'),
      text: node.str('text', or: ''),
    );
  }

  @override
  String toString() => 'AbilityDef($id, ${kind.name})';
}

/// Виды способностей, которые наносят урон.
///
/// Список нужен валидатору: именно урон обязан называть свою стихию. Аура
/// замедления или лечение живут вне осей урона, и требовать от них стихию
/// значило бы придумывать теги ради галочки.
const _damagingKinds = {
  AbilityKind.directDamage,
  AbilityKind.curse,
  AbilityKind.dot,
  AbilityKind.critApplyDot,
  AbilityKind.corpseExplosion,
  AbilityKind.execute,
  AbilityKind.chainDamage,
  AbilityKind.thorns,
  AbilityKind.infusion,
  AbilityKind.summonTotem,
};

/// Виды, урон которых считается от стата героя, — и потому обязаны назвать
/// форму.
///
/// Шипы и взрыв трупа сюда не входят намеренно: их урон считается от
/// полученного удара и от здоровья трупа. Форма ответила бы на вопрос,
/// которого им никто не задаёт, — но стихию они называют, потому что
/// «+% к урону Пустотой» их усиливает.
const _scaledKinds = {
  AbilityKind.directDamage,
  AbilityKind.curse,
  AbilityKind.dot,
  AbilityKind.critApplyDot,
  AbilityKind.execute,
  AbilityKind.chainDamage,
  AbilityKind.infusion,
  AbilityKind.summonTotem,
};

/// Теги — это не украшение карточки, а то, за что цепляются аффиксы, узлы
/// дерева и черты наёмника. Способность без тегов не входит ни в один билд, и
/// заметить это можно только замером — поэтому здесь стоят проверки.
///
/// Живой прогон дал ровно это: «очень мало тегов у этих скилов, игроку не с
/// чего строить билд». У восьми способностей из тридцати одной тегов не было
/// вовсе.
void _checkTags(JsonNode node, AbilityKind kind, AbilityType type,
    List<Tag> tags, DamageType damageType) {
  if (tags.isEmpty) {
    node.issues.add('${node.path}.tags',
        'способность без тегов не входит ни в один билд: '
        'ни аффикс, ни узел дерева, ни черта наёмника её не усилят');
    return;
  }

  final duplicates = <Tag>{};
  for (final tag in tags) {
    if (!duplicates.add(tag)) {
      node.issues.add('${node.path}.tags', 'тег «${tag.ru}» указан дважды');
    }
  }

  if (_scaledKinds.contains(kind)) {
    // Форма отвечает на вопрос «что искать в сундуке под эту способность».
    // Ровно одна: без формы способность не растёт ни от чего, с двумя —
    // растёт от обеих осей сразу и обесценивает выбор между ними.
    final forms = tags.where(Tag.forms.contains).length;
    if (forms != 1) {
      node.issues.add('${node.path}.tags',
          forms == 0
              ? 'у наносящей урон способности обязана быть форма: '
                  '«Атака» (растёт от урона оружия) или «Чары» (от силы чар)'
              : 'форма ровно одна: способность, растущая от обеих осей, '
                  'делает выбор между оружием и чарами бессмысленным');
    }
  }

  if (_damagingKinds.contains(kind)) {
    // Стихия обязана совпадать с типом урона: огненная способность без тега
    // «Огонь» не попала бы ни в один огненный билд, а «+% к урону Огнём» на
    // вещи не нашло бы, что усиливать.
    if (!tags.contains(damageType.tag)) {
      node.issues.add('${node.path}.tags',
          'урон типа «${damageType.ru}» без тега «${damageType.tag.ru}»: '
          'аффиксам этой стихии нечего усиливать');
    }
    for (final tag in tags) {
      if (!Tag.elements.contains(tag)) continue;
      if (tag != damageType.tag) {
        node.issues.add('${node.path}.tags',
            'тег стихии «${tag.ru}» при уроне типа «${damageType.ru}»: '
            'сопротивление режет по типу, и тег обязан его называть');
      }
    }
  }

  // Механика и объявленный вид обязаны совпадать: иначе «+% к урону
  // Проклятиями» усиливает не то, что игрок считает проклятием.
  if (type == AbilityType.aura && !tags.contains(Tag.aura)) {
    node.issues.add('${node.path}.tags', 'аура без тега «Аура»');
  }
  if (type != AbilityType.aura && tags.contains(Tag.aura)) {
    node.issues.add('${node.path}.tags',
        'тег «Аура» у способности, которая аурой не является');
  }
  if (kind == AbilityKind.curse && !tags.contains(Tag.curse)) {
    node.issues.add('${node.path}.tags', 'проклятие без тега «Проклятие»');
  }
  if (kind == AbilityKind.summonTotem && !tags.contains(Tag.totem)) {
    node.issues.add('${node.path}.tags', 'тотем без тега «Тотем»');
  }
  if (kind == AbilityKind.infusion && tags.contains(Tag.spell)) {
    node.issues.add('${node.path}.tags',
        'пропитка меняет автоатаку — это форма «Атака», а не «Чары»');
  }
  if (kind == AbilityKind.dot && !tags.contains(Tag.duration)) {
    node.issues.add('${node.path}.tags',
        'дот без тега «Длительность»: аффиксам на длительный урон '
        'нечего усиливать');
  }
}
