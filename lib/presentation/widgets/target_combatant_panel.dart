import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/actions.dart';
import '../../domain/models/models.dart';
import '../state/turn_engine_notifier.dart';

/// Right bottom panel: the **Target Combatant (Actee)** — the subject of
/// reactions and status management ([TurnState.targetCombatantId]).
///
/// Shows the target's name and Faction badge, the real-time OCV/DCV
/// tactical modifiers, the `[A]bort to Defensive Action` reaction (applied
/// to the target immediately, clearing any pending Haymakers, without
/// advancing the timeline clock) and the un-bracketed status toggles
/// (`OK`, `STUN`, `DYING`, `KO`, `DEAD`).
class TargetCombatantPanel extends ConsumerWidget {
  const TargetCombatantPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(turnEngineProvider);
    final index = state.combatants.indexWhere(
      (combatant) => combatant.id == state.targetCombatantId,
    );
    final combatant = index < 0 ? null : state.combatants[index];

    return Material(
      key: const Key('target-combatant-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: combatant == null
            ? const _TargetFallback()
            : _TargetDetails(
                state: state,
                combatant: combatant,
                onStatusSelected: (status) => ref
                    .read(turnEngineProvider.notifier)
                    .toggleCombatantStatus(combatant.id, status),
                onAbort: () {
                  try {
                    ref.read(turnEngineProvider.notifier).executeAction(
                          ActionDefinition.abortToDefensiveAction,
                          targetId: combatant.id,
                        );
                  } on StateError {
                    // Non-modal UX: an invalid reaction is a silent no-op.
                  }
                },
                onAdjustSpd: (change) => ref
                    .read(turnEngineProvider.notifier)
                    .adjustSpdDelta(combatant.id, change),
                onClearReaction: () => ref
                    .read(turnEngineProvider.notifier)
                    .clearReaction(combatant.id),
              ),
      ),
    );
  }
}

class _TargetFallback extends StatelessWidget {
  const _TargetFallback();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No Target Selected',
      key: Key('target-no-selection'),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _TargetDetails extends StatelessWidget {
  const _TargetDetails({
    required this.state,
    required this.combatant,
    required this.onStatusSelected,
    required this.onAbort,
    required this.onAdjustSpd,
    required this.onClearReaction,
  });

  final TurnState state;
  final Combatant combatant;
  final ValueChanged<CombatantStatus> onStatusSelected;
  final VoidCallback onAbort;
  final ValueChanged<int> onAdjustSpd;
  final VoidCallback onClearReaction;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('target-detail-${combatant.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              combatant.name,
              key: const Key('target-name'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              key: const Key('target-faction'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                combatant.team.isEmpty ? '—' : combatant.team,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          key: const Key('tactical-status-box'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: Text(
            _tacticalRule(combatant.status),
            key: const Key('tactical-status-rule'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          key: const Key('target-spd-controls'),
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              key: const Key('target-stat-SPD'),
              width: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'SPD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    combatant.spdDisplay,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              key: const Key('target-spd-plus'),
              onPressed: () => onAdjustSpd(1),
              child: const Text('SPD +1'),
            ),
            OutlinedButton(
              key: const Key('target-spd-minus'),
              onPressed: () => onAdjustSpd(-1),
              child: const Text('SPD -1'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            OutlinedButton(
              key: const Key('target-action-abort'),
              onPressed: onAbort,
              child: const Text('[A]bort to Defensive Action'),
            ),
            OutlinedButton(
              key: const Key('target-clear-reaction'),
              onPressed: onClearReaction,
              child: const Text('Clear Reaction'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          key: const Key('detail-status-buttons'),
          children: <Widget>[
            _statusButton('OK', CombatantStatus.normal),
            const SizedBox(width: 6),
            _statusButton('STUN', CombatantStatus.stunned),
            const SizedBox(width: 6),
            _statusButton('DYING', CombatantStatus.dying),
            const SizedBox(width: 6),
            _statusButton('KO', CombatantStatus.knockedOut),
            const SizedBox(width: 6),
            _statusButton('DEAD', CombatantStatus.dead),
          ],
        ),
      ],
    );
  }

  static String _tacticalRule(CombatantStatus status) {
    switch (status) {
      case CombatantStatus.normal:
        return 'Full OCV / Full DCV';
      case CombatantStatus.stunned:
        return '1/2 DCV | Action consumed to clear Stun on next phase';
      case CombatantStatus.knockedOut:
      case CombatantStatus.dying:
        return '0 OCV / 0 DCV | Unconscious / Bleeding (-1 BOD on Post-12)';
      case CombatantStatus.dead:
        return '0 OCV / 0 DCV | Dead';
    }
  }

  Widget _statusButton(String label, CombatantStatus value) {
    final isActive = combatant.status == value;
    return OutlinedButton(
      key: Key('detail-status-$label'),
      onPressed: () => onStatusSelected(value),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? Colors.teal.shade100 : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}