import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/models.dart';
import '../../domain/services/phase_display.dart';
import '../state/matrix_ui_state.dart';
import '../state/turn_engine_notifier.dart';

/// Number of columns in the initiative matrix:
/// Combatant header + Segments 1–12 + Post-12.
const int kMatrixColumnCount = 14;

/// Label of the combatant name column.
const String kCombatantColumnLabel = 'Combatant';

/// Label of the end-of-Turn resolution column.
const String kPost12ColumnLabel = 'Post-12';

/// Background highlight for the active segment column.
const Color kActiveSegmentColumnColor = Color(0x33FFB300);

/// Background tint for the row of the active (acting) combatant.
const Color kActiveRowColor = Color(0x33FFB300);

/// Background tint for the row of the targeted combatant.
const Color kTargetRowColor = Color(0x332979FF);

/// Standard indicator tile color ([PhaseStatus.scheduled]).
const Color kScheduledTileColor = Color(0xFFE0E0E0);

/// High-contrast / glowing tile color ([PhaseStatus.active]).
const Color kActiveTileColor = Color(0xFFFFB300);

/// Distinct badge tile color ([PhaseStatus.held]).
const Color kHeldTileColor = Color(0xFF00897B);

/// Greyed-out tile color ([PhaseStatus.aborted], [PhaseStatus.spent]).
const Color kSpentTileColor = Color(0xFFBDBDBD);

/// Border tile color ([PhaseStatus.delayed]).
const Color kDelayedTileColor = Color(0xFF90CAF9);

/// Highlight color for a selected matrix column (Post-12).
const Color kSelectedColumnColor = Color(0x337E57C2);

/// Subtle pale-red tint for NPC combatant rows (light mode).
const Color kNpcRowColor = Color(0xFFFFF5F5);

/// Darker, higher-contrast background for the matrix header row.
const Color kMatrixHeaderColor = Color(0xFF37474F);

/// Muted grey background for unselected `dead` rows (the standard
/// `Colors.grey.shade400` tint).
const Color kDeadRowColor = Color(0xFFBDBDBD);

/// Lighter grey selection tint for a selected `dead` row — keeps the
/// selected row state crisp and visible against the muted dead background.
const Color kDeadSelectedRowColor = Color(0xFFE2E8F0);

/// Wind-up (`[M]`) haymaker marker tile color.
const Color kHaymakerWindupColor = Color(0xFFFFE0B2);

/// "Strikes/Resolves" haymaker marker tile color.
const Color kHaymakerResolutionColor = Color(0xFFEF9A9A);

/// Wind-up (`[M]`) or "Strikes/Resolves" marker tile for a declared
/// haymaker (see [HaymakerDeclaration]). Rendered separately from the base
/// phase slot tiles: the declaration is decoupled from the slot, so the
/// markers never corrupt or orphan a phase across Turn boundaries.
class HaymakerMarkerTile extends StatelessWidget {
  const HaymakerMarkerTile.windup({super.key}) : isResolution = false;

  const HaymakerMarkerTile.resolution({super.key}) : isResolution = true;

  /// Whether this tile marks the forced strike ("Strikes/Resolves") rather
  /// than the wind-up.
  final bool isResolution;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isResolution ? 'Strikes/Resolves' : 'Haymaker (winding up)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isResolution
              ? kHaymakerResolutionColor
              : kHaymakerWindupColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isResolution ? 'Strikes' : '[M]',
          style: const TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// A single phase-slot tile rendered inside a [MatrixCell].
///
/// Styling per [PhaseStatus]:
/// - `scheduled`: standard indicator tile,
/// - `active`: glowing / high-contrast tile,
/// - `held`: distinct `[H]` badge,
/// - `aborted` / `spent`: greyed tile with strikethrough label,
/// - `delayed`: shifted indicator tile (nudged right of the cell edge).
class MatrixTile extends StatelessWidget {
  const MatrixTile({super.key, required this.slot, this.overrideLabel});

  /// The phase slot this tile represents.
  final PhaseSlot slot;

