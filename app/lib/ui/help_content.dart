/// Справка по игре.
///
/// Текст живёт отдельным файлом от экрана намеренно: экран — это список и
/// прокрутка, а это содержание, и править его будут чаще, чем виджеты.
///
/// Правило текста здесь одно: **объяснять правило, а не перечислять кнопки.**
/// «Нажмите на вещь, чтобы открыть карточку» устаревает при первой же правке
/// экрана; «осколок помнит качество, а не число» верно, пока верна игра.
///
/// Второе правило появилось после живого прогона: **в тексте нет ни одного
/// слова, которого игрок не встретил бы на экране.** Справка говорила
/// «аффикс», «перцентиль», «перекат», «ран», «билд» — это слова, которыми
/// удобно писать игру, а не слова, которыми в неё играют. Имена вещей (Эхо,
/// Клеймо, Осколок, Реликт) остаются: их объясняют там, где они впервые
/// встречаются.
///
/// Оба языка лежат рядом строка к строке. Так видно, что переведено, а что
/// нет, и правка правила не расходится с его переводом: их правят в одном
/// месте одним движением.
library;

import 'package:rift/core/model/lang.dart';

class HelpSection {
  const HelpSection({
    required this.id,
    required Phrase title,
    required Phrase summary,
    required this.blocks,
  })  : _title = title,
        _summary = summary;

  /// По нему на раздел ссылаются экраны: Кузница открывает справку сразу на
  /// Кузнице, а не на оглавлении.
  final String id;

  final Phrase _title;
  final Phrase _summary;

  String get title => _title.text;

  /// Одна строка под заголовком в оглавлении.
  String get summary => _summary.text;

  final List<HelpBlock> blocks;
}

/// Кусок раздела: заголовок и абзацы. Заголовок может быть пустым.
class HelpBlock {
  const HelpBlock(this._heading, this._lines);

  final Phrase _heading;
  final List<Phrase> _lines;

  String get heading => _heading.text;

  List<String> get lines => [for (final line in _lines) line.text];
}

/// Пустой заголовок блока. Отдельной константой, чтобы `Phrase.same('')` не
/// повторялся десять раз и читался как «заголовка нет», а не как недоперевод.
const _noHeading = Phrase.same('');

