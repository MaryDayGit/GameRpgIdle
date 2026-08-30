# Основа: кривые, герой, бой, добыча

Числа, от которых зависит вся игра сразу. Кривые роста врагов и вещей решают, где стена; базовые статы героя — с чего он начинает; добыча — сколько всего этого падает.

Здесь правки самые опасные: один множитель роста меняет каждый спуск. После правки обязательно прогнать `--curve` и `--campaign`.

## Кривые

Рост врагов, рост вещей, Эхо, золото, Клеймо, верёвка.

<!-- balance: file=balance path=curves kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `tau` | 30 |  |
| `mobHpGrowth` | 1.06 |  |
| `mobDpsGrowth` | 1.08 |  |
| `mobHpBase` | 22 |  |
| `mobDpsBase` | 6.5 |  |
| `itemGrowth` | 1.0715 | Во сколько раз сильнее предмет на этаж глубже. РУЧКА, а не производная. Два условия, оба проверяет валидатор: sqrt(mobHpGrowth*mobDpsGrowth) < itemGrowth < mobDpsGrowth. Первое — добыча двигает прогресс: снаряжение с глубины D уводит на D*2ln(g)/ln(a*b), и это должно быть больше D. Второе — спуск обрывается смертью, а не бесконечно медленными этажами. Вместе они выполнимы только при mobHpGrowth < mobDpsGrowth: HP мобов обязано расти медленнее их урона. |
| `armorConstantBase` | 60 |  |
| `armorDrCap` | 0.75 |  |
| `resistCap` | 75 |  |
| `echoBase` | 5 |  |
| `echoGrowth` | 1.055 |  |
| `goldBase` | 10 |  |
| `brandMobStatsPerRank` | 0.25 |  |
| `brandLootPerRank` | 0.12 |  |
| `brandEchoPerRank` | 0.24 |  |
| `brandMaxRank` | 30 |  |
| `brandUnlockDepths` | 25, 40, 55, 70, 90 | Ранги выше списка глубин открываются доказательством: спуск на этом ранге должен дойти до brandProofDepth. Плато прогрессии превращается в лестницу. |
| `brandProofDepth` | 80 |  |
| `hireScaleFromDepth` | 85 | С этой глубины задаток наёмника растёт тем же темпом, что доход. Ниже — цена та, что измерена для первых ранов; Оборванец не дорожает никогда. Здесь стояло 60 — вопреки GDD §3.1, раунду 27 и умолчанию в коде, которые все говорят 85. Чем кончается 60, раунд 27 измерил: цена найма индексирована РЕКОРДОМ, а доход — тем, что игрок берёт сейчас, и после одного удачного глубокого спуска цена уходит на порядок вперёд заработка и назад не возвращается. Замер --campaign 40: 60 даёт глубину 90 и Заставу 25/64, 85 — глубину 99 и Заставу 58/64. |
| `startDepthShare` | 0.15 | Доля рекорда, до которой спущена верёвка: спуск начинается там, а не с первого этажа. Задумывалась как экономия времени — замер --hp показал, что на 64 % этажей здоровье не падало ниже 90 %. НО ОНА ЖЕ ЧУТЬ НЕ УБИЛА ИГРУ. Экономика Заставы — самоподдерживающаяся петля: глубже -> больше золота -> выше Застава -> лучше добыча и наёмники -> глубже. Верёвка укорачивает спуск, петля не выходит на самоподдержание, и всё замирает. Замер --campaign 60: при 0.30 глубина встаёт на 58 с двадцатого спуска, Застава 2/64; при 0.15 растёт до 86, Застава 47/64. ОБРЫВ МЕЖДУ 0.18 И 0.20 — не наклон, а порог зажигания: 0.18 даёт 88 этажей, 0.20 даёт 54. Значение выбрано С ЗАПАСОМ от края: править петлю рядом с порогом означает ловить обвал от любой соседней правки. |
| `echoNodeBaseCost` | 30 | Цена узла древа Эха: base * growth^(куплено/4). Растяжение осознанное — за восемь ранов древо выкупалось целиком, и прести́ж-прогрессия кончалась за вечер. |
| `echoNodeCostGrowth` | 2.6 |  |
| `passivePointPerFloors` | 2 |  |
| `passivePointCap` | 60 |  |

## Голый герой

С чем наёмник входит вниз без единой вещи.

<!-- balance: file=balance path=hero kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `maxHp` | 200 |  |
| `hpRegen` | 0.5 |  |
| `maxMana` | 100 | Мана — общий бюджет активных способностей. Кулдаун ограничивает способность поодиночке, мана — все сразу. Базы хватает на две-три дешёвые активки; четыре дорогих пересыхают, и это выбор сборки, а не налог. |
| `manaRegen` | 5 |  |
| `armor` | 25 |  |
| `attackDamage` | 12 |  |
| `spellPower` | 8 | Вторая ось силы. От неё растут способности с тегом «Чары» — и только они. Меньше урона оружия намеренно: у чар нет скорости атаки, зато множители в контенте у них выше, а автоатака от них не растёт вовсе. |
| `attackSpeed` | 1.2 |  |
| `critChance` | 0.05 |  |
| `critMulti` | 0.5 |  |

