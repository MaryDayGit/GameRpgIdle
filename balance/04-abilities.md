# Умения

`cooldown` — перезарядка в секундах, `mana` — цена срабатывания. Остальное лежит в `params` и зависит от вида умения: множитель урона оружия, доля силы чар, число целей, длительность.

Текст умения на экране собирается из этих же чисел, так что править описание отдельно не нужно — оно подставится само.

## Все 55

<!-- balance: file=abilities path=abilities kind=wide -->
| id | название | `cooldown` | `mana` |
|---|---|---|---|
| `cleave` | Рассекающий удар | 3 | 10 |
| `bloodletting` | Кровопуск | 5 | 15 |
| `thirst` | Жажда | 0 |  |
| `fortitude` | Стойкость | 0 |  |
| `blade_echo` | Эхо клинка | 0 |  |
| `frost_spike` | Морозный шип | 4 | 12 |
| `sunder` | Раскол | 5 | 15 |
| `ember_burst` | Всполох | 5 | 15 |
| `field_dressing` | Перевязка | 14 | 40 |
| `spiked_guard` | Шипы | 0 |  |
| `spark_bolt` | Разряд | 3 | 10 |
| `flame_lash` | Огненный хлыст | 4 | 12 |
| `void_lance` | Копьё пустоты | 4 | 12 |
| `glacier_shard` | Осколок глетчера | 7 | 22 |
| `arc_lash` | Дуга молний | 6 | 20 |
| `ember_infusion` | Пламя на клинке | 0 |  |
| `rime_infusion` | Иней на клинке | 0 |  |
| `storm_infusion` | Гроза на клинке | 0 |  |
| `void_infusion` | Пустота на клинке | 0 |  |
| `fire_brand` | Огненное клеймо | 6 | 20 |
| `hex_of_frailty` | Порча хрупкости | 8 | 26 |
| `conduction` | Проводимость | 8 | 26 |
| `venom` | Яд | 6 | 20 |
| `pyre` | Погребальный костёр | 8 | 26 |
| `hoarfrost` | Изморозь | 7 | 22 |
| `static_field` | Статическое поле | 7 | 22 |
| `impale` | Пронзание | 7 | 22 |
| `frost_chain_bolt` | Ледяная дуга | 6 | 20 |
| `rift` | Разлом | 9 | 28 |
| `whirlwind` | Вихрь клинков | 8 | 26 |
| `coup_de_grace` | Милосердие | 7 | 22 |
| `cinder_totem` | Тотем углей | 12 | 34 |
| `winter_totem` | Тотем стужи | 12 | 34 |
| `thunder_totem` | Громовой тотем | 13 | 38 |
| `null_totem` | Тотем безмолвия | 12 | 34 |
| `overcharge` | Перегрузка | 0 |  |
| `entropy` | Энтропия | 0 |  |
| `storm_call` | Зов бури | 10 | 30 |
| `ashfield` | Пепелище | 0 |  |
| `frost_bite` | Обморожение | 0 |  |
| `abyss_seal` | Печать бездны | 0 |  |
| `totem_of_fury` | Тотем ярости | 14 | 40 |
| `battle_focus` | Сосредоточение | 16 | 50 |
| `berserk_rush` | Натиск | 18 | 52 |
| `butcher` | Мясник | 0 |  |
| `second_wind_blade` | Второй клинок | 0 |  |
| `last_stand` | Последний рубеж | 0 |  |
| `frost_shroud` | Ледяной покров | 0 |  |
| `war_cry` | Клич ярости | 0 |  |
| `stone_stance` | Каменная стойка | 0 |  |
| `blood_oath` | Кровавый обет | 0 |  |
| `hunters_mark` | Метка охотника | 0 |  |
| `wardens_vigil` | Дозор | 0 |  |
| `quickened_mind` | Ускоренный разум | 0 |  |
| `mana_font` | Родник маны | 0 |  |

Остальные числа:

