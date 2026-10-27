# Spider Solitaire for macOS: Design Spec

A native macOS (14+) clone of Windows XP Spider Solitaire, written in Swift and SwiftUI. The game
should look and play like the XP version, with Mac conventions where the two differ (menu bar,
⌘ shortcuts, `.app` bundle).

## 1. Sources

| Source | What it is | What we use from it |
|---|---|---|
| [najmiter/spider-solitaire-clone](https://github.com/najmiter/spider-solitaire-clone) | A **compiled Godot web export** (`index.pck`, `index.wasm`). There is no game source in the repo. The README credits the card sprite to the Figma "Classic Playing Cards" community file. | A visual reference only: XP layout, felt colour, how the stock and foundation look. |
| [baspinarenes/spider-solitaire](https://github.com/baspinarenes/spider-solitaire) | React web app, CC0. It is **one-suit only** and stacks A→K, which the README itself calls "contrary to the real rules". | UX ideas: the hint box, "cannot deal with an empty column" feedback, sound cues (`deal`, `hint`, `no-hint`, `win`). We do not copy its rules or its card images. |
| Wikipedia "Microsoft Spider Solitaire", Baidu Baike "Spider Solitaire", Microsoft Q&A | Descriptions of the rules, scoring and hints | The rules below. |

**Art and IP:** we do not ship Microsoft's card faces, card backs, sounds or the XP name and logo. Cards
are drawn in code (vector suit symbols and court-card lettering), or come from a CC0 set added in M7.
The look is "XP-like", not a copy of the XP assets.

## 2. Rules (implemented in `SpiderCore`)

### 2.1 Cards and difficulty
- The game always uses **104 cards** (two decks' worth), with 8 complete A–K sets:
  - **Easy: One Suit**: 8 × ♠
  - **Medium: Two Suits**: 4 × ♠, 4 × ♥
  - **Difficult: Four Suits**: 2 × each suit
- Shuffling uses Fisher–Yates with our own SplitMix64 generator. Seeds therefore reproduce the same
  deal on every platform and toolchain, and a unit test pins this with golden values. Every game has a
  `seed`, which makes Restart and saved games possible.

### 2.2 Layout
- There are **10 tableau columns**. Columns 1–4 get 6 cards and columns 5–10 get 5 cards (54 in all).
  Only the top card of each column starts face up.
- The **stock** holds 50 cards, which is 5 deals of 10. It is drawn as stacked card backs in the
  bottom-right corner, one back per remaining deal.
- The **foundation** sits in the bottom-left corner. It shows the completed suits, one K card each,
  fanned left to right.

### 2.3 Moves
- **Pick up:** the player can lift any face-up card together with everything on top of it, but only
  if those cards form a **same-suit run descending by one** (for example 9♥ 8♥ 7♥). A run may be
  lifted from any card inside it.
- **Drop:** the lowest card of the lifted run must land on a face-up card **exactly one rank higher,
  of any suit**, or on an **empty column**. Any card or valid run may go to an empty column.
- When a move exposes a face-down card, that card **turns face up automatically**.
- An illegal drop sends the cards back to where they were. It has no score effect and adds nothing
  to the undo history.

### 2.4 Dealing
- Clicking the stock (or pressing **D**) deals **one face-up card onto each of the 10 columns**,
  left to right.
- **No deal is allowed while any column is empty.** XP shows the message "You are not allowed to
  deal a new row while there are any empty slots."
  - *Decision:* if the tableau holds fewer than 10 cards in total, filling every column is
    impossible, so the deal is allowed anyway. This only happens late in a game.
- A deal can complete a run. All 10 columns are checked afterwards.

### 2.5 Completed suits
- When the top 13 cards of a column form a face-up **K→A run of one suit**, they are removed to the
  foundation automatically (animated in M4) and earn **+100**. The newly exposed card turns face up.
- The game is **won when all 8 suits are complete**. Win animation and dialog: §3.6.

### 2.6 Scoring (XP)
| Event | Score | Moves counter |
|---|---|---|
| New game | 500 | 0 |
| Card or run move | −1 | +1 |
| Completed suit | +100 | n/a |
| Deal | 0 (*decision*: XP does not charge for a deal) | +1 |
| Undo | restores the earlier position. The undone move's −1 is **not** refunded, any +100 it earned **is** taken back, and the undo itself costs −1. | +1 |

- The score may go negative.
- The highest possible score is 500 + 800 minus the number of moves.
- All constants live in `ScoringRules`, so they can be tuned without touching the engine.

### 2.7 Undo
- **Default `UndoPolicy.unlimited`:** the player can undo every move back to the start of the game.
  This is what the brief asks for, and it matches Vista and later.
- **`UndoPolicy.xpClassic`:** a deal or a completed-suit removal clears the undo history, as in
  original XP. It is offered in Options.
- *Decision:* the XP bug where undoing a final, suit-completing move kept the +100 is **not**
  reproduced.

### 2.8 Hints ("Show an available move", **M**)
- `GameState.hints()` returns the moves in XP's order:
  1. moves onto a **same-suit** card,
  2. moves onto a card of **another suit**,
  3. moves into an **empty column**.
  Ties are broken by source column and then destination column.
- Like XP, it **skips pointless shuffles**:
  - It never suggests moving a card off a same-suit parent.
  - It never moves a card that already sits on a valid parent onto another off-suit card.
  - It never moves a run that already fills its column into an empty column.
- Each press of M shows the next hint and wraps around. A hint is shown XP-style: the source run is
  highlighted (inverted), then the destination card, for about 0.5 s each.
- When no hints are left, the stock is highlighted if a deal is possible. Otherwise the game plays
  the "no moves" sound.
- `hasLegalMove` (with no filtering) detects a stuck game. When the game is stuck and the stock is
  empty, it offers "No more moves. New game / Undo".

## 3. UI and UX (matching XP)

### 3.1 Window
- There is one window, titled "Spider Solitaire". The default size is 800×600 and the window can be
  resized. Cards scale with the window width, with a minimum card width of 50 pt and a maximum of
  110 pt.
- The background is green felt: `#007F0E`, with a subtle radial vignette added in M7.
- Card proportions are 71:96, the classic Windows card ratio, with rounded corners and a 1 px dark
  border.
- Card backs are a blue pattern, drawn in code.

### 3.2 Tableau
- The 10 columns are spread evenly across the top.
- Fanning:
  - face-down cards are offset about 12% of the card height,
  - face-up cards are offset about 25%,
  - a column that would overflow the window compresses its offsets.
- An empty column shows a faint outlined slot.

### 3.3 Bottom bar
- **Left:** the foundation, with the completed suits' kings fanned.
- **Centre:** the XP score box, a dark-green rounded rectangle showing `Score: 500` and `Moves: 0`.
  Clicking it shows a hint, as in XP.
- **Right:** the stock, with up to 5 stacked backs. Clicking it deals.

### 3.4 Interaction
- **Drag and drop (M3):**
  - Pressing on a movable card lifts it and every card above it.
  - The dragged run follows the cursor with a shadow.
  - On release, the run drops onto the column whose top card's frame, or empty slot, overlaps it
    most.
  - An illegal drop animates the run back.
  - Cards the player cannot lift give no drag feedback.
- **Click-to-move (M3, optional):** double-clicking a movable run sends it to the best legal target,
  using the same ordering as the hints.
- **Animations:**
  - dealing sweeps 10 cards from the stock, staggered by 45 ms. Each card stays face down on its pile until it leaves,
  - a completed run flies to the foundation one card at a time, starting with the top card (A) and ending with the K, staggered by 40 ms, about 0.3 s per card. The foundation king appears once all 13 cards have landed,
  - an exposed card flips over.
  Options → "Show animations" turns all of these off.

### 3.5 Menus and shortcuts
| XP menu item | XP key | Mac shortcut |
|---|---|---|
| Game ▸ New Game | F2 | ⌘N and F2 |
| Game ▸ Restart This Game | n/a | ⇧⌘N |
| Game ▸ Undo | Ctrl+Z | ⌘Z |
| Game ▸ Deal Next Row | D | D |
| Game ▸ Show An Available Move | M | M (H also works) |
| Game ▸ Difficulty… | n/a | ⌘D (sheet: Easy, Medium, Difficult) |
| Game ▸ Statistics… | n/a | ⌘I |
| Game ▸ Options… | n/a | ⌘, (Settings) |
| Game ▸ Save This Game | Ctrl+S | ⌘S |
| Game ▸ Open Last Saved Game | Ctrl+O | ⌘O |
| Game ▸ Exit | Alt+F4 | ⌘Q |
| Help ▸ Contents / About | F1 | ⌘? |

- Choosing a new difficulty, or a new game while a game is in progress, first asks "Are you sure you
  want to quit this game?" If the player confirms, the abandoned game counts as a loss, as in XP.

### 3.6 Win
- The XP-style celebration plays: card fireworks or bouncing cards rendered with a SwiftUI `Canvas`
  and `TimelineView`.
- Then the dialog "Congratulations, you won! Do you want to start another game?" appears with
  Yes/No buttons and shows the final score.
- The win animation (completed suits' K/Q/J/10 bouncing out of the foundation with trails, plus
  firework sparks, about 10 s) can be skipped with a click or any key. With animations off, the dialog
  appears straight away.

### 3.6a Card faces
- Options → Card faces: **Classic** (default) or **Simple**. It is saved in options.json; older files
  without the key decode as Classic.
- Classic: 240 × 324 px PNGs (2x the largest card) from Dmitry Fomin's CC0 English-pattern deck. The ace
  of spades has Byron Knoll's public-domain ornate spade. The images live in the app target's resources
  (`.copy("Resources/Cards")`), and sources and licences are listed in `Resources/Cards/CREDITS.md`.
- CardView draws the image on the white card, clipped to the rounded rect, with the usual border. If
  an image can't be found, it falls back to the code-drawn face. Card backs are unchanged.

### 3.7 Sound (M7, optional)
- The game plays short cues for deal, drop, cannot-deal, hint, no-hint and win.
- The cues are built-in macOS system sounds played with `NSSound(named:)` (Pop, Tink, Basso, Ping, Funk,
  Glass, Hero); no Microsoft or bundled audio. Options → "Play sounds" is off by default.

## 4. Persistence and statistics
- **Statistics** (`Statistics`, `DifficultyStatistics` in the core), kept per difficulty:
  - games played and won, and the win percentage,
  - high score,
  - current and longest win streak,
  - current and longest loss streak.
- Statistics are stored as JSON in
  `~/Library/Application Support/SpiderSolitaire/statistics.json`. Game ▸ Statistics shows them and
  has a Reset button.
- **Saved game:** `SpiderGame` is `Codable`, including its undo history.
  - ⌘S writes `savedgame.json`. There is only one slot, as in XP. Saving on quit uses the same slot.
  - ⌘O restores it. Opening the save, or declining it at launch, **uses up the slot**. This stops a player from replaying a save after losing. A saved game that is declined counts as a loss if it was in progress.
  - When the app quits, it saves automatically and resumes on the next launch. This follows the XP
    option "Always save game on exit" and is the default. Options also offers Prompt or Never.
- **Preferences** (`options.json`):
  - difficulty
  - undo policy
  - animations
  - save on exit (always, never or prompt). "Never" means an unfinished game counts as a loss.
  - open on start (always, never or prompt)

  Missing or unknown fields fall back to their defaults.
- **Counting rule:** a game counts as played once the player makes a move or a deal.
  - It counts as **lost** when the player abandons it: a new game, a difficulty change, or quitting
    with "Never save".
  - It counts as **won** when all 8 suits are complete.

## 5. Architecture

```
SpiderSolitaire (Swift package)
├── SpiderCore          pure Swift, Foundation-free, Linux-testable
│   ├── Card / Suit / Rank
│   ├── Difficulty
│   ├── Deck             (SeededGenerator: SplitMix64, Fisher–Yates)
│   ├── GameState        (value type: columns, stock, completed, score, moves; rule queries)
│   ├── SpiderGame       (engine: perform(Action) → ActionOutcome, undo, UndoPolicy, ScoringRules)
│   ├── Hints            (GameState.hints(), hasLegalMove)
│   └── Statistics
├── SpiderSolitaire     macOS app (SwiftUI; AppKit only where SwiftUI falls short)
│   ├── SpiderSolitaireApp   App, Commands (menus and shortcuts), Settings scene
│   ├── GameModel            @MainActor ObservableObject wrapping SpiderGame and animation state
│   ├── BoardView, ColumnView, CardView, StockView, FoundationView, ScoreBoxView
│   ├── DragState            drag gesture and hit-testing (geometry via PreferenceKeys)
│   ├── WinAnimationView
│   └── Persistence          JSON files for the save and statistics
└── SpiderCoreTests     XCTest: deck, layout, move rules, deal, completion, scoring, undo, hints,
                        Codable, statistics, randomized invariant playthroughs
```

- **Single source of truth:**
  - The UI never changes cards itself. It calls `game.perform(action)` and animates the returned
    `ActionOutcome`, which lists the completed runs and the ids of revealed cards.
  - Each card's `id` is stable across a whole game, so SwiftUI `matchedGeometryEffect` can animate a
    card from its old position to its new one.
- **Value semantics:** `GameState` is a struct. Undo stores whole snapshots, which at about 104 cards
  each is cheap, so there is no inverse-move bookkeeping to get wrong.
- **Testability:** every rule lives in `SpiderCore`, which compiles and is tested on Linux CI. The UI
  holds no rules, only drawing, gestures and timing.
- **Toolchain:**
  - swift-tools-version 5.9, macOS 14 deployment target, Swift 5 language mode.
  - Builds with Xcode 15 or later. Tested on the Swift 6.0.3 Linux toolchain.
- **Packaging (M8):**
  - `scripts/package.sh` runs `swift build -c release`, renders the icon with the `SpiderIcon`
    tool (CoreGraphics), builds the `.icns` with `sips`/`iconutil`, assembles
    `build/Spider Solitaire.app/Contents/{MacOS,Resources,Info.plist,PkgInfo}`, ad-hoc codesigns it
    (`codesign --force --deep -s -`) and zips it to `build/SpiderSolitaire.zip`.
  - `Info.plist`: `com.dansailer.SpiderSolitaire`, "Spider Solitaire", category
    `public.app-category.card-games` (Apple's games subcategory), `LSMinimumSystemVersion` 14.0.
  - An Xcode project can be generated later if the app goes to the App Store or needs notarization.