## Бой и спуск

Тик, волны, отдых, развилки, третий путь.

<!-- balance: file=balance path=combat kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `tickSeconds` | 0.1 |  |
| `spellReferenceRate` | 1.2 | Эталонная частота чар: сила чар × эту величину = урон в секунду, как урон оружия × скорость атаки. Нужна дотам от чар, чтобы горение не считалось по замаху оружия. |
| `chillSeconds` | 2 | Длительность замедления от узла «Стылая хватка». Короче типичной перезарядки: правило вознаграждает частые удары, а не вешает постоянный дебаф на всю волну. |
| `wavesPerFloor` | 3 |  |
| `wavesPerBossFloor` | 1 |  |
| `restSecondsBetweenFloors` | 5 |  |
| `restHealFraction` | 0.35 | Отдых между этажами возвращает эту долю максимума HP. Было 0.35 — и здоровье не двигалось: этаж стоил меньше, чем возвращал отдых, полоска стояла на 95-99 % две трети рана. Замер --hp. |
| `waveTimeoutSeconds` | 3600 |  |
| `stallCheckSeconds` | 30 |  |
| `stallProgressThreshold` | 0.01 |  |
| `abilitySlots` | 4 |  |
| `forkEveryFloors` | 3 |  |
| `forkWaitSeconds` | 45 |  |
| `boldForkLootBonus` | 0 |  |
| `boldForkRarityBonus` | 0 |  |
| `boldForkEchoBonus` | 0.35 |  |
| `sellBonus` | 1.6 |  |

## Добыча

Сундуки, редкости, перцентили, крафтовое сырьё.

<!-- balance: file=balance path=loot kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `chestItemChance` | 0.18 |  |
| `onboardingFloors` | 12 |  |
| `onboardingChestItemChance` | 0.45 |  |
| `bossItems` | 1 |  |
| `bigBossItems` | 1 |  |
| `relicPityFloors` | 60 |  |
| `percentileMin` | 0.65 |  |
| `percentileMax` | 1 |  |
| `extractionPercentilePenalty` | 0.1 |  |
| `twoHandedRollBonus` | 0.5 |  |
| `twoHandedChance` | 0.25 |  |
| `rarityWeights.common` | 46 |  |
| `rarityWeights.uncommon` | 35 |  |
| `rarityWeights.rare` | 15 |  |
| `rarityWeights.relic` | 4 |  |
| `affixSlotsByRarity.common` | 1 |  |
| `affixSlotsByRarity.uncommon` | 2 |  |
| `affixSlotsByRarity.rare` | 3 |  |
| `affixSlotsByRarity.relic` | 4 |  |
| `maxTriggerAffixesPerItem` | 1 |  |
| `itemPowerScale` | 1.25 |  |

## Повадки врагов

Числа за повадками бестиария: замедление, взрыв, отражение.

<!-- balance: file=balance path=traits kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `slowFraction` | 0.2 |  |
| `shredFraction` | 0.3 |  |
| `lifestealFraction` | 0.3 |  |
| `rampPerSecond` | 0.03 |  |
| `rampCap` | 1 |  |
| `explosionFraction` | 1 |  |
| `manaDrainPerHit` | 8 |  |
| `allyHealPerSecond` | 0.012 |  |
| `reflectFraction` | 0.12 |  |
| `hardenPerSecond` | 0.04 |  |
| `hardenCap` | 1.5 |  |

## Кузница

Цены переката и углубления, вместимость верстака.

<!-- balance: file=balance path=crafting kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `rerollCostBase` | 40 |  |
| `rerollCostGrowth` | 1.6 |  |
| `rerollRarityMultiplier.common` | 1 |  |
| `rerollRarityMultiplier.uncommon` | 1.5 |  |
| `rerollRarityMultiplier.rare` | 2.5 |  |
| `rerollRarityMultiplier.relic` | 4 |  |
| `deepenCostBase` | 120 |  |
| `deepenCostGrowth` | 1.35 |  |
| `deepenIlvlStep` | 10 |  |
| `shardCapacityBase` | 12 |  |
| `shardCapacityPerLevel` | 4 |  |

## Застава

Постройки: что даёт уровень и сколько он стоит.

<!-- balance: file=balance path=outpost kind=scalars -->
| ключ | значение | что это |
|---|---|---|
| `baseHireCost` | 250 |  |
| `baseTavernCandidates` | 3 |  |
| `baseSalvageRate` | 0.35 |  |
| `maxBuildingLevel` | 8 |  |
| `depthGatePerLevel` | 12 |  |
| `upgradeCostFloors` | 35 |  |
| `stashSlotsBase` | 40 |  |
| `stashSlotsPerLevel` | 6 |  |
| `lootQualityPerLevel` | 0.1 |  |
| `lootQuantityPerLevel` | 0.06 |  |
| `rerollFloorPerLevel` | 0.1 |  |
| `shardSalvageLevel` | 4 |  |
| `shardSalvageChance` | 0.25 |  |
| `salvageRatePerLevel` | 0.15 |  |
| `forecastFloorsBase` | 3 |  |
| `forecastFloorsPerLevel` | 1 |  |
| `restHealPerLevel` | 0.02 |  |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