  /// Status-driven label override (e.g. `[CLR STUN]`, `[REC]`); `null`
  /// renders the regular [PhaseStatus] glyph.
  final String? overrideLabel;

  String get _label => overrideLabel ??
      switch (slot.status) {
        PhaseStatus.scheduled => '●',
        PhaseStatus.active => '★',
        PhaseStatus.held => '[H]',
        PhaseStatus.aborted => '⊘',
        PhaseStatus.spent => '×',
        PhaseStatus.delayed => '⇢',
      };

  Color get _backgroundColor => switch (slot.status) {
        PhaseStatus.scheduled => kScheduledTileColor,
        PhaseStatus.active => kActiveTileColor,
        PhaseStatus.held => kHeldTileColor,
        PhaseStatus.aborted || PhaseStatus.spent => kSpentTileColor,
        PhaseStatus.delayed => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    final isConcluded = slot.status == PhaseStatus.aborted ||
        slot.status == PhaseStatus.spent;
    final isEmphasized =
        slot.status == PhaseStatus.active || slot.status == PhaseStatus.held;

    final tile = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: slot.status == PhaseStatus.delayed
            ? Border.all(color: kDelayedTileColor)
            : null,
        boxShadow: slot.status == PhaseStatus.active
            ? const <BoxShadow>[
                BoxShadow(
                  color: kActiveTileColor,
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: isEmphasized ? FontWeight.bold : FontWeight.normal,
          color: isConcluded ? Colors.grey.shade700 : Colors.black87,
          decoration: isConcluded ? TextDecoration.lineThrough : null,
        ),
      ),
    );

    if (slot.status == PhaseStatus.delayed) {
      // "Shifted indicator tile": nudged right of the cell's leading edge.
      return Padding(padding: const EdgeInsets.only(left: 10), child: tile);
    }
    return tile;
  }
}

/// Post-12 end-of-Turn indicator tile: `[REC]` (Post-12 Recovery active) or
/// `[BLEED]` (dying — recovery suppressed, -1 BOD on Post-12).
class Post12MarkerTile extends StatelessWidget {
  const Post12MarkerTile({super.key, required this.label});

  /// Either `[REC]` or `[BLEED]`.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: label == '[BLEED]' ? Colors.red.shade100 : kScheduledTileColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.2),
      ),
    );
  }
}

/// Compact Column 1 cell: the combatant's status icon (`OK` / `STUN` /
/// `DYING` / `KO` / `DEAD`). Clicking anywhere in Column 1 (or the row)
/// targets the combatant for the Target panel's reactions and status
/// controls.
class TargetStatusCell extends StatelessWidget {
  const TargetStatusCell({
    super.key,
    required this.combatant,
    required this.isTargeted,
  });

  final Combatant combatant;

  /// Whether this combatant is the current Target (Actee): the target
  /// selection highlight is isolated to this Column 1 cell — it never
  /// tints the whole grid row.
  final bool isTargeted;

  @override
  Widget build(BuildContext context) {
    final isDead = combatant.status == CombatantStatus.dead;
    return Container(
      key: Key('target-column-${combatant.id}'),
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      color: isTargeted
          ? (isDead ? kDeadSelectedRowColor : kTargetRowColor)
          : null,
      child: Container(
        key: Key('target-status-${combatant.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isDead ? Colors.grey.shade300 : Colors.teal.shade50,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          combatant.status.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDead ? Colors.grey.shade700 : Colors.black87,
          ),
        ),
      ),
    );
  }
}

/// One cell of the matrix: either the combatant label (header column) or
/// the phase-slot tiles a combatant has scheduled in a segment column (or
/// the reserved Post-12 end-of-Turn column).
class MatrixCell extends StatelessWidget {
  const MatrixCell({
    super.key,
    required this.combatantId,
    required this.columnLabel,
    this.slots = const <PhaseSlot>[],
    this.slotLabels = const <String?>[],
    this.markers = const <Widget>[],
    this.label,
    this.isHighlighted = false,
    this.isSelected = false,
    this.onTap,
  });

