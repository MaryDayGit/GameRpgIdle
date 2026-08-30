# Аффиксы и основы вещей

`base` — значение на первом уровне предмета; дальше оно растёт по кривой вещей, если `scales`. `weight` — как часто аффикс выпадает по сравнению с остальными для того же вида вещи.

## Статовые

<!-- balance: file=affixes_stat path=affixes kind=wide -->
| id | название | `base` | `weight` |
|---|---|---|---|
| `max_hp_flat` | +{value} к максимуму HP | 30 | 12 |
| `max_hp_pct` | +{value:%} к максимуму HP | 0.06 | 6 |
| `hp_regen` | +{value} восстановления HP в секунду | 0.15 | 7 |
| `armor_flat` | +{value} к броне | 6 | 12 |
| `armor_pct` | +{value:%} к броне | 0.08 | 6 |
| `resist_fire` | +{value} к сопротивлению огню | 8 | 9 |
| `resist_cold` | +{value} к сопротивлению холоду | 8 | 9 |
| `resist_lightning` | +{value} к сопротивлению молнии | 8 | 9 |
| `resist_void` | +{value} к сопротивлению пустоте | 8 | 9 |
| `attack_damage_flat` | +{value} к урону оружия | 2 | 12 |
| `spell_power_flat` | +{value} к силе чар | 1.6 | 12 |
| `increased_damage` | +{value:%} к урону | 0.08 | 10 |
| `attack_speed` | +{value:%} к скорости атаки | 0.06 | 9 |
| `crit_chance` | +{value:%} к шансу критического удара | 0.03 | 8 |
| `crit_multi` | +{value:%} к урону критических ударов | 0.15 | 8 |
| `cooldown_reduction` | −{value:%} ко времени перезарядки | 0.05 | 7 |
| `leech` | +{value:%} вампиризма | 0.015 | 5 |
| `damage_element` | +{value:%} {tag} | 0.12 | 18 |
| `damage_form` | +{value:%} {tag} | 0.15 | 9 |
| `damage_delivery` | +{value:%} {tag} | 0.14 | 7 |
| `aura_power` | +{value:%} {tag} | 0.16 | 7 |
| `damage_mechanic` | +{value:%} {tag} | 0.13 | 9 |
| `loot_quality` | +{value:%} к качеству добычи | 0.08 | 5 |
| `loot_quantity` | +{value:%} к количеству добычи | 0.06 | 5 |
| `max_mana_flat` | +{value} к максимуму маны | 25 | 8 |
| `mana_regen` | +{value} восстановления маны в секунду | 1.2 | 7 |


## Триггерные

<!-- balance: file=affixes_trigger path=affixes kind=wide -->
| id | название | `weight` |
|---|---|---|
| `metronome` | Метроном | 10 |
| `discharge` | Разряд | 8 |
| `chase` | Гон | 10 |
| `smoulder` | Тлен | 7 |
| `desperation` | Отчаяние | 6 |
| `double_strike` | Двойной удар | 7 |
| `pestilence` | Мор | 5 |
| `reflection` | Отражение | 7 |
| `vanguard` | Авангард | 9 |
| `blood_tithe` | Кровавая дань | 6 |
| `totem_resonance` | Резонанс тотемов | 5 |
| `frost_chain` | Ледяная цепь | 6 |

Остальные числа:

<!-- balance: file=affixes_trigger path=affixes kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `metronome` | Метроном | `params.n` | 5 |
| `metronome` | Метроном | `params.multiplier` | 2 |
| `discharge` | Разряд | `params.chance` | 0.2 |
| `chase` | Гон | `params.value` | 0.25 |
| `chase` | Гон | `params.duration` | 3 |
| `chase` | Гон | `params.maxStacks` | 5 |
| `smoulder` | Тлен | `params.duration` | 4 |
| `smoulder` | Тлен | `params.dpsFraction` | 0.35 |
| `desperation` | Отчаяние | `params.threshold` | 0.35 |
| `desperation` | Отчаяние | `params.moreDamage` | 0.6 |
| `desperation` | Отчаяние | `params.lessArmor` | 0.4 |
| `double_strike` | Двойной удар | `params.period` | 8 |
| `reflection` | Отражение | `params.chance` | 0.15 |
| `reflection` | Отражение | `params.armorFraction` | 2 |
| `vanguard` | Авангард | `params.moreDamage` | 1.5 |
| `blood_tithe` | Кровавая дань | `params.fraction` | 0.04 |
| `totem_resonance` | Резонанс тотемов | `params.duration` | 0.5 |
| `totem_resonance` | Резонанс тотемов | `params.rate` | 0.25 |
| `frost_chain` | Ледяная цепь | `params.duration` | 3 |
| `frost_chain` | Ледяная цепь | `params.slow` | 0.25 |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
