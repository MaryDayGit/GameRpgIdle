# Враги и боссы

Множители считаются от кривой этажа, а не задаются числом: `hpMult` 0.6 значит «шесть десятых обычного HP этого этажа». Поэтому мобов можно переставлять между собой, не трогая кривые.

`weight` — вес в выпадении: чем больше, тем чаще встречается.

## Обычные

<!-- balance: file=enemies path=enemies kind=wide -->
| id | название | `hpMult` | `dpsMult` | `attackSpeed` | `armorMult` | `packMin` | `packMax` | `weight` |
|---|---|---|---|---|---|---|---|---|
| `scavenger` | Падальщик | 0.6 | 0.25 | 1.4 | 0 | 3 | 5 | 30 |
| `bonebreaker` | Костолом | 1.8 | 0.75 | 0.5 | 0.15 | 1 | 2 | 18 |
| `ash_eater` | Пеплоед | 0.9 | 0.45 | 1 | 0.05 | 2 | 4 | 18 |
| `frost_warden` | Ледяной страж | 1.3 | 0.35 | 0.8 | 0.3 | 1 | 3 | 12 |
| `void_whisperer` | Пустотный шептун | 0.8 | 0.4 | 1.1 | 0 | 2 | 3 | 10 |
| `blood_leech` | Кровавая пиявка | 1.1 | 0.4 | 1.2 | 0 | 2 | 3 | 10 |
| `stone_fist` | Каменный кулак | 1.87 | 0.504 | 0.6 | 1.4 | 1 | 2 | 9 |
| `rot_howler` | Гнилой ревун | 1.02 | 0.216 | 1 | 0.2 | 1 | 2 | 7 |
| `grave_swarm` | Могильный рой | 0.34 | 0.144 | 1.8 | 0 | 5 | 8 | 24 |
| `cinderling` | Головня | 0.595 | 0.36 | 1.2 | 0 | 3 | 5 | 12 |
| `forge_smith` | Пепельный кузнец | 1.36 | 0.396 | 0.8 | 1 | 1 | 2 | 8 |
| `rime_horror` | Инеевая тварь | 0.85 | 0.288 | 0.9 | 0.3 | 2 | 4 | 12 |
| `frost_maw` | Морозная пасть | 1.19 | 0.324 | 0.8 | 0.4 | 1 | 3 | 10 |
| `sparkling` | Искровик | 0.425 | 0.252 | 1.9 | 0 | 3 | 6 | 22 |
| `storm_warden` | Громовой страж | 1.275 | 0.36 | 0.9 | 0.6 | 1 | 2 | 8 |
| `arc_leech` | Разрядник | 0.85 | 0.288 | 1.1 | 0.2 | 2 | 3 | 10 |
| `void_reaper` | Пустотный жнец | 1.105 | 0.396 | 0.9 | 0.3 | 1 | 3 | 9 |
| `mana_eater` | Иссушитель | 0.935 | 0.252 | 1 | 0.2 | 2 | 3 | 8 |
| `rift_shade` | Расколотая тень | 0.765 | 0.324 | 1.2 | 0.1 | 2 | 4 | 9 |

Остальные числа:

<!-- balance: file=enemies path=enemies kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `ash_eater` | Пеплоед | `resists.fire` | 40 |
| `ash_eater` | Пеплоед | `resists.cold` | -25 |
| `frost_warden` | Ледяной страж | `resists.cold` | 40 |
| `void_whisperer` | Пустотный шептун | `resists.voidType` | 35 |
| `stone_fist` | Каменный кулак | `resists.fire` | 17.5 |
| `stone_fist` | Каменный кулак | `resists.lightning` | -35 |
| `rot_howler` | Гнилой ревун | `resists.voidType` | 17.5 |
| `rot_howler` | Гнилой ревун | `resists.fire` | -30 |
| `cinderling` | Головня | `resists.fire` | 24.5 |
| `cinderling` | Головня | `resists.cold` | -40 |
| `forge_smith` | Пепельный кузнец | `resists.fire` | 31.5 |
| `forge_smith` | Пепельный кузнец | `resists.cold` | -30 |
| `rime_horror` | Инеевая тварь | `resists.cold` | 28 |
| `rime_horror` | Инеевая тварь | `resists.fire` | -35 |
| `frost_maw` | Морозная пасть | `resists.cold` | 24.5 |
| `frost_maw` | Морозная пасть | `resists.lightning` | -25 |
| `sparkling` | Искровик | `resists.lightning` | 28 |
| `sparkling` | Искровик | `resists.voidType` | -30 |
| `storm_warden` | Громовой страж | `resists.lightning` | 31.5 |
| `storm_warden` | Громовой страж | `resists.cold` | -25 |
| `arc_leech` | Разрядник | `resists.lightning` | 24.5 |
| `arc_leech` | Разрядник | `resists.physical` | -20 |
| `void_reaper` | Пустотный жнец | `resists.voidType` | 28 |
| `void_reaper` | Пустотный жнец | `resists.lightning` | -30 |
| `mana_eater` | Иссушитель | `resists.voidType` | 24.5 |
| `mana_eater` | Иссушитель | `resists.fire` | -25 |
| `rift_shade` | Расколотая тень | `resists.voidType` | 21 |
| `rift_shade` | Расколотая тень | `resists.physical` | -25 |

## Боссы

<!-- balance: file=enemies path=bosses kind=wide -->
| id | название | `everyFloors` | `hpMult` | `dpsMult` | `attackSpeed` | `armorMult` | `resists.fire` | `resists.cold` |
|---|---|---|---|---|---|---|---|---|
| `ash_lord` | Владыка Пепла | 5 | 4 | 0.8 | 0.7 | 0.2 | 40 |  |
| `void_devourer` | Пустотный Пожиратель | 10 | 6.5 | 1 | 0.6 | 0.3 |  |  |
| `storm_sovereign` | Громовой Владыка | 15 | 5 | 0.9 | 0.9 | 1.2 |  | -25 |
| `frost_patriarch` | Ледяной Патриарх | 25 | 5.5 | 0.85 | 0.7 | 1.5 | -30 | 50 |

Остальные числа:

<!-- balance: file=enemies path=bosses kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `void_devourer` | Пустотный Пожиратель | `resists.voidType` | 40 |
| `storm_sovereign` | Громовой Владыка | `resists.lightning` | 45 |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