<!-- balance: file=abilities path=abilities kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `cleave` | Рассекающий удар | `params.weaponMultiplier` | 2.64 |
| `cleave` | Рассекающий удар | `params.targets` | 1 |
| `bloodletting` | Кровопуск | `params.weaponMultiplier` | 1.2 |
| `bloodletting` | Кровопуск | `params.duration` | 5 |
| `bloodletting` | Кровопуск | `params.dpsFraction` | 0.66 |
| `thirst` | Жажда | `params.threshold` | 0.5 |
| `thirst` | Жажда | `params.leechMultiplier` | 2 |
| `fortitude` | Стойкость | `params.armorPct` | 0.4 |
| `fortitude` | Стойкость | `params.attackSpeedPct` | -0.15 |
| `blade_echo` | Эхо клинка | `params.chance` | 0.2 |
| `frost_spike` | Морозный шип | `params.weaponMultiplier` | 3.24 |
| `frost_spike` | Морозный шип | `params.targets` | 1 |
| `frost_spike` | Морозный шип | `params.bonusVsSlowed` | 0.5 |
| `sunder` | Раскол | `params.weaponMultiplier` | 1.9 |
| `sunder` | Раскол | `params.targets` | 3 |
| `ember_burst` | Всполох | `params.weaponMultiplier` | 2.55 |
| `ember_burst` | Всполох | `params.targets` | 3 |
| `field_dressing` | Перевязка | `params.fractionOfMaxHp` | 0.12 |
| `spiked_guard` | Шипы | `params.fractionReturned` | 0.25 |
| `spark_bolt` | Разряд | `params.weaponMultiplier` | 2.9 |
| `spark_bolt` | Разряд | `params.targets` | 1 |
| `flame_lash` | Огненный хлыст | `params.weaponMultiplier` | 2.3 |
| `flame_lash` | Огненный хлыст | `params.targets` | 1 |
| `void_lance` | Копьё пустоты | `params.weaponMultiplier` | 3.45 |
| `void_lance` | Копьё пустоты | `params.targets` | 1 |
| `glacier_shard` | Осколок глетчера | `params.weaponMultiplier` | 2.4 |
| `glacier_shard` | Осколок глетчера | `params.targets` | 4 |
| `glacier_shard` | Осколок глетчера | `params.bonusVsSlowed` | 0.6 |
| `arc_lash` | Дуга молний | `params.weaponMultiplier` | 2.4 |
| `arc_lash` | Дуга молний | `params.targets` | 5 |
| `arc_lash` | Дуга молний | `params.falloff` | 0.2 |
| `ember_infusion` | Пламя на клинке | `params.moreDamage` | 0.1 |
| `rime_infusion` | Иней на клинке | `params.moreDamage` | 0.06 |
| `storm_infusion` | Гроза на клинке | `params.moreDamage` | 0.08 |
| `void_infusion` | Пустота на клинке | `params.moreDamage` | 0.12 |
| `fire_brand` | Огненное клеймо | `params.weaponMultiplier` | 1.44 |
| `fire_brand` | Огненное клеймо | `params.duration` | 6 |
| `fire_brand` | Огненное клеймо | `params.damageTakenIncrease` | 0.2 |
| `hex_of_frailty` | Порча хрупкости | `params.weaponMultiplier` | 0.9 |
| `hex_of_frailty` | Порча хрупкости | `params.duration` | 8 |
| `hex_of_frailty` | Порча хрупкости | `params.damageTakenIncrease` | 0.3 |
| `conduction` | Проводимость | `params.weaponMultiplier` | 1.2 |
| `conduction` | Проводимость | `params.duration` | 7 |
| `conduction` | Проводимость | `params.damageTakenIncrease` | 0.28 |
| `venom` | Яд | `params.weaponMultiplier` | 1.2 |
| `venom` | Яд | `params.duration` | 7 |
| `venom` | Яд | `params.dpsFraction` | 0.5 |
| `pyre` | Погребальный костёр | `params.weaponMultiplier` | 1.2 |
| `pyre` | Погребальный костёр | `params.duration` | 6 |
| `pyre` | Погребальный костёр | `params.dpsFraction` | 0.85 |
| `hoarfrost` | Изморозь | `params.weaponMultiplier` | 1 |
| `hoarfrost` | Изморозь | `params.duration` | 6 |
| `hoarfrost` | Изморозь | `params.dpsFraction` | 0.6 |
| `static_field` | Статическое поле | `params.weaponMultiplier` | 0.9 |
| `static_field` | Статическое поле | `params.duration` | 6 |
| `static_field` | Статическое поле | `params.dpsFraction` | 0.7 |
| `impale` | Пронзание | `params.weaponMultiplier` | 1.5 |
| `impale` | Пронзание | `params.duration` | 8 |
| `impale` | Пронзание | `params.dpsFraction` | 0.5 |
| `frost_chain_bolt` | Ледяная дуга | `params.weaponMultiplier` | 2.7 |
| `frost_chain_bolt` | Ледяная дуга | `params.targets` | 4 |
| `frost_chain_bolt` | Ледяная дуга | `params.falloff` | 0.25 |
| `rift` | Разлом | `params.weaponMultiplier` | 2.88 |
| `rift` | Разлом | `params.targets` | 99 |
| `whirlwind` | Вихрь клинков | `params.weaponMultiplier` | 1.45 |
| `whirlwind` | Вихрь клинков | `params.targets` | 6 |
| `coup_de_grace` | Милосердие | `params.weaponMultiplier` | 2.2 |
| `coup_de_grace` | Милосердие | `params.threshold` | 0.35 |
| `coup_de_grace` | Милосердие | `params.bonusBelow` | 1.5 |
| `cinder_totem` | Тотем углей | `params.weaponMultiplier` | 1.1 |
| `cinder_totem` | Тотем углей | `params.duration` | 10 |
| `cinder_totem` | Тотем углей | `params.interval` | 1.2 |
| `cinder_totem` | Тотем углей | `params.targets` | 2 |
| `winter_totem` | Тотем стужи | `params.weaponMultiplier` | 1.2 |
| `winter_totem` | Тотем стужи | `params.duration` | 10 |
| `winter_totem` | Тотем стужи | `params.interval` | 1.5 |
| `winter_totem` | Тотем стужи | `params.targets` | 1 |
| `thunder_totem` | Громовой тотем | `params.weaponMultiplier` | 1.4 |
| `thunder_totem` | Громовой тотем | `params.duration` | 9 |
| `thunder_totem` | Громовой тотем | `params.interval` | 1.4 |
| `thunder_totem` | Громовой тотем | `params.targets` | 2 |
| `null_totem` | Тотем безмолвия | `params.weaponMultiplier` | 1.3 |
| `null_totem` | Тотем безмолвия | `params.duration` | 10 |
| `null_totem` | Тотем безмолвия | `params.interval` | 1.6 |
| `null_totem` | Тотем безмолвия | `params.targets` | 1 |
| `overcharge` | Перегрузка | `params.chance` | 0.18 |
| `entropy` | Энтропия | `params.chance` | 0.12 |
| `storm_call` | Зов бури | `params.weaponMultiplier` | 2.2 |
| `storm_call` | Зов бури | `params.targets` | 99 |
| `ashfield` | Пепелище | `params.duration` | 3 |
| `ashfield` | Пепелище | `params.dpsFraction` | 0.36 |
| `frost_bite` | Обморожение | `params.duration` | 4 |
| `frost_bite` | Обморожение | `params.dpsFraction` | 0.3 |
| `abyss_seal` | Печать бездны | `params.fractionOfMaxHp` | 0.25 |
| `totem_of_fury` | Тотем ярости | `params.value` | 0.3 |
| `totem_of_fury` | Тотем ярости | `params.duration` | 8 |
| `battle_focus` | Сосредоточение | `params.value` | 0.45 |
| `battle_focus` | Сосредоточение | `params.duration` | 8 |
| `berserk_rush` | Натиск | `params.value` | 0.5 |
| `berserk_rush` | Натиск | `params.duration` | 6 |
| `butcher` | Мясник | `params.armorPct` | -0.2 |
| `butcher` | Мясник | `params.attackSpeedPct` | 0.25 |
| `second_wind_blade` | Второй клинок | `params.chance` | 0.12 |
| `last_stand` | Последний рубеж | `params.threshold` | 0.4 |
| `last_stand` | Последний рубеж | `params.lessDamageTaken` | 0.2 |
| `frost_shroud` | Ледяной покров | `params.slow` | 0.25 |
| `frost_shroud` | Ледяной покров | `reserve` | 0.25 |
| `war_cry` | Клич ярости | `reserve` | 0.35 |
| `war_cry` | Клич ярости | `params.value` | 0.3 |
| `stone_stance` | Каменная стойка | `reserve` | 0.3 |
| `stone_stance` | Каменная стойка | `params.value` | 0.45 |
| `blood_oath` | Кровавый обет | `reserve` | 0.4 |
| `blood_oath` | Кровавый обет | `params.value` | 0.025 |
| `hunters_mark` | Метка охотника | `reserve` | 0.25 |
| `hunters_mark` | Метка охотника | `params.value` | 0.08 |
| `wardens_vigil` | Дозор | `reserve` | 0.2 |
| `wardens_vigil` | Дозор | `params.value` | 25 |
| `quickened_mind` | Ускоренный разум | `reserve` | 0.35 |
| `quickened_mind` | Ускоренный разум | `params.value` | 0.18 |
| `mana_font` | Родник маны | `reserve` | 0.15 |
| `mana_font` | Родник маны | `params.value` | 4 |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
