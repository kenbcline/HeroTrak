import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/matrix_ui_state.dart';
import '../state/turn_engine_notifier.dart';

/// Shows the "Start Next Turn?" (Yes/No) confirmation dialog.
///
/// Returns `true` when the user confirms, `false` when they decline, and
/// `null` when the dialog is dismissed.
Future<bool?> showStartNextTurnDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Start Next Turn?'),
      actions: <Widget>[
        TextButton(
          key: const Key('cancel-start-next-turn'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          key: const Key('confirm-start-next-turn'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
}

/// Requests one forward step, gating the Post-12 → new-Turn transition
/// behind the "Start Next Turn?" confirmation.
///
/// Advancing within the Turn (Segments 1–12) is immediate; advancing past
/// Post-12 into a new Turn only happens when the user confirms. Declining
/// leaves the tracker untouched at Segment 12.
Future<void> requestNextStep(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(turnEngineProvider.notifier);
  if (ref.read(turnEngineProvider).activeSegment < 12) {
    notifier.nextStep();
    return;
  }

  final startNextTurn = await showStartNextTurnDialog(context);
  if (startNextTurn == true) {
    notifier.nextStep();
  }
}

/// Requests one forward timeline step (Right Arrow / Next Phase), staging
/// the end-of-Turn transition behind the "Start Next Turn?" confirmation.
///
/// The walk has three stages:
/// 1. the Turn's remaining phases — immediate;
/// 2. past the last active phase (Segment 12 included), timeline focus steps
///    onto the Post-12 column — immediate, no dialog;
/// 3. with Post-12 selected, the next press asks "Start Next Turn?" and only
///    a confirmation advances to Turn N+1, Segment 1 (clearing the Post-12
///    selection). Declining leaves the tracker untouched at Post-12.
Future<void> requestNextPhaseSlot(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(turnEngineProvider.notifier);
  if (ref.read(selectedColumnProvider) == 'post12') {
    final startNextTurn = await showStartNextTurnDialog(context);
    if (startNextTurn == true) {
      ref.read(selectedColumnProvider.notifier).state = null;
      notifier.startNextTurn();
    }
    return;
  }

  if (notifier.selectNextPhaseSlot()) return;

  // The Turn's phases are exhausted: step timeline focus onto Post-12 and
  // let the next press handle the turn-over confirmation.
  ref.read(selectedColumnProvider.notifier).state = 'post12';
}