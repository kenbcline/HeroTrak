import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/actions/actions.dart';
import 'package:herotrak/domain/models/models.dart';

/// Builds an [ActionMutation] through runtime parameters so constructor
/// asserts are exercised at runtime rather than at compile time.
ActionMutation makeMutation(
  ActionMutationType type, {
  int? targetSegment,
  PhaseStatus? status,
  String? queueOverride,
}) {
  return ActionMutation(
    type: type,
    targetSegment: targetSegment,
    status: status,
    queueOverride: queueOverride,
  );
}

void main() {
  group('ActionMutationType', () {
    test('exposes exactly the four primitive state changes', () {
      expect(ActionMutationType.values, [
        ActionMutationType.consumeNextPhase,
        ActionMutationType.relocatePhase,
        ActionMutationType.applyStatusBadge,
        ActionMutationType.insertQueueOverride,
      ]);
    });
  });

  group('ActionMutation factories', () {
    test('consumeNextPhase carries no payload', () {
      const mutation = ActionMutation.consumeNextPhase();
      expect(mutation.type, ActionMutationType.consumeNextPhase);
      expect(mutation.targetSegment, isNull);
      expect(mutation.status, isNull);
      expect(mutation.queueOverride, isNull);
    });

    test('relocatePhase carries the target segment', () {
      const mutation = ActionMutation.relocatePhase(targetSegment: 10);
      expect(mutation.type, ActionMutationType.relocatePhase);
      expect(mutation.targetSegment, 10);
    });

    test('applyStatusBadge carries the status', () {
      const mutation = ActionMutation.applyStatusBadge(
        status: PhaseStatus.aborted,
      );
      expect(mutation.type, ActionMutationType.applyStatusBadge);
      expect(mutation.status, PhaseStatus.aborted);
    });

    test('insertQueueOverride carries the override descriptor', () {
      const mutation = ActionMutation.insertQueueOverride(
        queueOverride: 'hold_interrupt',
      );
      expect(mutation.type, ActionMutationType.insertQueueOverride);
      expect(mutation.queueOverride, 'hold_interrupt');
    });
  });

  group('ActionMutation validation', () {
    test('relocatePhase without a target segment asserts', () {
      expect(
        () => makeMutation(ActionMutationType.relocatePhase),
        throwsA(isA<AssertionError>()),
      );
    });

    test('relocatePhase outside segment 1-12 asserts', () {
      expect(
        () => makeMutation(ActionMutationType.relocatePhase, targetSegment: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => makeMutation(ActionMutationType.relocatePhase, targetSegment: 13),
        throwsA(isA<AssertionError>()),
      );
    });

    test('applyStatusBadge without a status asserts', () {
      expect(
        () => makeMutation(ActionMutationType.applyStatusBadge),
        throwsA(isA<AssertionError>()),
      );
    });

    test('insertQueueOverride without a queue override asserts', () {
      expect(
        () => makeMutation(ActionMutationType.insertQueueOverride),
        throwsA(isA<AssertionError>()),
      );
    });

    test('consumeNextPhase requires no payload and never asserts', () {
      expect(
        makeMutation(ActionMutationType.consumeNextPhase),
        const ActionMutation.consumeNextPhase(),
      );
    });
  });

  group('ActionMutation equality', () {
    test('identical factories produce equal values', () {
      expect(
        const ActionMutation.relocatePhase(targetSegment: 5),
        const ActionMutation.relocatePhase(targetSegment: 5),
      );
    });

    test('different payloads are not equal', () {
      expect(
        const ActionMutation.relocatePhase(targetSegment: 5),
        isNot(const ActionMutation.relocatePhase(targetSegment: 6)),
      );
    });
  });

  group('ActionDefinition structure', () {
    test('standard actions expose stable ids, labels, and hotkeys', () {
      expect(ActionDefinition.standardActions.map((a) => a.id).toList(), [
        'abort_to_defensive_action',
        'declare_haymaker',
        'interrupt_with_hold',
      ]);
      expect(ActionDefinition.standardActions.map((a) => a.label).toList(), [
        'Abort to Defensive Action',
        'Declare Haymaker',
        'Interrupt with Hold',
      ]);
      expect(ActionDefinition.standardActions.map((a) => a.hotkey).toList(), [
        'a',
        'm',
        'h',
      ]);
    });

    test('all standard actions target self', () {
      for (final action in ActionDefinition.standardActions) {
        expect(action.targetType, ActionTargetType.self);
      }
    });

    test('abort to defensive action badges aborted and consumes the phase', () {
      expect(ActionDefinition.abortToDefensiveAction.mutations, const [
        ActionMutation.applyStatusBadge(status: PhaseStatus.aborted),
        ActionMutation.consumeNextPhase(),
      ]);
    });

    test('declare haymaker inserts an end-of-segment queue override', () {
      expect(ActionDefinition.declareHaymaker.mutations, const [
        ActionMutation.insertQueueOverride(
          queueOverride: 'haymaker_end_of_segment',
        ),
      ]);
    });

    test('interrupt with hold badges held and inserts a hold override', () {
      expect(ActionDefinition.interruptWithHold.mutations, const [
        ActionMutation.applyStatusBadge(status: PhaseStatus.held),
        ActionMutation.insertQueueOverride(queueOverride: 'hold_interrupt'),
      ]);
    });

    test('supports custom action definitions', () {
      const custom = ActionDefinition(
        id: 'custom_abort',
        label: 'Abort to Dive For Cover',
        hotkey: 'c',
        targetType: ActionTargetType.ally,
        mutations: [ActionMutation.consumeNextPhase()],
      );
      expect(custom.id, 'custom_abort');
      expect(custom.targetType, ActionTargetType.ally);
      expect(custom.mutations, const [ActionMutation.consumeNextPhase()]);
    });
  });

  group('hotkey associations', () {
    test('every standard action has a single-character hotkey', () {
      for (final action in ActionDefinition.standardActions) {
        expect(action.hotkey, hasLength(1));
      }
    });

    test('standard hotkeys are unique', () {
      final hotkeys = ActionDefinition.standardActions
          .map((a) => a.hotkey)
          .toSet();
      expect(hotkeys, {'a', 'm', 'h'});
    });

    test('each hotkey letter appears in its action label', () {
      for (final action in ActionDefinition.standardActions) {
        expect(
          action.label.toLowerCase(),
          contains(action.hotkey.toLowerCase()),
        );
      }
    });

    test('bracketed hotkey convention maps to the documented actions', () {
      const bracketed = <String, String>{
        '[A]bort to Defensive Action': 'abort_to_defensive_action',
        'Declare Hay[M]aker': 'declare_haymaker',
        'Interrupt with [H]old': 'interrupt_with_hold',
      };
      for (final entry in bracketed.entries) {
        final hotkey = entry.key
            .substring(entry.key.indexOf('[') + 1, entry.key.indexOf(']'))
            .toLowerCase();
        final action = ActionDefinition.standardActions.firstWhere(
          (a) => a.hotkey == hotkey,
        );
        expect(action.id, entry.value);
      }
    });
  });

  group('ActionDefinition equality', () {
    test('identical values are equal', () {
      expect(
        ActionDefinition.abortToDefensiveAction,
        ActionDefinition.abortToDefensiveAction,
      );
    });

    test('different actions are not equal', () {
      expect(
        ActionDefinition.declareHaymaker,
        isNot(ActionDefinition.interruptWithHold),
      );
    });

    test('definitions differing only by mutations are not equal', () {
      const a = ActionDefinition(
        id: 'x',
        label: 'X',
        hotkey: 'x',
        targetType: ActionTargetType.self,
        mutations: [ActionMutation.consumeNextPhase()],
      );
      const b = ActionDefinition(
        id: 'x',
        label: 'X',
        hotkey: 'x',
        targetType: ActionTargetType.self,
        mutations: [ActionMutation.relocatePhase(targetSegment: 1)],
      );
      expect(a, isNot(b));
    });
  });
}
