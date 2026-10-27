# Milestones

Each milestone is small enough to review on its own and ends in a state you can check. Milestones
M2 to M8 need a Mac with Xcode 15 or later. M1 can also be checked on Linux.

Status: **M1 is done.** M2 and M3 build and pass their tests on a Mac; the on-screen play test is still pending. M4 and M5 are implemented and unit-tested on Linux, and are waiting for a Mac check. M6 to M8 are not started.

---

### M1: Game model and rules engine ✅
**Scope:** in `SpiderCore`:
- `Card`, `Suit`, `Rank`, `Difficulty`, and `Deck` (seeded shuffle)
- `GameState` (layout, run detection, move validation, deal rules, completed-run detection)
- `SpiderGame` (perform, undo, scoring, undo policy)
- hint finder and the `Statistics` model
- a placeholder SwiftUI board

**Acceptance criteria:**
- [x] `swift build` and `swift test` pass. All 35 XCTests pass on Linux with Swift 6.0.3.
- [x] Tests cover:
  - 104 cards for each difficulty
  - the 6/6/6/6/5×6 layout with only top cards face up, and 50 cards in stock
  - seed determinism, pinned with golden values
- [x] Move rules:
  - only same-suit descending runs can be lifted
  - a run may land on any suit one rank higher, or on an empty column
  - an exposed card flips face up automatically
- [x] Deals:
  - a deal is blocked while a column is empty, except when fewer than 10 cards are left
  - 5 deals empty the stock
- [x] Completed suits: a K→A same-suit run is removed for +100, whether a move or a deal completed
  it. The 8th suit wins the game.
- [x] Scoring: 500 at the start, −1 per move, a deal is free, and an undo costs −1 and takes back any
  bonus.
- [x] Undo is unlimited and returns to the start of the game. The xpClassic policy stops at deals and
  at completed suits.
- [x] Hints come in order (same suit, then other suit, then empty column) and skip pointless
  shuffles. Every hint is legal across 120 randomized games, and card conservation and face-up
  invariants hold throughout.
- [x] The game and its undo history round-trip through `Codable`.

### M2: SwiftUI board rendering 🟡 (implemented, waiting for a Mac check)
**Implemented:**
- the `SpiderBoard` target (pure Swift): `BoardLayout`, which handles card size scaling with the window width, column positions, face-down and face-up fan steps, column compression, and the stock, foundation and score-box frames
- `placements(for:drag:)`, which gives every card a frame keyed by its stable id, so moves and deals animate
- `CardFace.pips`, the pip layout for number cards
- SwiftUI views: `CardView`, which draws faces and the blue lattice back in code; `BoardView`; `ScoreBoxView`; and the felt

Not done yet: snapshot images and SwiftUI previews.

**Scope:**
- `CardView` with vector faces and backs at a 71:96 ratio
- `ColumnView` with face-down and face-up offsets, and compression for tall columns
- `StockView` with one back per remaining deal
- `FoundationView` and `ScoreBoxView`
- the green felt background and a resizable layout

**Acceptance:**
- `swift run SpiderSolitaire` shows a new four-suit game laid out like XP: 10 columns, the stock at
  bottom right, the score box in the centre showing "Score: 500 Moves: 0", and the foundation at
  bottom left.
- Resizing the window from 800×600 to full screen keeps everything visible.
- SwiftUI previews render for an opening position, a mid-game position and a near-win position.
- Snapshot images of these 3 positions are committed under `docs/screenshots/`.

### M3: Drag and drop 🟡 (implemented, waiting for a Mac check)
**Implemented:** `PointerController` (pure Swift, tested) receives a single board-wide `DragGesture`. It handles:
- lifting a run from any card in a same-suit run
- dropping on the legal column the run overlaps most
- snapping back after an illegal drop
- clicking the stock to deal
- double-clicking to send a run to its best target (`GameState.bestDestination`)

Not done yet: `docs/QA.md`.

**Scope:**
- a drag gesture that lifts a movable run, hit-testing the drop target, a return animation for
  illegal drops, and double-click to auto-move
- `GameModel` bridges these to `SpiderGame.perform`

**Acceptance:**
- The player can drag a single card and a multi-card same-suit run onto valid targets, including
  empty columns.
