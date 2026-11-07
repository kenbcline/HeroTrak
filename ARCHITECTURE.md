# HeroTrak — Architecture

HeroTrak is a Flutter application for large screens (desktop + tablets)
organized as a **strictly layered** codebase: business rules live in the
domain layer, state transitions live in the Riverpod engine, and widgets
only render state and forward input.

```
lib/
├── core/          # constants (6e Speed Chart) and utilities
├── domain/
│   ├── models/    # immutable Equatable value objects
│   ├── actions/   # declarative ActionDefinition / ActionMutation specs
│   └── services/  # pure-Dart rule services (no Flutter imports)
└── presentation/
    ├── state/     # Riverpod notifiers / UI providers
    ├── views/     # screens (control bar + matrix + panels)
    └── widgets/   # matrix, panels, hotkeys, dialogs
```

---

## Riverpod State Management

### `TurnState` — the single immutable snapshot
`lib/domain/models/turn_state.dart` holds the entire encounter:
`turnNumber`, `activeSegment`, `activeCombatantId`, `targetCombatantId`,
the combatant roster, and pending `HaymakerDeclaration`s. Every model is an
immutable Equatable value (defensive `List.unmodifiable` copies), so states
compare and round-trip exactly.

### `TurnEngineNotifier` — the rules engine
`lib/presentation/state/turn_engine_notifier.dart` owns all transitions via
`turnEngineProvider = NotifierProvider<TurnEngineNotifier, TurnState>`.
Highlights:

- **Atomic mutations** — `executeAction(ActionDefinition)` applies an
  action's `ActionMutation` stream (consume phase, relocate, badge, queue
  override) in one state write; any failure throws `StateError` leaving the
  state untouched (the UI swallows it non-modally).
- **Timeline navigation** — `selectNextPhaseSlot` / `selectPreviousPhaseSlot`
  walk `timeline_traversal.dart` stops (regular phases plus `Strikes`,
  `[REC]`, and `[CLR STUN]` pseudo-phases), staging Post-12 and gating the
  turn wrap behind "Start Next Turn?".
- **Smart turn reset** — `_enterNextTurn` reschedules every phase to
  `scheduled`, drops action flags/badges/declarations, carries only deferred
  Segment-12 Haymakers into Turn N+1, and preserves roster configuration.
- **Transient tag expiry** — condition badges (`Held`/`Aborted`) clear when
  their combatant reaches its next phase; Haymaker wind-ups expire once
  their resolution falls behind the cursor.
- **Status rules** — `setCombatantStatus` / `toggleCombatantStatus` enforce
  the DEAD phase-clear/restore cycle; stun recovery auto-clears when the
  `[CLR STUN]` phase is stepped past (action consumed).
- **SPD Aid/Drain** — `adjustSpdDelta` re-plans phases after `activeSegment`
  for the new `effectiveSpd = (spd + spdDelta).clamp(1, 12)`; `clearReaction`
  resets the delta and the `Aborted` state.

### UI-only state
`matrix_ui_state.dart` holds `selectedColumnProvider` (the Post-12 column
selection) — presentation focus that never touches domain rules.

---

## Dual-Panel Selection Model

The tracker keeps two independent cursors on purpose — the GM acts with one
character *on* another:

| | `activeCombatantId` — **Actor** | `targetCombatantId` — **Actee** |
| --- | --- | --- |
| Driven by | Timeline phase focus **only** (Left/Right, Prev/Next Phase, Space) | Column 1 clicks and Up/Down target-cursor keys |
| Panel | `ActiveCombatantPanel` (left) | `TargetCombatantPanel` (right) |
| Actions | `Declare Hay[M]aker`, `Interrupt with [H]old`, `[C]lear Action` (all bound to the actor; hotkeys M/H/C) | `[A]bort to Defensive Action` (hotkey A), `Clear Reaction`, `SPD +1/-1`, status toggles (OK/STUN/DYING/KO/DEAD) |
| Highlight | Row tint (`kActiveRowColor`; lighter grey on dead rows) | Column 1 cell only (`kTargetRowColor`; `kDeadSelectedRowColor` on dead rows) |

Target navigation is *pure selection*: it never advances the turn clock,
moves the segment cursor, or triggers recovery/phase side effects. The
abort reaction is subject-scoped — it cancels the *target's* Haymakers and
consumes only the target's phase, leaving the actor's timeline cursor alone.

---

## Domain Services (pure Dart)