  /// Id of the combatant whose row this cell belongs to.
  final String combatantId;

  /// Column identifier: `'combatant'`, `'1'`–`'12'`, or `'post12'`.
  final String columnLabel;

  /// Phase slots rendered inside this cell (segment / Post-12 columns).
  final List<PhaseSlot> slots;

  /// Status-driven label overrides, index-aligned with [slots].
  final List<String?> slotLabels;

  /// Extra marker tiles rendered after the phase tiles (e.g. haymaker
  /// wind-up / "Strikes/Resolves" markers).
  final List<Widget> markers;

  /// Optional label rendered instead of tiles (combatant header column).
  final String? label;

  /// Whether the cell sits in the active segment column.
  final bool isHighlighted;

  /// Whether the cell's column is selected.
  final bool isSelected;

  /// Column selection handler (Post-12 column); null when not clickable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      key: Key('matrix-cell-$combatantId-$columnLabel'),
      height: 44,
      padding: label != null
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.all(3),
      alignment: Alignment.center,
      color: isSelected
          ? kSelectedColumnColor
          : isHighlighted
              ? kActiveSegmentColumnColor
              : null,
      child: label != null
          ? Text(
              label!,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : Wrap(
              spacing: 3,
              runSpacing: 3,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (var i = 0; i < slots.length; i++)
                  MatrixTile(
                    key: Key('matrix-tile-$combatantId-$columnLabel-$i'),
                    slot: slots[i],
                    overrideLabel: i < slotLabels.length ? slotLabels[i] : null,
                  ),
                ...markers,
              ],
            ),
    );

    if (onTap == null) return cell;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: cell,
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.columnLabel,
    this.isHighlighted = false,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final String columnLabel;
  final bool isHighlighted;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onHighlight = isHighlighted || isSelected;
    final cell = Container(
      key: Key('matrix-column-header-$columnLabel'),
      height: 36,
      alignment: Alignment.center,
      color: isSelected
          ? kSelectedColumnColor
          : isHighlighted
              ? kActiveSegmentColumnColor
              : kMatrixHeaderColor,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: onHighlight ? Colors.black87 : Colors.white,
        ),
      ),
    );

    if (onTap == null) return cell;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: cell,
      ),
    );
  }
}

class _MatrixHeaderRow extends StatelessWidget {
  const _MatrixHeaderRow({
    required this.activeSegment,
    required this.isPost12Selected,
    required this.onSelectPost12,
    required this.onSegmentSelected,
  });

  final int activeSegment;
  final bool isPost12Selected;
  final VoidCallback onSelectPost12;
  final ValueChanged<int> onSegmentSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(
          flex: 5,
          child: _HeaderCell(
            label: 'Target',
            columnLabel: 'target',
          ),
        ),
        const Expanded(
          flex: 27,
          child: _HeaderCell(
            label: kCombatantColumnLabel,
            columnLabel: 'combatant',
          ),
        ),
        for (var segment = 1; segment <= 12; segment++)
          Expanded(
            flex: 9,
            child: _HeaderCell(
              label: '$segment',
              columnLabel: '$segment',
              isHighlighted: segment == activeSegment,
              onTap: () => onSegmentSelected(segment),
            ),
          ),
        Expanded(
          flex: 10,
          child: _HeaderCell(
            label: kPost12ColumnLabel,
            columnLabel: 'post12',
            isSelected: isPost12Selected,
            onTap: onSelectPost12,
          ),
        ),
      ],
    );
  }
}

class _CombatantRow extends StatelessWidget {
  const _CombatantRow({
    super.key,
    required this.combatant,
    required this.activeSegment,
    required this.turnNumber,
    required this.isActive,
    required this.isTargeted,
    required this.isPost12Selected,
    required this.haymakers,
    required this.onSelectPost12,
    required this.onSelected,
    required this.onTargeted,
  });