const helpSections = <HelpSection>[
  HelpSection(
    id: 'loop',
    title: Phrase('С чего всё начинается', 'Where it all begins'),
    summary: Phrase(
      'Цикл игры: нанял, отправил, дождался, забрал, вложил',
      'The loop: hire, send, wait, collect, invest',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Вы не спускаетесь в бездну сами. Вы нанимаете тех, кто спускается.',
          'You do not go down into the abyss yourself. You hire those who do.',
        ),
        Phrase(
          'Наёмник уходит вниз с тем, что вы ему собрали, и идёт, пока не '
              'погибнет. Вмешаться нельзя: снаряжение и умения выставляются '
              'ДО отправки и заперты до конца контракта.',
          'The mercenary goes down with whatever you put together and keeps '
              'going until they die. You cannot step in: gear and abilities '
              'are set BEFORE they leave, and locked until the contract '
              'ends.',
        ),
      ]),
      HelpBlock(
          Phrase('Гибель — это не проигрыш', 'Dying is not losing'), [
        Phrase(
          'Наёмник — это один спуск. Он погибнет, и это нормально.',
          'A mercenary is one descent long. They will die, and that is '
              'fine.',
        ),
        Phrase(
          'Снаряжение, золото, осколки и Эхо возвращаются на Заставу. '
              'Теряется только глубина: следующий наёмник начнёт заново — но '
              'уже с тем, что принёс предыдущий.',
          'Gear, gold, shards and Echo come back to the Outpost. Only depth '
              'is lost: the next mercenary starts over — but with what the '
              'previous one brought.',
        ),
      ]),
      HelpBlock(
          Phrase('Ваши вещи не теряются', 'Your items are not lost'), [
        Phrase(
          'Всё, что вы надели на наёмника, уходит вниз именно так, как вы '
              'собрали. Игра не подменяет ваш выбор на «лучшее из сундука»: '
              'она не знает, зачем вы надели именно это кольцо, а вы знаете.',
          'Everything you put on the mercenary goes down exactly as you '
              'left it. The game will not swap your choice for “the best in '
              'the stash”: it has no idea why you picked that particular '
              'ring, and you do.',
        ),
        Phrase(
          'Пустые слоты наёмник дозаполнит сам из сундука — чтобы не уйти '
              'голым. Реликты не берёт: они меняют правила боя, и это ваше '
              'решение.',
          'Empty slots they fill from the stash themselves, so as not to '
              'walk in bare. Relics they leave alone: those change the rules '
              'of a fight, and that call is yours.',
        ),
        Phrase(
          'Внизу наёмник НЕ переодевается. Что вы на него надели — с тем он и '
              'идёт до конца, даже если найдёт вещь получше: найденное он '
              'просто несёт в рюкзаке. Ваше снаряжение возвращается целиком.',
          'Down there they do NOT swap gear. What you put on them is what '
              'they wear to the end, even if they turn up something better: '
              'the find just rides along in the backpack. '
              'Your gear comes back whole.',
        ),
        Phrase(
          'Единственное, где вещи всё же теряются, — переполненный сундук: '
              'если места не хватило, лишнее уходит в золото, и игра об этом '
              'скажет.',
          'The one place items really are lost is an overfull stash: if there '
              'is no room, the surplus turns to gold, and the game says so.',
        ),
      ]),
      HelpBlock(
          Phrase('Добыча ждёт, пока вы её не заберёте',
              'The haul waits until you collect it'), [
        Phrase(
          'Пока наёмник внизу, вы не получаете ничего. Всё, что он найдёт, '
              'вернётся только с ним — и только когда вы откроете журнал и '
              'заберёте.',
          'While they are below, you get nothing. Everything they find comes '
              'back only with them — and only once you open the journal and '
              'take it.',
        ),
        Phrase(
          'Спуск идёт по часам, а не по экрану: игру можно закрыть.',
          'The descent runs on the clock, not on the screen: you can close '
              'the game.',
        ),
      ]),
      HelpBlock(Phrase('Верёвка', 'The rope'), [
        Phrase(
          'Спуск начинается не с первого этажа, а с трети вашего рекорда: до '
              'него спущена верёвка.',
          'A descent starts not on the first floor but a third of the way '
              'to your record: the rope reaches down that far.',
        ),
        Phrase(
          'Пройденное однажды не надо проходить заново — там нечего искать и '
              'некому сопротивляться.',
          'Ground you have covered once is not worth covering twice — '
              'nothing left to find there, and nobody left to fight.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'build',
    title: Phrase('Сборка: снаряжение и умения', 'The build: gear and abilities'),
    summary: Phrase(
      'Девять слотов вещей, четыре слота умений, мана и ауры',
      'Nine item slots, four ability slots, mana and auras',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Сборка — единственное место, где вы принимаете решения о бое. Всё '
              'остальное наёмник делает сам.',
          'The build is the only place you make decisions about the fight. '
              'Everything else, the mercenary handles on their own.',
        ),
      ]),
      HelpBlock(Phrase('Две оси силы', 'Two axes of power'), [
        Phrase(
          'У каждого умения, которое наносит урон, есть ФОРМА — «Атака» или '
              '«Чары». Форма отвечает на один вопрос: от чего это умение '
              'растёт.',
          'Every ability that deals damage has a FORM — Attack or Spell. The '
              'form answers one question: what this ability scales from.',
        ),
        Phrase(
          'АТАКИ растут от урона оружия. Его дают оружие, перчатки, кольца — '
              'и от него же бьёт автоатака.',
          'ATTACKS scale from weapon damage. Weapons, gloves and rings '
              'supply it — and your auto-attack runs off it too.',
        ),
        Phrase(
          'ЧАРЫ растут от силы чар. Её даёт левая рука и свойства «+к силе '
              'чар»; урон оружия им не помогает вовсе.',
          'SPELLS scale from spell power. The off-hand and “+spell power” '
              'properties supply that; weapon damage does nothing for them.',
        ),
        Phrase(
          'Поэтому выбор умений — это и есть ответ на вопрос, что искать в '
              'сундуке. Собрали сборку на Чарах — оружие с большим уроном ей '
              'почти бесполезно, и наоборот.',
          'So picking abilities is the same as deciding what to hunt for in '
              'the stash. Build around Spells and a big-damage weapon is near '
              'dead weight to you — and the other way round.',
        ),
      ]),
      HelpBlock(
          Phrase('Три вида умений на четыре слота',
              'Three kinds of ability for four slots'), [
        Phrase(
          'АКТИВНЫЕ срабатывают сами, когда готова перезарядка и хватает '
              'маны.',
          'ACTIVE ones fire by themselves once the cooldown is up and there '
              'is mana for it.',
        ),
        Phrase(
          'ПАССИВНЫЕ работают всегда и ничего не стоят.',
          'PASSIVE ones always work and cost nothing.',
        ),
        Phrase(
          'АУРЫ работают всегда, но резервируют долю запаса маны — пока аура '
              'в слоте, эта часть недоступна.',
          'AURAS always work, but they hold back a share of the mana pool — '
              'while an aura sits in a slot, that share is off the table.',
        ),
        Phrase(
          'Активные, пассивные и ауры делят одни и те же четыре места. В этом '
              'и состоит выбор.',
          'Active, passive and auras all share the same four slots. That is '
              'where the choice is.',
        ),
      ]),
      HelpBlock(Phrase('Мана', 'Mana'), [
        Phrase(
          'Мана — общий запас на все активные умения. Перезарядка '
              'ограничивает умение поодиночке («как часто»), мана — все '
              'вместе («сколько их сразу»).',
          'Mana is a shared pool for every active ability. A cooldown limits '
              'one ability at a time (“how often”), mana limits them together '
              '(“how many at once”).',
        ),
        Phrase(
          'Не хватило маны — умение просто ждёт, а наёмник продолжает бить '
              'оружием. Пустая мана не ломает бой: это запас, который можно '
              'не рассчитать, а не наказание.',
          'If mana runs short, the ability simply waits and the mercenary '
              'keeps swinging. An empty pool does not break the fight — it is '
              'a budget you can misjudge, not a punishment.',
        ),
        Phrase(
          'Аура забирает и запас, и восстановление. Активное умение тратит '
              'ману на секунду, аура — насовсем: две ауры уже заметно сушат '
              'сборку, три превращают наёмника в бойца без умений.',
          'An aura takes the pool and the regeneration both. An active '
              'ability spends mana for a second; an aura spends it for good. '
              'Two auras already leave a build visibly dry, three turn your '
              'mercenary into someone with no abilities at all.',
        ),
        Phrase(
          'Запас маны не растёт от глубины: цены умений тоже не растут. '
              'Поднять его можно только вложениями — свойствами на вещах и '
              'лучом «Разум» в дереве пассивок.',
          'The mana pool does not grow with depth — and neither do ability '
              'costs. The only way up is investment: item properties, and the '
              'Mind branch of the passive tree.',
        ),
      ]),
      HelpBlock(Phrase('Сила сборки', 'Build power'), [
        Phrase(
          'Число под сборкой — это оценка того, как глубоко наёмник дойдёт. '
              'Оно считает вещи, оба дерева и выбранные умения вместе с их '
              'тегами.',
          'The number under the build is a guess at how deep this mercenary '
              'will get. It counts items, both trees, and the abilities you '
              'chose along with their tags.',
        ),
        Phrase(
          'Оценка знает, чем вы бьёте: поставьте в слоты Чары — и вещи с '
              'силой чар начнут поднимать это число, а урон оружия перестанет.',
          'The guess knows what you strike with: slot Spells, and items with '
              'spell power start lifting the number while weapon damage stops '
              'counting.',
        ),
        Phrase(
          'Чего оно не считает: сопротивления, вампиризм и всё, что умение '
              'делает помимо урона. Это мерка для сравнения вещей, а не '
              'приговор.',
          'What it does not count: resistances, life leech and everything an '
              'ability does besides damage. It is a yardstick for comparing '
              'items, not a verdict.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'tags',
    title: Phrase('Теги: как связаны умения и вещи',
        'Tags: how abilities and items connect'),
    summary: Phrase(
      'Стихия, форма, доставка, механика — и что их усиливает',
      'Element, form, delivery, mechanic — and what boosts them',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Под каждым умением написаны его теги. Это не украшение: тег — '
              'единственное, за что цепляются вещи, дерево пассивок и черта '
              'наёмника.',
          'Every ability lists its tags underneath. Those are not '
              'decoration: a tag is the only thing items, the passive tree '
              'and a mercenary’s trait can hook onto.',
        ),
        Phrase(
          '«+18 % к урону Огнём» усиливает ЛЮБОЕ умение с тегом «Огонь» — и '
              'не делает ничего для умения без него.',
          '“+18% Fire damage” boosts ANY ability with the Fire tag — and does '
              'nothing for an ability without it.',
        ),
      ]),
      HelpBlock(Phrase('Четыре оси тегов', 'Four axes of tags'), [
        Phrase(
          'СТИХИЯ — Огонь, Холод, Молния, Пустота, Физический. Она же тип '
              'урона: у врагов бывают сопротивления, и стихия говорит, какое '
              'из них сработает.',
          'ELEMENT — Fire, Cold, Lightning, Void, Physical. It is also the '
              'damage type: enemies have resistances, and the element says '
              'which one applies.',
        ),
        Phrase(
          'ФОРМА — Атака или Чары. От чего умение растёт.',
          'FORM — Attack or Spell. What the ability scales from.',
        ),
        Phrase(
          'ДОСТАВКА — Снаряд, Область. По скольким целям бьёт.',
          'DELIVERY — Projectile, Area. How many targets it hits.',
        ),
        Phrase(
          'МЕХАНИКА — Длительность, Проклятие, Аура, Тотем, Удар, Кровь.',
          'MECHANIC — Duration, Curse, Aura, Totem, Strike, Blood.',
        ),
        Phrase(
          'У одного умения теги с разных осей сразу. Поэтому «+% к урону '
              'Снарядами» и «+% к урону Молнией» усиливают «Разряд» оба.',
          'A single ability carries tags from several axes at once. That is '
              'why “+% Projectile damage” and “+% Lightning damage” both boost '
              'Spark Bolt.',
        ),
      ]),
      HelpBlock(
          Phrase('Где брать множители', 'Where multipliers come from'), [
        Phrase(
          'ДЕРЕВО ПАССИВОК — надёжный источник: пять лучей отданы стихиям '
              'целиком, и вы выбираете, в какой идти.',
          'THE PASSIVE TREE is the reliable source: five branches are given '
              'over to elements entirely, and you choose which to walk.',
        ),
        Phrase(
          'ВЕЩИ — случайный: свойство «+% к урону с тегом» выпадает с '
              'конкретным тегом, и нужный придётся искать. Зато Кузница умеет '
              'вынуть его в осколок и переставить на вещь получше.',
          'ITEMS are the random source: a “+% tagged damage” property rolls '
              'with one specific tag, and you have to hunt for the tag you '
              'want. The Forge can at least pull it into a shard and move it '
              'onto a better item.',
        ),
        Phrase(
          'ЧЕРТА НАЁМНИКА — иногда даёт стихию сразу.',
          'THE MERCENARY’S TRAIT sometimes grants an element outright.',
        ),
      ]),
      HelpBlock(
          Phrase('Пропитка: мост между осями',
              'Infusion: a bridge between axes'), [
        Phrase(
          'Умения-пропитки («Пламя на клинке» и подобные) заставляют '
              'автоатаку бить стихией вместо физического урона.',
          'Infusion abilities (Flame on the Blade and its kin) make the '
              'auto-attack strike with an element instead of physical damage.',
        ),
        Phrase(
          'Это единственный способ применить огненные вещи к автоатаке — а '
              'именно ею наёмник наносит львиную долю урона. Оружейная сборка '
              'с пропиткой пользуется стихийным лучом дерева наравне с чарами.',
          'It is the only way to apply fire items to the auto-attack — and '
              'that is where the mercenary’s damage mostly comes from. A '
              'weapon build with an infusion uses an elemental branch of the '
              'tree on equal terms with spells.',
        ),
        Phrase(
          'Обратная сторона: пропитанный удар режется сопротивлением этой '
              'стихии. Против врага, который к ней стоек, вы бьёте слабее.',
          'The catch: an infused strike is cut by resistance to that '
              'element. Against an enemy that resists it, you hit softer.',
        ),
      ]),
      HelpBlock(
          Phrase('Как это читать на экране', 'How to read this on screen'), [
        Phrase(
          'В сборке под умениями есть строка «Урон по тегам». Яркий тег '
              'работает на выбранных умениях, бледный — не встречается ни в '
              'одном из них, и эти проценты сейчас лежат впустую.',
          'In the build, under the abilities, there is a “Damage by tag” row. '
              'A bright tag works on the chosen abilities; a pale one appears '
              'in none of them, and those percentages are lying idle.',
        ),
        Phrase(
          'В выборе умения теги вынесены в отбор сверху: точка у тега '
              'означает, что множитель по нему у вас уже есть.',
          'In the ability picker the tags are lifted into a filter at the '
              'top: a dot on a tag means you already have a multiplier for it.',
        ),
        Phrase(
          'Кнопка «i» у любого умения открывает разбор: от какой вашей '
              'характеристики оно растёт, сколько бьёт за удар и в секунду, '
              'из чего сложились ваши увеличения и что делает каждый его тег. '
              'Числа там ваши, а не примерные.',
          'The “i” button on any ability opens a breakdown: which of your '
              'stats it scales from, how much it hits for per strike and per '
              'second, what your increases add up from, and what each of its '
              'tags does. Those numbers are yours, not ballpark.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'items',
    title: Phrase('Вещи и их свойства', 'Items and their properties'),
    summary: Phrase(
      'Что написано на вещи и что из этого важно',
      'What is written on an item and which of it matters',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'У вещи есть уровень, редкость, основа и свойства.',
          'An item has a level, a rarity, a base and properties.',
        ),
        Phrase(
          'ОСНОВА — то, что есть у любой вещи этого типа: у доспеха броня, у '
              'оружия урон. Она растёт вместе с уровнем вещи.',
          'THE BASE is what every item of that type has: armor on body armor, '
              'damage on a weapon. It grows with the item’s level.',
        ),
        Phrase(
          'СВОЙСТВА — то, что выпало именно этой вещи. Сколько их будет, '
              'решает редкость; какие именно — случай. Они и делают вещь '
              'вашей.',
          'PROPERTIES are what rolled on this particular item. Rarity says '
              'how many; chance says which. They are what make an item '
              'yours.',
        ),
      ]),
      HelpBlock(Phrase('Качество', 'Quality'), [
        Phrase(
          'У каждого свойства есть качество от 0 до 100 — насколько удачно '
              'оно выпало. Качество 96 значит, что лучше на этом уровне вещи '
              'почти не бывает.',
          'Every property has a quality from 0 to 100 — how well it rolled. '
              'Quality 96 means there is almost nothing better at this item '
              'level.',
        ),
        Phrase(
          'Качество важнее самого числа. Число стареет вместе с вещью — через '
              'двадцать этажей вы найдёте такое же, но больше. Качество не '
              'стареет: именно его и хранят осколки.',
          'Quality matters more than the number. The number ages with the '
              'item — twenty floors later you will find the same one, but '
              'bigger. Quality does not age: that is exactly what shards keep.',
        ),
      ]),
      HelpBlock(
          Phrase('Наёмник донесёт всё',
              'The mercenary carries everything back'), [
        Phrase(
          'Он не выбрасывает ничего: что нашёл, то и принёс наверх. Ограничен '
              'не рюкзак, а сундук на Заставе.',
          'They throw nothing away: what they find is what comes up. The '
              'limit is not the backpack — it is the stash at the Outpost.',
        ),
        Phrase(
          'Поэтому после каждого спуска вы разбираете добычу сами — см. '
              'раздел «Разбор добычи».',
          'That is why after every descent you sort the haul yourself — see '
              '“Sorting the haul”.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'loot',
    title: Phrase('Разбор добычи', 'Sorting the haul'),
    summary: Phrase(
      'Что оставить, что переплавить, что продать',
      'What to keep, what to salvage, what to sell',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Наёмник приносит наверх всё найденное. Место есть только в '
              'сундуке, и решаете вы: над каждой вещью три кнопки.',
          'The mercenary brings up everything they found. The only place '
              'that runs out of room is the stash — so you decide, three '
              'buttons over every item.',
        ),
        Phrase(
          'ОСТАВИТЬ — вещь едет в сундук и станет частью следующей сборки. '
              'Мест ровно столько, сколько даёт Хранилище.',
          'KEEP — it goes into the stash and becomes part of the next '
              'build. You get exactly as many slots as the Vault gives you.',
        ),
        Phrase(
          'ПЕРЕПЛАВИТЬ — золото и, если вещь была редкой, осколок. Осколок '
              'хранит качество свойства и нужен Кузнице.',
          'SALVAGE — gold and, if the item was rare, a shard. A shard keeps a '
              'property’s quality and is what the Forge needs.',
        ),
        Phrase(
          'ПРОДАТЬ — золота больше, осколка нет. Когда материал не нужен, а '
              'нужны деньги.',
          'SELL — more gold, no shard. For when it is money you need, not '
              'material.',
        ),
      ]),
      HelpBlock(Phrase('Зачем это вам', 'Why this is yours to do'), [
        Phrase(
          'Вещь, слабая по уровню, может быть единственной с нужным тегом. '
              'Раньше такую выбрасывал наёмник, не зная вашей сборки, — '
              'теперь её судьбу решаете вы.',
          'An item that looks weak by level may be the only one carrying '
              'the tag you need. It used to be thrown away by a mercenary who '
              'knew nothing of your build — now the call is yours.',
        ),
        Phrase(
          'Хранилище на Заставе растёт без потолка. Это единственная '
              'постройка без предела: место в сундуке нужно всегда.',
          'The Vault at the Outpost grows without a ceiling — the only '
              'building with no limit. Stash room is never not wanted.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'craft',
    title: Phrase('Кузница и осколки', 'The Forge and shards'),
    summary: Phrase(
      'Переброс, разбор, вставка, углубление — по шагам',
      'Reroll, break down, imprint, deepen — step by step',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Кузница нужна ради одного: то, что вы в ней сделали, НЕ стареет. '
              'Любую вещь вы найдёте лучше через двадцать этажей, а вложенное '
              'в осколок останется с вами навсегда.',
          'The Forge exists for one thing: what you make in it does NOT '
              'age. Any item, you will find a better one twenty floors down — '
              'but what went into a shard stays with you for good.',
        ),
        Phrase(
          'Каждое действие сперва показывает, что получится, и только потом '
              'берёт плату. Передумать можно всегда.',
          'Every action shows you the outcome first and only then asks for '
              'payment. You can always back out.',
        ),
      ]),
      HelpBlock(Phrase('Перебросить свойство', 'Reroll a property'), [
        Phrase(
          'Бросает число заново. Что выпадет — неизвестно; известно, между '
              'чем и чем, и это написано до оплаты.',
          'Rolls the number again. You will not know what comes up — only '
              'the range it lands in, and that is on screen before you pay.',
        ),
        Phrase(
          'Уровень Кузницы поднимает нижнюю границу броска. Пока она ниже '
              'нынешнего числа, переброс — лотерея: может стать хуже. Когда '
              'Кузница поднимет её выше, хуже уже не будет никогда.',
          'The Forge’s level raises the floor of the roll. While that floor '
              'sits below your current number, a reroll is a lottery — it can '
              'come out worse. Once the Forge lifts it above, it never can '
              'again.',
        ),
        Phrase(
          'Каждый следующий переброс того же свойства дороже предыдущего.',
          'Each next reroll of the same property costs more than the last.',
        ),
      ]),
      HelpBlock(
          Phrase('Разобрать на осколок', 'Break down into a shard'), [
        Phrase(
          'Вещь исчезает целиком. От неё остаётся ОДНО свойство — то, что вы '
              'выбрали, — в виде осколка. Остальные пропадают.',
          'The item is destroyed entirely. ONE property remains — the one you '
              'chose — as a shard. The rest are lost.',
        ),
        Phrase(
          'Осколок помнит не число, а качество. Поэтому он не стареет: '
              'вставьте его в вещь поглубже, и там он даст больше, чем давал '
              'раньше.',
          'A shard remembers the quality, not the number. That is why it '
              'does not age: set it into a deeper item and it pays out more '
              'there than it did before.',
        ),
        Phrase(
          'При разборе качество теряет 10 пунктов — это плата за то, что '
              'свойство стало переносимым.',
          'Breaking down costs 10 points of quality — the price of making '
              'the property portable.',
        ),
      ]),
      HelpBlock(Phrase('Вставить осколок', 'Imprint a shard'), [
        Phrase(
          'Кладёт осколок в свободное место на вещи. Число пересчитывается '
              'под уровень ЭТОЙ вещи — ради этого осколки и берегут.',
          'Sets the shard into a free slot on the item. The number is '
              'worked out again for THIS item’s level — which is the whole '
              'reason to hoard shards.',
        ),
        Phrase(
          'Свободных мест нет — придётся стереть одно из свойств. Оно '
              'пропадёт; Верстак осколков даёт шанс его уберечь, и этот шанс '
              'написан в подтверждении.',
          'With no free slot, one of the properties has to be wiped. It is '
              'gone; the Shard Bench gives it a chance of surviving, and that '
              'chance is spelled out before you confirm.',
        ),
        Phrase(
          'Двух одинаковых свойств на одной вещи не бывает.',
          'No item ever carries the same property twice.',
        ),
      ]),
      HelpBlock(Phrase('Углубить реликт', 'Deepen a relic'), [
        Phrase(
          'Поднимает уровень реликта, пересчитывая всё, что от него зависит. '
              'Особое свойство реликта не меняется — оно и не стареет.',
          'Raises the relic’s level, recomputing everything that depends on '
              'it. The relic’s unique effect does not change — it does not '
              'age either.',
        ),
        Phrase(
          'Выше вашего рекорда глубины поднять нельзя: реликт не должен '
              'обгонять того, кто его носит.',
          'It cannot be raised above your depth record: a relic must not '
              'outrun the one who wears it.',
        ),
      ]),
      HelpBlock(
          Phrase('Куда девать лишнее', 'What to do with the surplus'), [
        Phrase(
          'Переплавка превращает вещь в золото — сколько именно, зависит от '
              'Алтаря. Это единственный способ освободить место в сундуке '
              'своими руками: иначе за вас решит переполнение.',
          'Salvage turns an item into gold — how much is up to the Altar. '
              'It is the only way to clear stash room by your own hand; '
              'otherwise overflow does it for you, and not to your taste.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'quests',
    title: Phrase('Задания: откуда берутся умения',
        'Quests: where abilities come from'),
    summary: Phrase(
      'Сорок четыре цели, у каждой своё умение в награду',
      'Forty-four goals, each with its own ability as the reward',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Все умения, кроме стартовых одиннадцати, открываются ЗАДАНИЯМИ. '
              'Одно задание — одно умение.',
          'Every ability except the eleven starting ones is opened by a '
              'QUEST. One quest, one ability.',
        ),
        Phrase(
          'Заданий сорок четыре, и они разложены по цепочкам: пролог, четыре '
              'стихии, ремесло войны, стойкость и знамёна.',
          'There are forty-four quests, laid out in chains: the prologue, '
              'four elements, the craft of war, fortitude and banners.',
        ),
      ]),
      HelpBlock(
          Phrase('Видно следующий шаг, а не всё сразу',
              'You see the next step, not everything at once'), [
        Phrase(
          'В журнале показаны только те цели, до которых вы дошли по цепочке. '
              'Остальные откроются дальше — иначе это был бы не список целей, '
              'а простыня из сорока четырёх строк.',
          'The journal shows only the goals you have reached along the '
              'chain. The rest open later — otherwise this would not be a '
              'list of goals but a wall of forty-four lines.',
        ),
        Phrase(
          'Если вы выполнили условие раньше, чем цель открылась, она '
              'закроется в тот же миг, когда откроется. Заслуженное не '
              'пропадает.',
          'If you met the condition before the goal even opened, it closes '
              'the moment it appears. Nothing earned goes to waste.',
        ),
      ]),
      HelpBlock(Phrase('Три вида целей', 'Three kinds of goal'), [
        Phrase(
          'НАКОПИТЕЛЬНЫЕ — рекорд глубины, число контрактов, уровень '
              'постройки, узлы древа, очки дерева, осколки, реликты. У них '
              'есть полоска: видно, сколько осталось.',
          'CUMULATIVE — depth record, number of contracts, building level, '
              'tree nodes, tree points, shards, relics. They have a bar: you '
              'can see how much is left.',
        ),
        Phrase(
          'ПРО ОДИН СПУСК — «нанесите половину урона Молнией», «пройдите '
              'спуск со сборкой, где два умения с тегом Огонь». Полоски у них '
              'нет: такая цель либо выполнена спуском, либо нет.',
          'ABOUT ONE DESCENT — “deal half your damage as Lightning”, “finish '
              'a descent with two Fire-tagged abilities”. They have no bar: '
              'such a goal is either met by a descent or not.',
        ),
        Phrase(
          'ПРО СОБЫТИЕ — уложить конкретного босса. Дойти до него и уложить '
              'его — разные вещи.',
          'ABOUT AN EVENT — bring down a particular boss. Reaching one and '
              'putting it down are two different things.',
        ),
      ]),
      HelpBlock(
          Phrase('Почему цели про урон стихией',
              'Why there are goals about elemental damage'), [
        Phrase(
          'Это единственный вид цели, который спрашивает про БИЛД, а не про '
              'глубину. Выполнить его можно только собрав сборку вокруг '
              'стихии — и по дороге станет понятно, как теги, вещи и дерево '
              'связаны между собой.',
          'It is the only kind of goal that asks about the BUILD rather than '
              'about depth. It can only be met by building around an element '
              '— and along the way it becomes clear how tags, items and the '
              'tree connect.',
        ),
        Phrase(
          'Стартовый набор всегда содержит умение той стихии, которую просит '
              'первое звено цепи: цепь не требует того, что сама же и выдаёт.',
          'The starting set always contains an ability of the element the '
              'first link of the chain asks for: a chain does not demand what '
              'it itself hands out.',
        ),
        Phrase(
          'Ста процентов одной стихией не просят никогда: автоатака бьёт '
              'своим типом урона, и сборки без неё в игре нет.',
          'A hundred percent of one element is never asked for: the '
              'auto-attack strikes with its own damage type, and there is no '
              'build in the game without it.',
        ),
      ]),
      HelpBlock(
          Phrase('Награда приходит с добычей',
              'The reward arrives with the haul'), [
        Phrase(
          'Задания проверяются в тот момент, когда вы забираете добычу. Спуск '
              'посчитан заранее, но пока вы не вернулись за ним — он вам не '
              'принадлежит, и награда за него тоже.',
          'Quests are checked the moment you collect the haul. The descent '
              'is worked out in advance, but until you come back for it, it '
              'is not yours — and neither is the reward.',
        ),
        Phrase(
          'Сверх умения задание даёт немного Эха. Немного намеренно: награда '
              'задания — новое умение, а не валюта.',
          'On top of the ability, a quest hands over a little Echo. A '
              'little, on purpose: the reward here is a new ability, not '
              'currency.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'trees',
    title: Phrase('Два дерева', 'Two trees'),
    summary: Phrase(
      'Древо Эха и дерево пассивок: чем они отличаются',
      'The Echo tree and the passive tree: how they differ',
    ),
    blocks: [
      HelpBlock(Phrase('Древо Эха', 'The Echo tree'), [
        Phrase(
          'Покупается Эхом — валютой, которая приходит с каждой смертью и '
              'больше ниоткуда.',
          'Bought with Echo — a currency that comes with every death and from '
              'nowhere else.',
        ),
        Phrase(
          'Меняет ПРАВИЛА спуска: добавляет место под умение и под свойство '
              'вещи, даёт стартовую глубину, спасает осколок при полном '
              'Верстаке.',
          'It changes the RULES of a descent: adds a slot for an ability and '
              'for an item property, grants starting depth, saves a shard '
              'when the Bench is full.',
        ),
        Phrase(
          'Умения оно НЕ открывает — это делают задания. Древо отвечает за '
              'то, по каким правилам идёт спуск, задания — за то, чем вы его '
              'проходите.',
          'It does NOT unlock abilities — quests do that. The tree decides '
              'the rules a descent runs by; quests decide what you walk it '
              'with.',
        ),
        Phrase(
          'Ветка открывается по порядку: вложенное в урон не досталось '
              'выживанию.',
          'A branch opens in order: what went into damage did not go into '
              'survival.',
        ),
      ]),
      HelpBlock(Phrase('Дерево пассивок', 'The passive tree'), [
        Phrase(
          'Очки даёт достигнутая ГЛУБИНА, а не потраченная валюта: очко '
              'подтверждает, что вы там были.',
          'Points come from DEPTH reached, not from currency spent: a point '
              'is proof you were there.',
        ),
        Phrase(
          'Действует на всех наёмников сразу — наёмник живёт один спуск, а '
              'дерево переживает любое их число.',
          'It applies to every mercenary at once — a mercenary lasts one '
              'descent, and the tree outlives any number of them.',
        ),
        Phrase(
          'Узел берётся, только если рядом уже взят другой. Дорога до '
              'дальнего луча стоит очков, и в этом весь выбор.',
          'You can only take a node next to one you already hold. The road '
              'out to a distant branch costs points, and that is the whole '
              'choice.',
        ),
      ]),
      HelpBlock(Phrase('Три вида узлов', 'Three kinds of node'), [
        Phrase(
          'ДОРОГА — мелкая прибавка. Её берут, чтобы пройти дальше.',
          'THE ROAD — a small bonus you take to get somewhere else.',
        ),
        Phrase(
          'КРУПНЫЙ узел — то, ради чего в луч идут. Без платы. Один в каждом '
              'луче меняет ПРАВИЛО, а не число: «убийство лечит», «по '
              'замедленным крит всегда», «часть брони считается '
              'сопротивлением».',
          'A NOTABLE node is what you walk a branch for, and it costs '
              'nothing extra. One in each branch changes a RULE rather than a '
              'number: “a kill heals”, “strikes on slowed targets always '
              'crit”, “part of your armor counts as resistance”.',
        ),
        Phrase(
          'КЛЮЧЕВОЙ узел — размен: большой плюс и настоящая плата другой '
              'характеристикой. По одному на луч, тринадцать на всё дерево.',
          'A KEYSTONE is a trade: a big gain, and a real price paid out of '
              'some other stat. One per branch, thirteen in the whole tree.',
        ),
        Phrase(
          'Снять можно только конец дороги. Полный сброс бесплатен: ошибка в '
              'сборке не должна стоить вам аккаунта.',
          'Only the end of a road can be undone. A full reset is free: a '
              'mistake in a build must not cost you your account.',
        ),
      ]),
      HelpBlock(
          Phrase('Общие лучи и стихийные',
              'General branches and elemental ones'), [
        Phrase(
          'Восемь лучей двигают общие числа: здоровье, броню, урон, крит, '
              'скорость, ману, добычу, вампиризм. Они работают всегда.',
          'Eight branches move general numbers: health, armor, damage, crit, '
              'speed, mana, loot, life leech. They always work.',
        ),
        Phrase(
          'Пять лучей отданы стихиям и чарам: их узлы усиливают только то, '
              'что несёт нужный тег. Поэтому проценты в них крупнее — узкий '
              'узел обязан давать больше широкого, иначе его незачем брать.',
          'Five branches are given to the elements and to spells: their nodes '
              'boost only what carries the right tag. That is why their '
              'percentages are larger — a narrow node must give more than a '
              'wide one, or there is no reason to take it.',
        ),
        Phrase(
          'Стихийный луч окупается двумя способами: сборкой на Чарах этой '
              'стихии или пропиткой оружия в неё. Во втором случае '
              'усиливается и автоатака, и он выгоднее.',
          'An elemental branch pays off two ways: a Spell build of that '
              'element, or infusing your weapon with it. The second also '
              'boosts the auto-attack, and is the better trade.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'outpost',
    title: Phrase('Застава и экономика', 'The Outpost and the economy'),
    summary: Phrase(
      'Постройки, задаток наёмника, куда уходит золото',
      'Buildings, the mercenary’s retainer, where the gold goes',
    ),
    blocks: [
      HelpBlock(Phrase('Постройки', 'Buildings'), [
        Phrase(
          'Застава покупается золотом и даёт экономику и удобство: сколько '
              'вещей влезет, сколько даёт переплавка лишнего, кто приходит '
              'в Таверну, насколько наёмник отдыхает между этажами.',
          'The Outpost is bought with gold, and what it buys is economy and '
              'comfort: how many items fit, what salvage pays back, who walks '
              'into the Tavern, how much your mercenary recovers between '
              'floors.',
        ),
        Phrase(
          'Уровень открывает достигнутая ГЛУБИНА, а не кошелёк. Иначе '
              'Застава выкупалась бы вперёд прогресса, и дальше игра шла бы '
              'сама.',
          'Levels are unlocked by DEPTH reached, not by your purse. '
              'Otherwise you would buy the whole Outpost out ahead of your '
              'own progress, and the game would run itself from there.',
        ),
      ]),
      HelpBlock(Phrase('Таверна', 'The Tavern'), [
        Phrase(
          'Ранг наёмника — это множитель всех его характеристик и размер '
              'рюкзака. Таверна не делает наёмника сильнее: она повышает '
              'шансы, что придёт хороший.',
          'Rank is a multiplier on every stat a mercenary has, and on the '
              'size of their pack. The Tavern makes nobody stronger — it only '
              'raises the odds that a good one walks in.',
        ),
        Phrase(
          'Задаток растёт вместе с вашим рекордом: чем глубже расселина, тем '
              'дороже те, кто в неё пойдёт. Оборванцы стоят своё всегда.',
          'The fee climbs with your record: the deeper the rift runs, the '
              'more they want for going into it. The Ragged always come at '
              'their own flat price.',
        ),
        Phrase(
          'Если наёмников нет и платить нечем, Таверна отдаёт добровольца '
              'даром. В расселину всегда есть кому пойти от отчаяния.',
          'With nobody left and nothing to pay with, the Tavern hands over a '
              'volunteer for nothing. There is always someone desperate '
              'enough to walk into the rift.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'brand',
    title: Phrase('Клеймо Бездны', 'Brand of the Abyss'),
    summary: Phrase(
      'Добровольная сложность и лестница эндгейма',
      'Voluntary difficulty and the endgame ladder',
    ),
    blocks: [
      HelpBlock(_noHeading, [
        Phrase(
          'Клеймо выставляется перед спуском. Каждый ранг делает врагов '
              'крепче, а добычу и Эхо — больше.',
          'The Brand is set before a descent. Every rank makes enemies '
              'tougher and the haul and the Echo larger.',
        ),
        Phrase(
          'Первые ранги открывает рекорд глубины. Дальше — только делом: '
              'чтобы открыть следующий ранг, надо дойти до нужного этажа НА '
              'текущем.',
          'The first ranks are opened by your depth record. After that only '
              'by deed: to open the next rank you must reach the required '
              'floor ON the current one.',
        ),
        Phrase(
          'Каждый доказанный ранг даёт лишнее очко дерева пассивок сверх его '
              'потолка.',
          'Every proven rank grants one extra passive tree point above its '
              'cap.',
        ),
      ]),
      HelpBlock(Phrase('Зачем это нужно', 'What it is for'), [
        Phrase(
          'Рано или поздно Застава достроена, деревья выкуплены, и глубина '
              'встаёт. Клеймо — то, что растёт дальше: вопрос меняется с «как '
              'глубоко ты зашёл» на «на каком Клейме ты держишь свою глубину».',
          'Sooner or later the Outpost is finished, the trees are bought out '
              'and depth stops moving. The Brand is what grows after that: '
              'the question turns from “how deep did you get” into “what '
              'Brand can you hold that depth at”.',
        ),
      ]),
    ],
  ),
  HelpSection(
    id: 'descent',
    title: Phrase('Спуск: этажи, развилки, стена',
        'The descent: floors, forks, the wall'),
    summary: Phrase(
      'Как устроен спуск и почему наёмник всё-таки гибнет',
      'How a descent works and why the mercenary dies anyway',
    ),
    blocks: [
      HelpBlock(Phrase('Этаж', 'A floor'), [
        Phrase(
          'Этаж — это три волны врагов и сундук. Каждый пятый этаж — босс.',
          'A floor is three waves of enemies and a chest. Every fifth floor '
              'holds a boss.',
        ),
        Phrase(
          'Между этажами наёмник переводит дух: это занимает время и '
              'возвращает часть здоровья и маны.',
          'Between floors they stop to catch their breath: it takes time, '
              'and gives back part of their health and mana.',
        ),
      ]),
      HelpBlock(Phrase('Развилки', 'Forks'), [
        Phrase(
          'Каждые несколько этажей путь раздваивается, и у каждой ветки свой '
              'модификатор — «врагов вдвое больше», «нет регенерации», «−30 к '
              'сопротивлению».',
          'Every few floors the path splits in two, and each branch has its '
              'own modifier — “twice the enemies”, “no regeneration”, “−30 '
              'resistance”.',
        ),
        Phrase(
          'На развилке наёмник ОСТАНАВЛИВАЕТСЯ и ждёт вашего решения. Не '
              'дождавшись — идёт дальше по приказу, который вы выставили в '
              'сборке, и больше на этом спуске не встаёт нигде.',
          'At a fork the mercenary STOPS and waits for your decision. If it '
              'does not come, they walk on by the standing order you set in '
              'the build — and never stop again for the rest of that descent.',
        ),
        Phrase(
          'Тому, кто здесь, открыт третий путь: награды обоих путей и ни '
              'одной платы. Платой служит само присутствие — приказ такой '
              'путь выбрать не может.',
          'For whoever is actually here, a third path opens: the rewards of '
              'both, and no price at all. Being here IS the price — a '
              'standing order can never take that one.',
        ),
        Phrase(
          'Модификатор держится до следующей развилки, а не один этаж.',
          'A modifier holds until the next fork, not for a single floor.',
        ),
      ]),
      HelpBlock(Phrase('Разлом дня', 'The Daily Rift'), [
        Phrase(
          'Раз в сутки открыт особый спуск. Модификатор дня действует на '
              'каждом этаже, а не между развилками, и он один для всех '
              'игроков: сегодняшний разлом нельзя перекатить, закрыв игру.',
          'Once a day a special descent opens. The day’s modifier applies on '
              'every floor rather than between forks, and it is the same for '
              'every player: today’s rift cannot be rerolled by closing the '
              'game.',
        ),
        Phrase(
          'Эхо за такой спуск удваивается, а глубина в разломах ведёт '
              'отдельную запись — сравнивать её с обычным рекордом значило бы '
              'сравнивать разные игры.',
          'Echo for such a descent is doubled, and rift depth keeps its own '
              'record — comparing it with the ordinary one would mean '
              'comparing different games.',
        ),
        Phrase(
          'Сутки тратятся в момент отправки. Развилки внутри разлома работают '
              'как обычно, и выбранный путь складывается с модификатором дня.',
          'Your day is spent the moment you send someone. Forks inside a '
              'rift work as usual, and whichever path you pick stacks with '
              'the day’s modifier.',
        ),
      ]),
      HelpBlock(Phrase('Стена', 'The wall'), [
        Phrase(
          'Враги усиливаются быстрее, чем растёт снаряжение. Это не ошибка '
              'баланса, а устройство игры: у каждой сборки есть глубина, '
              'дальше которой она не идёт.',
          'Enemies grow stronger faster than gear does. That is not a '
              'balance mistake, it is how the game is built: every build has '
              'a depth it will not get past.',
        ),
        Phrase(
          'Удвоение силы сборки добавляет около сорока этажей. Именно поэтому '
              'смерть — не проигрыш, а способ измерить, насколько вы выросли.',
          'Doubling a build’s power buys about forty floors. Which is why a '
              'death is not a loss but a measurement: it tells you how far '
              'you have come.',
        ),
      ]),
    ],
  ),
];
