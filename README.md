# HeroTrak

A desktop-first **Hero System 6th Edition combat tracker** for Game Masters:
a keyboard-driven initiative matrix, a strict 6e tactical rules engine, and
fast encounter bookkeeping across large tables.

HeroTrak targets large screens (macOS, Windows, Linux, and tablet-class
devices) and is built with Flutter + Riverpod.

---

## Application Overview & Features

- **Initiative Matrix** — the full 6e Speed Chart laid out as a 15-column
  grid: a Target/status column (Column 1), the Combatant name column,
  Segments 1–12, and a Post-12 end-of-Turn column. Column headers stay
  **pinned** while long rosters scroll beneath a visible desktop scrollbar.
- **Dual bottom panels** —
  - **Active Combatant (Actor):** name + faction, SPD/DEX/EGO, live status
    badges, and initiative actions (`Declare Hay[M]aker`,
    `Interrupt with [H]old`, `[C]lear Action`).
  - **Target Combatant (Actee):** name + faction, a real-time OCV/DCV
    tactical card, reactions (`[A]bort to Defensive Action`,
    `Clear Reaction`), `SPD +1` / `SPD -1` Aid/Drain adjusters, and the
    `OK / STUN / DYING / KO / DEAD` status toggles.
- **Timeline engine** — phase-by-phase traversal with `Strikes` and
  `[REC]`/`[CLR STUN]` pseudo-phase stops, Post-12 staging, and a
  "Start Next Turn?" gate around the Turn boundary.
- **Encounter I/O** — native file dialogs, JSON save/load (with an optional
  *Reset to Turn 1, Segment 1* on load), and **New Encounter...** with
  confirmation.
- **Goon factory** — archetype templates (Slow/Fast Weak Goon, Slow/Fast
  Tough Goon, Mind-Resistant Goon, Mastermind / Elite Boss) with
  auto-numbered names and faction autocompletion (Players, Villain,
  Civilian, Law Enforcement + session factions).

---

## GM Keyboard Navigation Cheat Sheet

### Timeline controls (Active Combatant / Actor)

| Key | Action |
| --- | --- |
| `Space` | Advance one segment. At Segment 12, prompts **Start Next Turn?** |
| `→` / **Next Phase** | Walk to the next timeline phase (auto-selects its owner as Actor). Past the last phase, steps onto **Post-12**; from Post-12, prompts **Start Next Turn?** |
| `←` / **Prev Phase** | Walk to the previous phase. From Post-12, disengages it and returns to the Turn's last phase |
| `M` | Declare Hay[M]aker on the Actor (wind-up on N, **Strikes** on N+1; Segment-12 declarations strike on Segment 1 of the next Turn) |
| `H` | Interrupt with [H]old on the Actor (held actions resolve first in a segment) |
| `C` | [C]lear Action — release Holds and cancel Haymakers, restoring normal phase markers |

### Target controls (Actee)

| Key | Action |
| --- | --- |
| `↓` / `↑` | Move the **target cursor** up/down Column 1 (never touches the timeline clock) |
| Click row / Column 1 | Set the Target |
| `A` | [A]bort to Defensive Action on the Target (clears their pending Haymakers; never advances the timeline) |

### General

| Key | Action |
| --- | --- |
| `N` | Open the **Add Combatant** dialog |
| Menu ▸ **New Encounter...** | Clear the encounter (confirmed) |
| Menu ▸ **Save/Load Encounter...** | Native file dialogs; load offers *Reset to Turn 1, Segment 1* |

Keyboard navigation auto-scrolls: the scrollbar keeps the active/target row
in view below the pinned headers.

---

## Hero System 6e Tactical Engine Rules

### Phase Economy
- Phases follow the standard **6e Speed Chart**. SPD 1 acts on **Segment 7**
  only (and takes its normal Post-12 Recovery); SPD 2–12 follow the printed
  chart. SPD is clamped to 1–12.
- A phase is an economy: spending one on an action consumes it (`spent`),
  aborting to a defensive action consumes it (`aborted`), and **[H]old**
  banks it for a later interruption (held slots resolve ahead of all
  regular actions in a segment).
- Segment queues resolve **Held → Mental (EGO↓) → Physical (DEX↓)** with
  SPD↓ / Name↑ tiebreaks. Initiative rows sort **SPD↓, DEX↓, EGO↓, Name↑**.
- **Haymakers** cost a full phase: the wind-up (`[M]`) sits on Segment N and
  the attack **Strikes** on Segment N+1 — Segment-12 declarations strike on
  Segment 1 of the *next* Turn. Aborting cancels a pending Haymaker outright;
  aborting while standing on a pending `Strikes` phase consumes the
  resolution instead of a downstream phase. Transient tags (Held, Aborted,
  wind-ups) expire when their combatant reaches its next phase.

### Stun
- A **Stunned** combatant's next scheduled phase renders as **`[CLR STUN]`**
  and its action is consumed to clear the stun. Stepping the timeline past
  that phase auto-clears the status.
- Tactical modifier: **1/2 DCV**; Post-12 Recovery remains active.

### Dying / Bleed vs. KO (Stabilized / Unconscious)
- **DYING:** all natural Phase Recoveries are suppressed and Post-12
  Recovery is replaced by a **`[BLEED]`** indicator — the character loses
  **1 BOD on Post-12**. Tactical modifier: **0 OCV / 0 DCV**.
- **KO (Stabilized/Unconscious):** automatic phase **`[REC]`** and Post-12
  **`[REC]`** are restored so the character can regain STUN and wake up.
  Tactical modifier: **0 OCV / 0 DCV**.
- **DEAD:** the row is cleared of phases and greyed out; restoring any other
  status re-populates the natural Speed Chart.

### Mid-Turn SPD Aid / Drain
- `SPD +1` / `SPD -1` on the Target panel apply a temporary modifier
  (`spdDelta`) on top of the base SPD. The **effective SPD** is
  `(SPD + delta).clamp(1, 12)` and upcoming phases (everything after the
  active segment) are re-planned against the new chart immediately — past
  segments are never altered. The panels display `5 (+1)` / `5 (-1)`
  notation; **Clear Reaction** resets the delta.

---

## Build & Installation

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable)
- macOS with **Xcode** (for the macOS desktop target)

### One-command macOS release

```sh
./scripts/build_macos_release.sh
```

The script:
1. Regenerates `AppIcon.icns` from `icon/HeroTrakIcon.svg` (via
   `rsvg-convert`, `sips`, `iconutil`) when `rsvg-convert` is installed —
   skipped gracefully otherwise.
2. Cleans build artifacts (`flutter clean`, `flutter pub get`).
3. Verifies readiness (`flutter analyze`, `flutter test`).
4. Builds the universal (arm64 + x86_64) release:
   `flutter build macos --release --target-platform macos-universal`.
5. Packages `HeroTrak.app` into **`dist/HeroTrak-macOS-Universal.zip`**.

### Developer setup

```sh
flutter pub get        # dependencies
flutter run -d macos   # run in debug mode
flutter test           # full unit + widget suite
flutter analyze        # static analysis (must stay clean)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layered design, state
management, and test-suite map.