- Mixed-suit stacks can't be lifted.
- Illegal drops snap back and leave the score unchanged.
- A legal drop updates the score and moves by −1 and +1, and the exposed card flips over.
- A manual check script in `docs/QA.md` (10 steps) passes.

### M4: Dealing, stock and completed-suit animation 🟡 (implemented, waiting for a Mac check)
**Implemented:**
- `BoardAnimations` (pure Swift, tested), with a deal hold and flying cards
- `ActionOutcome.dealtCardIDs`, and `CompletedRun.cards` and `foundationSlot`
- `GameModel` steps through the animation with cancellable timed tasks. Any new action jumps running animations to their end state.

**Scope:**
- Clicking the stock or pressing D deals, with a staggered 10-card animation.
- When a deal is blocked, an XP-style alert appears ("You are not allowed to deal a new row while
  there are any empty slots.").
- A completed run flies to the foundation card by card, and then the exposed card flips.

**Acceptance:**
- After 5 deals the stock shows nothing, and further deal attempts do nothing.
- In one-suit mode, completing a K→A run animates it to the foundation and adds 100 to the score.
- Turning off animations (via a debug toggle for now) applies the state change instantly.
- Cards never get stuck mid-animation when the player clicks quickly (stress test: hold D and click
  rapidly).

### M5: Scoring, undo and hints in the UI 🟡 (implemented, waiting for a Mac check)
**Implemented:**
- `HintCycler`, `HintHighlight` and `GameState.isStuck`, all tested
- M, Game ▸ Show an Available Move, and clicking the score box all show a hint
- The hint flash inverts the source run, then the target card or empty slot, then fades, about 0.55 s per step.
- The "There are no more moves." dialog offers Undo, New Game and OK.
- Game ▸ Classic XP Undo switches the undo mode and is remembered between launches.

**Scope:**
- the score box updates live
- ⌘Z undo, which also animates
- M (and clicking the score box) cycles through the hints, XP-style: the source flashes, then the
  destination
- when there are no hints, the stock is highlighted, or the "no moves" feedback plays

**Acceptance:**
- Undo all the way back to the deal, then redo the same moves: positions match and the score follows
  the §2.6 table.
- Pressing M repeatedly cycles through every hint `hints()` returns and then wraps around.
- In a blocked position with stock left, the stock flashes. In a blocked position with an empty
  stock, the "No more moves" dialog appears.

### M6: Menus, difficulty, new game, statistics and saving
**Scope:**
- `Commands` that recreate the XP Game menu (see §3.5)
- a Difficulty sheet
- a confirm dialog for abandoning a game in progress, which records a loss
- the Statistics window with a Reset button
- Settings for undo policy, animations, sounds and save-on-exit
- JSON persistence for the save, the statistics and autosave on quit

**Acceptance:**
- Every shortcut in §3.5 works.
- Quitting mid-game and relaunching resumes the exact position, and undo still works.
- The statistics numbers update correctly after a win (forced with a debug "near-win" seed or
  position) and after an abandoned game. They survive a relaunch.
- Restart This Game re-deals the same seed.

### M7: XP visual polish and win animation
**Scope:**
- refined card faces (corner indices, pips, court letters), the blue card back and the felt
  vignette
- XP-style score-box styling, the hint highlight (inverted colours) and drag shadows
- the win celebration (card fireworks in `Canvas`) and the "Congratulations" dialog
- optional sounds

**Acceptance:**
- A side-by-side screenshot against an XP reference image is reviewed and judged close enough.
- The win animation runs at 60 fps on an M1 Mac (Instruments shows no dropped frames over 5 s), can
  be skipped, and leads to the dialog.
- Sounds respect the Settings toggle.

### M8: App icon and `.app` packaging
**Scope:**
- an app icon (spider and cards, our own art) as an `.icns` in all sizes
- `Info.plist` (bundle id `com.dansailer.SpiderSolitaire`, version, category `public.app-category.card-games`)
- `scripts/package.sh` → `dist/SpiderSolitaire.app`, ad-hoc signed
- a zip artifact

**Acceptance:**
- Double-clicking `dist/SpiderSolitaire.app` launches the game with its icon in the Dock and Finder.
- `codesign --verify --deep dist/SpiderSolitaire.app` passes.
- The README documents the packaging step.
- Optional: CI (GitHub Actions on a macOS runner) builds, tests and uploads the zip.