| Service | Responsibility |
| --- | --- |
| `core/constants/speed_chart.dart` | The 6e Speed Chart (`kSpeedChart`); SPD 1 → Segment 7; `getSegmentsForSpd` |
| `segment_queue.dart` | Per-segment action queues: Held → Mental (EGO↓) → Physical (DEX↓), SPD↓/Name↑ tiebreaks; held-interruption carry-in |
| `timeline_traversal.dart` | Timeline stops and walks (`findNext/PreviousPhasePosition`, `findLastPhasePosition`), haymaker `Strikes` pseudo-stops, KO/dead bypass rules |
| `phase_display.dart` | Status-driven tile labels: `[CLR STUN]`, `[REC]`, Post-12 `[REC]`/`[BLEED]` |
| `encounter_serializer.dart` / `encounter_file_service.dart` | Strict JSON round-trip (`FormatException` on malformed data, lenient defaults for older files) + native file dialogs |

Domain models (`Combatant`, `PhaseSlot`, `HaymakerDeclaration`,
`CombatantStatus`, `PhaseStatus`) are flat immutable records; the
serializer mirrors them 1:1 so `serialize → deserialize` is state-equal.

---

## Presentation Structure

- **`initiative_matrix_screen.dart`** — control bar (brand menu: New
  Encounter… / Save / Load-with-reset-checkbox, Turn/Segment counters,
  two-line Prev/Next Phase buttons), the matrix, and the dual bottom panels.
- **`matrix_grid.dart`** — 15 columns (Target status, Combatant, Segments
  1–12, Post-12) with **pinned headers** above a `Scrollbar`-wrapped body.
  Header and rows share one flex layout (5/27/9…/10) for exact column
  alignment. Renders phase tiles, haymaker markers, `[CLR STUN]`/`[REC]`
  overrides, and Post-12 `[REC]`/`[BLEED]`. Keyboard navigation
  auto-scrolls changed rows into view below the header.
- **`hotkey_wrapper.dart`** — the keyboard layer (Space, arrows, A/H/M/C/N)
  mapping intents onto engine methods; invalid actions are silent no-ops.
- **`turn_advance.dart`** — the "Start Next Turn?" confirmation and the
  three-stage Next-Phase walk (phases → Post-12 → prompt).
- **`add_combatant_dialog.dart`** — Goon archetypes with auto-numbered
  names, faction autocompletion, strict SPD 1–12 validation.

---

## Test Suite Coverage & Matrix Validation

The suite (`flutter test`, 326 tests) is TDD-grown and organized by layer:

| File | Validates |
| --- | --- |
| `test/domain/models_test.dart` | Model immutability, equality, copyWith, initiative ordering |
| `test/domain/speed_chart_test.dart` | The full chart table (incl. SPD 1 → Segment 7) and phase counts |
| `test/domain/services/timeline_traversal_test.dart` | Phase/pseudo-phase walks, Post-12 exit, KO/dead bypass, segment-queue ordering |
| `test/domain/services/encounter_serializer_test.dart` | JSON shape, exact round-trips, malformed-input safety |
| `test/domain/services/encounter_file_service_test.dart` | Dialog-hook injection and file I/O |
| `test/presentation/state/turn_engine_basic_test.dart` | Segments/turn wrap, smart reset, target cycling, stun windows, transient expiry, SPD scheduling |
| `test/presentation/state/turn_engine_actions_test.dart` | Action mutations, abort-vs-Haymaker rules, status mechanics, Post-12 backing off |
| `test/presentation/widgets/matrix_grid_test.dart` | **Matrix validation:** 15-column structure, centering, column-width balancing, target highlighting isolation, pinned headers + column alignment, haymaker/status markers, dead-row styling, scrollbar + auto-scroll |
| `test/presentation/widgets/combatant_panels_test.dart` | Dual-panel rendering, tactical OCV/DCV box, status toggles, SPD adjusters, clear controls |
| `test/presentation/views/initiative_matrix_screen_test.dart` | Keyboard navigation, phase buttons, Post-12/turn flow, hotkey-to-panel bindings |
| `test/presentation/widgets/add_combatant_dialog_test.dart` | Archetypes, auto-numbering, faction defaults, validation |
| `test/presentation/widgets/encounter_io_dialogs_test.dart` | Save/Load/New-Encounter flows, reset checkbox, error feedback |
| `test/widget_test.dart` | App-shell smoke test |

Matrix widgets carry stable keys (`matrix-cell-<id>-<col>`,
`matrix-tile-<id>-<col>-<i>`, `haymaker-windup|resolution-<id>-<seg>`,
`target-column-<id>`, `post12-rec|bleed-<id>`, `detail-status-*`, …) so
widget tests assert exact visual state — marker placement, tint precedence,
column geometry (header/data `left`/`width` equality), and viewport
behavior — with no brittle text matching.

Run everything with:

```sh
flutter analyze && flutter test
```
