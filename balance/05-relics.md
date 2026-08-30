# Реликты

Реликт меняет правило боя, а числа при нём — цена и размер этого правила. Что именно делает реликт, задаёт поле `effect` в JSON: его тут нет намеренно, это не баланс, а код.

## Двадцать пять

<!-- balance: file=relics path=relics kind=long -->
| id | название | параметр | значение |
|---|---|---|---|
| `ash_covenant` | Пепельный завет | `params.maxStacks` | 5 |
| `ash_covenant` | Пепельный завет | `params.directFirePenalty` | 0.5 |
| `split_counterweight` | Расколотый противовес | `params.maxHpPenalty` | 0.4 |
| `crown_of_obsession` | Венец одержимого | `params.cooldownReduction` | 0.7 |
| `skin_of_despair` | Кожа отчаяния | `params.maxHpPenalty` | 0.65 |
| `skin_of_despair` | Кожа отчаяния | `params.leechMultiplier` | 2 |
| `counter_of_moments` | Счётчик мгновений | `params.rate` | 2 |
| `boots_of_descent` | Сапоги нисходящего | `params.waveReduction` | 1 |
| `seal_of_thousand_eyes` | Печать тысячи глаз | `params.uncursedPenalty` | 0.6 |
| `charm_of_silence` | Оберег молчания | `params.passivesPerSlot` | 2 |
| `mask_of_certainty` | Маска неизбежности | `params.damagePenalty` | 0.45 |
| `first_blood_gauntlet` | Перчатка первой крови | `params.multiplier` | 3 |
| `first_blood_gauntlet` | Перчатка первой крови | `params.penalty` | 0.25 |
| `reaper_edge` | Жатва | `params.threshold` | 0.18 |
| `reaper_edge` | Жатва | `params.damagePenalty` | 0.3 |
| `hide_of_prisms` | Шкура призм | `params.resistAll` | 45 |
| `glass_crown` | Стеклянный венец | `params.damageBonus` | 0.7 |
| `glass_crown` | Стеклянный венец | `params.maxHpPenalty` | 0.55 |
| `scarred_pact` | Клятый договор | `params.perHit` | 0.05 |
| `scarred_pact` | Клятый договор | `params.maxStacks` | 8 |
| `blood_oath_ring` | Кровавый обет | `params.leechMultiplier` | 3 |
| `endless_censer` | Бесконечная кадильница | `params.cooldownMultiplier` | 2 |
| `seal_of_haste` | Печать спешки | `params.cooldownMultiplier` | 0.5 |
| `seal_of_haste` | Печать спешки | `params.manaCostMultiplier` | 2 |
| `ember_conduit` | Проводник пепла | `params.damageBonus` | 0.3 |
| `ember_conduit` | Проводник пепла | `params.resistPenalty` | 50 |
| `rime_conduit` | Проводник инея | `params.damageBonus` | 0.3 |
| `rime_conduit` | Проводник инея | `params.resistPenalty` | 50 |
| `storm_conduit` | Проводник грозы | `params.damageBonus` | 0.3 |
| `storm_conduit` | Проводник грозы | `params.resistPenalty` | 50 |
| `void_conduit` | Проводник пустоты | `params.damageBonus` | 0.3 |
| `void_conduit` | Проводник пустоты | `params.resistPenalty` | 50 |
| `tireless_boots` | Неутомимые сапоги | `params.waveReduction` | 1 |
| `horn_of_the_hunt` | Рог охоты | `params.bossReward` | 2 |
| `horn_of_the_hunt` | Рог охоты | `params.mobHp` | 0.35 |
| `rope_of_the_deep` | Канат глубин | `params.floors` | 10 |
| `rope_of_the_deep` | Канат глубин | `params.maxHpPenalty` | 0.3 |

---

Правится только колонка со значением. Как применить — [в оглавлении](README.md).
