import 'package:flutter/material.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/build_power.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/mercenary.dart';

import 'format.dart';
import 'gear_grid.dart';
import 'mercenary_stats.dart';

/// Карточка наёмника перед решением.
///
/// Нанимать вслепую нельзя: ранг и черта — это цифры, а в списке они выглядят
/// как слова. Здесь показано, что игрок на самом деле покупает: сила билда,
/// запас прочности, урон, броня и что именно делает черта.
///
/// Отсюда же вход в сборку билда — иначе его попросту не находят: экран
/// открывался по нажатию на имя, и об этом никто не догадывался.
Future<void> showMercenarySheet(
  BuildContext context, {
  required Mercenary merc,
  required int depth,
  String? hireLabel,
  VoidCallback? onHire,
  VoidCallback? onBuild,
  VoidCallback? onDeploy,
  String? note,
  int abilitySlots = 4,
  HeroProfile Function()? profileFor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MercBody(
      merc: merc,
      depth: depth,
      hireLabel: hireLabel,
      onHire: onHire,
      onBuild: onBuild,
      onDeploy: onDeploy,
      note: note,
      abilitySlots: abilitySlots,
      profileFor: profileFor,
    ),
  );
}

class _MercBody extends StatelessWidget {
  const _MercBody({
    required this.merc,
    required this.depth,
    this.hireLabel,
    this.onHire,
    this.onBuild,
    this.abilitySlots = 4,
    this.profileFor,
    this.onDeploy,
    this.note,
  });

  final Mercenary merc;
  final int depth;
  final String? hireLabel;
  final VoidCallback? onHire;
  final VoidCallback? onBuild;

  /// Сколько слотов способностей у игрока: базовые плюс узел древа.
  final int abilitySlots;

  /// Как собрать боевой профиль наёмника. Приходит снаружи, потому что
  /// деревья принадлежат ИГРОКУ, а не наёмнику: без них карточка показывала
  /// бы силу билда, с которой он вниз не пойдёт.
  final HeroProfile Function()? profileFor;
  final VoidCallback? onDeploy;
  final String? note;

  @override
  Widget build(BuildContext context) {
    // Профиль считается один раз и на всё: и на числа в карточке, и на
    // полный лист. Второй вызов дал бы другой объект, а расхождение между
    // «Силой сборки» здесь и «Броня» там игрок прочитал бы как ошибку.
    final profile = (profileFor ?? merc.toProfile).call();
    final stats = profile.aggregate();
    final abilities = [
      for (final id in merc.abilities) ContentPack.current.ability(id),
    ].whereType<Object>().toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(merc.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${merc.rank.forGender(merc.gender)} · '
              'рюкзак ${merc.backpackSlots} предметов',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                _Stat(
                    'Сила сборки',
                    money(BuildPower.of(stats, depth,
                        loadout: BuildPower.loadoutOf(merc.abilities)))),
                _Stat('HP', money(stats.maxHp)),
                _Stat('Урон', money(stats.attackDamage)),
                _Stat('Броня', money(stats.armor)),
              ],
            ),
            const SizedBox(height: 16),

            _Line('Черта', merc.trait.forGender(merc.gender)),
            Text(
              merc.trait.description,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            _Line('Умения',
                '${merc.abilities.length} из $abilitySlots'),
            Text(
              abilities.isEmpty
                  ? 'Слоты пусты'
                  : merc.abilities
                      .map((id) => ContentPack.current.ability(id)?.name ?? id)
                      .join(', '),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            _Line('Снаряжение',
                '${merc.gear.filledSlots} из ${merc.gear.usableSlots} слотов'),
            const SizedBox(height: 8),
            GearGrid(equipment: merc.gear, compact: true),

            if (note != null) ...[
              const SizedBox(height: 12),
              Text(note!,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.orangeAccent)),
            ],

            const SizedBox(height: 20),
            // Полный лист характеристик стоит рядом с «Отправить в бездну»,
            // потому что решение принимается ЗДЕСЬ. Четыре числа выше
            // отвечают на «стало лучше или хуже»; перед спуском игрок
            // спрашивает другое — хватит ли сопротивлений, куда ушла мана.
            OutlinedButton.icon(
              onPressed: () => MercenaryStatsSheet.show(
                context,
                mercenary: merc,
                profile: profile,
                depth: depth,
              ),
              icon: const Icon(Icons.bar_chart_outlined, size: 18),
              label: const Text('Характеристики целиком'),
            ),
            const SizedBox(height: 8),
            if (onBuild != null)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onBuild!();
                },
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: const Text('Сборка: снаряжение и умения'),
              ),
            if (onHire != null) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onHire!();
                },
                child: Text(hireLabel ?? 'Нанять'),
              ),
            ],
            if (onDeploy != null) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onDeploy!();
                },
                child: const Text('Отправить в бездну'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            Text(value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
