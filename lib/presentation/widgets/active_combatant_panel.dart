import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/actions.dart';
import '../../domain/models/models.dart';
import '../state/turn_engine_notifier.dart';

/// Left bottom panel: the **Active Combatant (Actor)** — the owner of the
/// timeline's active phase ([TurnState.activeCombatantId]).
///
/// Shows the actor's name and Faction badge, the primary stats (SPD, DEX,
/// EGO), active status badges, and the initiative actions (`Declare
/// Haymaker`, `Interrupt with Hold`) bound directly to the actor.
class ActiveCombatantPanel extends ConsumerWidget {
  const ActiveCombatantPanel({super.key});

  static void _execute(
    WidgetRef ref,
    ActionDefinition action,
    String actorId,
  ) {
    try {
      ref
          .read(turnEngineProvider.notifier)
          .executeAction(action, targetId: actorId);
    } on StateError {
      // Non-modal UX: an invalid action is a silent no-op (no dialogs).
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(turnEngineProvider);
    final index = state.combatants.indexWhere(
      (combatant) => combatant.id == state.activeCombatantId,
    );
    final combatant = index < 0 ? null : state.combatants[index];

    return Material(
      key: const Key('active-combatant-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: combatant == null
            ? const _ActorFallback()
            : _ActorDetails(state: state, combatant: combatant),
      ),
    );
  }
}

class _ActorFallback extends StatelessWidget {
  const _ActorFallback();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No Combatant Selected',
      key: Key('detail-no-selection'),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _ActorDetails extends StatelessWidget {
  const _ActorDetails({required this.state, required this.combatant});

  final TurnState state;
  final Combatant combatant;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('actor-detail-${combatant.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              combatant.name,
              key: const Key('detail-name'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            _factionBadge(combatant.team),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          key: const Key('detail-stats'),
          spacing: 16,
          runSpacing: 4,
          children: <Widget>[
            _statCell('SPD', combatant.spdDisplay),
            _statCell('DEX', '${combatant.dex}'),
            _statCell('EGO', '${combatant.ego}'),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          key: const Key('detail-badges'),
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            for (final status in combatant.statusBadges)
              _badgeChip(_badgeLabel(status)),
            if (state.haymakerDeclarations.any(
              (declaration) =>
                  declaration.combatantId == combatant.id &&
                  declaration.declaredTurn == state.turnNumber,
            ))
              _badgeChip('Haymaker Charging'),
          ],
        ),
        const SizedBox(height: 6),
        Consumer(
          builder: (context, ref, child) => Wrap(
            key: const Key('actor-actions'),
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              OutlinedButton(
                key: const Key('actor-action-haymaker'),
                onPressed: () => ActiveCombatantPanel._execute(
                  ref,
                  ActionDefinition.declareHaymaker,
                  combatant.id,
                ),
                child: const Text('Declare Hay[M]aker'),
              ),
              OutlinedButton(
                key: const Key('actor-action-hold'),
                onPressed: () => ActiveCombatantPanel._execute(
                  ref,
                  ActionDefinition.interruptWithHold,
                  combatant.id,
                ),
                child: const Text('Interrupt with [H]old'),
              ),
              OutlinedButton(
                key: const Key('actor-action-clear'),
                onPressed: () =>
                    ref.read(turnEngineProvider.notifier).clearAction(combatant.id),
                child: const Text('[C]lear Action'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _factionBadge(String team) {
    return Container(
      key: const Key('detail-faction'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child:
          Text(team.isEmpty ? '—' : team, style: const TextStyle(fontSize: 11)),
    );
  }

  static Widget _statCell(String label, String value) {
    return SizedBox(
      key: Key('detail-stat-$label'),
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  static Widget _badgeChip(String label) {
    return Container(
      key: Key('detail-badge-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  static String _badgeLabel(PhaseStatus status) {
    switch (status) {
      case PhaseStatus.scheduled:
        return 'Scheduled';
      case PhaseStatus.active:
        return 'Active';
      case PhaseStatus.held:
        return 'Held';
      case PhaseStatus.aborted:
        return 'Aborted';
      case PhaseStatus.spent:
        return 'Spent';
      case PhaseStatus.delayed:
        return 'Delayed';
    }
  }
}