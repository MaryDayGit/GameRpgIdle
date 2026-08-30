# Модификаторы этажей

Каждый модификатор — одна плата и одна награда. Ими же живёт разлом дня и третий путь развилки: он складывает награды обоих путей, так что усиление любого модификатора усиливает и его.

## Восемь путей

<!-- balance: file=floor_modifiers path=modifiers kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `heat` | Жар | `effects.resistFire` | -30 |
| `heat` | Жар | `effects.tagDamageFire` | 0.15 |
| `hunger` | Голод | `effects.regenDisabled` | 1 |
| `hunger` | Голод | `effects.lootQuantity` | 0.4 |
| `vice` | Тиски | `effects.cooldownReduction` | -0.25 |
| `vice` | Тиски | `effects.bossEchoMultiplier` | 2 |
| `abundance` | Изобилие | `effects.mobDps` | 0.2 |
| `abundance` | Изобилие | `effects.lootQuantity` | 0.5 |
| `chill` | Стужа | `effects.resistCold` | -30 |
| `chill` | Стужа | `effects.cooldownReduction` | 0.15 |
| `void_rot` | Пустотная гниль | `effects.resistVoid` | -30 |
| `void_rot` | Пустотная гниль | `effects.chestRarityBonus` | 1 |
| `silence` | Тишина | `effects.aurasDisabled` | 1 |
| `silence` | Тишина | `effects.autoAttackDamage` | 0.5 |
| `swarm` | Рой | `effects.waveMultiplier` | 2 |
| `swarm` | Рой | `effects.packMultiplier` | 2 |
| `swarm` | Рой | `effects.mobHp` | -0.4 |
| `swarm` | Рой | `effects.lootQuantity` | 0.3 |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