  final Combatant combatant;
  final int activeSegment;
  final int turnNumber;
  final bool isActive;
  final bool isTargeted;
  final bool isPost12Selected;
  final List<HaymakerDeclaration> haymakers;
  final VoidCallback onSelectPost12;
  final VoidCallback onSelected;
  final VoidCallback onTargeted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelected,
      onSecondaryTap: onTargeted,
      child: Container(
        key: Key('matrix-row-${combatant.id}'),
        decoration: BoxDecoration(
          // The target selection highlight is isolated to Column 1 (see
          // [TargetStatusCell]); the row keeps only dead/actor/NPC tints.
          color: combatant.status == CombatantStatus.dead
              ? (isActive ? kDeadSelectedRowColor : kDeadRowColor)
              : isActive
                  ? kActiveRowColor
                  : combatant.isNpc
                      ? kNpcRowColor
                      : null,
          border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: TargetStatusCell(
                combatant: combatant,
                isTargeted: isTargeted,
              ),
            ),
            Expanded(
              flex: 27,
              child: MatrixCell(
                combatantId: combatant.id,
                columnLabel: 'combatant',
                label: combatant.name,
              ),
            ),
            for (var segment = 1; segment <= 12; segment++)
              Expanded(
                flex: 9,
                child: MatrixCell(
                  combatantId: combatant.id,
                  columnLabel: '$segment',
                  isHighlighted: segment == activeSegment,
                  slots: <PhaseSlot>[
                    for (final slot in combatant.phaseSlots)
                      if (slot.segment == segment) slot,
                  ],
                  slotLabels: <String?>[
                    for (final slot in combatant.phaseSlots)
                      if (slot.segment == segment)
                        phaseSlotDisplayLabel(combatant, slot, activeSegment),
                  ],
                  markers: <Widget>[
                    // The wind-up lives only in the declaring Turn; a
                    // deferred (Segment 12) declaration renders its
                    // "Strikes" marker on Segment 1 of Turn N+1 instead.
                    for (final declaration in haymakers)
                      if (declaration.declaredSegment == segment &&
                          declaration.declaredTurn == turnNumber)
                        HaymakerMarkerTile.windup(
                          key: Key(
                            'haymaker-windup-${combatant.id}-$segment',
                          ),
                        ),
                    for (final declaration in haymakers)
                      if (declaration.resolutionSegment == segment &&
                          declaration.resolutionTurn == turnNumber)
                        HaymakerMarkerTile.resolution(
                          key: Key(
                            'haymaker-resolution-${combatant.id}-$segment',
                          ),
                        ),
                  ],
                ),
              ),
            // Post-12: end-of-Turn resolution column — the Post-12 Recovery
            // (`[REC]`) or bleeding (`[BLEED]`) indicator; no phase slot
            // maps past Segment 12.
            Expanded(
              flex: 10,
              child: Builder(
                builder: (context) {
                  final post12Label = post12DisplayLabel(combatant);
                  return MatrixCell(
                    combatantId: combatant.id,
                    columnLabel: 'post12',
                    slots: const <PhaseSlot>[],
                    markers: <Widget>[
                      if (post12Label != null)
                        Post12MarkerTile(
                          key: Key(
                            'post12-${post12Label == '[BLEED]' ? 'bleed' : 'rec'}-${combatant.id}',
                          ),
                          label: post12Label,
                        ),
                    ],
                    isSelected: isPost12Selected,
                    onTap: onSelectPost12,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 15-column initiative matrix: Target status column, Combatant header,
/// Segments 1–12, Post-12.
///
/// Renders one row per combatant with phase-slot tiles per [PhaseStatus],
/// wrapped in a desktop [Scrollbar] (`thumbVisibility: true`). Keyboard
/// navigation auto-scrolls: whenever [TurnState.targetCombatantId] or
/// [TurnState.activeCombatantId] changes, the owning row is brought into
/// the viewport if it moved past the top/bottom edge.
///
/// Clicking a row (Column 1 status icon or name included) sets the Target
/// combatant (`targetCombatantId`, the Actee); the Active combatant
/// (`activeCombatantId`, the Actor) is driven exclusively by timeline phase
/// focus. Clicking a segment header (1–12) jumps the active
/// segment directly to that column (clearing any Post-12 selection); the
/// Post-12 column stays independently selectable for recovery tracking.
/// All tracker rules live in [TurnEngineNotifier]; this widget only renders
/// state and forwards input.
class MatrixGrid extends ConsumerStatefulWidget {
  const MatrixGrid({super.key});

  @override
  ConsumerState<MatrixGrid> createState() => _MatrixGridState();
}

class _MatrixGridState extends ConsumerState<MatrixGrid> {
  final _scrollController = ScrollController();
  final _contentKey = GlobalKey();
  final _rowKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _rowKey(String combatantId) =>
      _rowKeys.putIfAbsent(combatantId, GlobalKey.new);

  /// Scrolls the row of [combatantId] into the viewport when it has moved
  /// past the top/bottom edge (keyboard-navigation auto-scroll).
  ///
  /// The pinned header sits above the scrollable body, so the scroll
  /// viewport — the coordinate space of [position]'s bounds — begins
  /// exactly below it: rows land cleanly under the header and are never
  /// hidden behind it.
  Future<void> _ensureRowVisible(String? combatantId) async {
    if (combatantId == null) return;
    final rowContext = _rowKeys[combatantId]?.currentContext;
    if (rowContext == null) return;
    if (!_scrollController.hasClients) return;
    final rowBox = rowContext.findRenderObject() as RenderBox?;
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || contentBox == null) return;

    final position = _scrollController.position;
    final offset = rowBox.localToGlobal(Offset.zero, ancestor: contentBox);
    final top = offset.dy - position.pixels;
    final bottom = top + rowBox.size.height;
    if (top < 0) {
      await Scrollable.ensureVisible(rowContext, alignment: 0.0);
    } else if (bottom > position.viewportDimension) {
      await Scrollable.ensureVisible(rowContext, alignment: 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TurnState>(turnEngineProvider, (previous, next) {
      if (previous?.targetCombatantId != next.targetCombatantId) {
        _ensureRowVisible(next.targetCombatantId);
      }
      if (previous?.activeCombatantId != next.activeCombatantId) {
        _ensureRowVisible(next.activeCombatantId);
      }
    });

    final state = ref.watch(turnEngineProvider);
    final isPost12Selected = ref.watch(selectedColumnProvider) == 'post12';

    void selectPost12() =>
        ref.read(selectedColumnProvider.notifier).state = 'post12';

    void selectSegment(int segment) {
      // Jumping the board replaces any Post-12 column selection.
      ref.read(selectedColumnProvider.notifier).state = null;
      ref.read(turnEngineProvider.notifier).setActiveSegment(segment);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Pinned header: stays visible above the scrolling body. It shares
        // the exact flex layout of the data rows inside an equal-width
        // container, so every header column stays aligned with its phase
        // column below (the scrollbar thumb overlays, consuming no width).
        _MatrixHeaderRow(
          activeSegment: state.activeSegment,
          isPost12Selected: isPost12Selected,
          onSelectPost12: selectPost12,
          onSegmentSelected: selectSegment,
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                key: _contentKey,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final combatant in state.combatants)
                    _CombatantRow(
                      key: _rowKey(combatant.id),
                      combatant: combatant,
                      activeSegment: state.activeSegment,
                      turnNumber: state.turnNumber,
                      isActive: combatant.id == state.activeCombatantId,
                      isTargeted: combatant.id == state.targetCombatantId,
                      isPost12Selected: isPost12Selected,
                      haymakers: <HaymakerDeclaration>[
                        for (final declaration in state.haymakerDeclarations)
                          if (declaration.combatantId == combatant.id)
                            declaration,
                      ],
                      onSelectPost12: selectPost12,
                      onSelected: () => ref
                          .read(turnEngineProvider.notifier)
                          .setTargetCombatant(combatant.id),
                      onTargeted: () => ref
                          .read(turnEngineProvider.notifier)
                          .setTargetCombatant(combatant.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}