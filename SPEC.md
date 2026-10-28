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
are drawn in code (vector suit symbols and court-card lettering), or come from a CC0 set (Classic faces, §3.6a).
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
- Clicking the stock (or Game ▸ Deal Next Row, ⌘D) deals **one face-up card onto each of the 10 columns**,
  left to right.
- **No deal is allowed while any column is empty.** XP shows the message "You are not allowed to
  deal a new row while there are any empty slots."
  - *Decision:* if the tableau holds fewer than 10 cards in total, filling every column is
    impossible, so the deal is allowed anyway. This only happens late in a game.
- A deal can complete a run. All 10 columns are checked afterwards.

### 2.5 Completed suits
- When the top 13 cards of a column form a face-up **K→A run of one suit**, they are removed to the
  foundation automatically and earn **+100**. The newly exposed card turns face up.
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

### 2.8 Hints (Game ▸ Show Hint, ⌘T, or a click on the score box)
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
- The background is green felt: `#007F0E`, with a subtle radial vignette.
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
- **Drag and drop:**
  - Pressing on a movable card lifts it and every card above it.
  - The dragged run follows the cursor with a shadow.
  - On release, the run drops onto the column whose top card's frame, or empty slot, overlaps it
    most.
  - An illegal drop animates the run back.
  - Cards the player cannot lift give no drag feedback.
- **Click-to-move:** double-clicking a movable run sends it to the best legal target,
  using the same ordering as the hints.
- **Animations:**
  - dealing, XP style, one card after another so each landing can be followed (`DealPacing`): a stock deal
    sends its 10 cards 80 ms apart, each flying 240 ms with ease-out (about 1 s); a new game or restart deals
    its 54 cards row by row from the stock, 50 ms apart (about 3 s). Each card stays face down on the pile
    until it leaves. The game state is complete at once; only the drawing lags. A click or plain key press
    finishes the deal instantly and does nothing else; any menu action (undo, hint, deal…) settles it first.
    The deal sound plays per stock card and once per row of the new-game deal. macOS Reduce Motion makes
    deals instant too,
  - a completed run flies to the foundation one card at a time, starting with the top card (A) and ending with the K, staggered by 40 ms, about 0.3 s per card. The foundation king appears once all 13 cards have landed,
  - an exposed card flips over.
  Settings → "Show animations" turns all of these off.

### 3.5 Menus and shortcuts
The menu bar follows the macOS HIG: one game window (no New Window), no window
tabs, no File, Edit or View menu. Titles are Title Case; an ellipsis marks only items that open a
window needing more input. Titles and shortcuts for the app's own items live in one table,
`MenuCommand` (SpiderBoard), which tests check for duplicates, for clashes with
`MenuCommand.reservedShortcuts` (system and standard app/Window-menu shortcuts) and for bare keys.
There are no bare-key shortcuts and no F2; clicking the stock deals and clicking the score box shows
a hint.

| Menu | Item | Shortcut | XP equivalent |
|---|---|---|---|
| Spider Solitaire | About Spider Solitaire | | Help ▸ About |
| | Check for Updates… | | |
| | Settings… (XP's Options) | ⌘, | Game ▸ Options |
| | Services ▸ | | |
| | Hide Spider Solitaire | ⌘H | |
| | Hide Others | ⌥⌘H | |
| | Show All | | |
| | Quit Spider Solitaire | ⌘Q | Game ▸ Exit |
| Game | New Game | ⌘N | F2 |
| | Restart Game | ⇧⌘N | |
| | Undo | ⌘Z | Ctrl+Z |
| | Redo | ⇧⌘Z | (none) |
| | Deal Next Row | ⌘D | D |
| | Show Hint | ⌘T | M |
| | Difficulty ▸ One Suit / Two Suits / Four Suits (checked = current game) | ⌘1 / ⌘2 / ⌘4 | Game ▸ Difficulty |
| | Statistics… | ⌘I | Game ▸ Statistics |
| | Achievements… | ⇧⌘A | |
| | Save Game | ⌘S | Ctrl+S |
| | Open Saved Game | ⌘O | Ctrl+O |
| | Close Window | ⌘W | |
| Window | Minimize | ⌘M | |
| | Zoom | | |
| | Enter Full Screen / Exit Full Screen | ⌃⌘F | |
| | (window list, Bring All to Front, and the macOS 15 tiling items) | | |
| Help | Spider Solitaire Help, and the menu search field | ⌘? | F1 / Help ▸ Contents |
| | Visit Website | | |

Why these keys:
- **⌘D Deal Next Row:** the HIG's ⌘D is Duplicate, which has no meaning in a card game. It keeps XP's D.
  The Difficulty dialog it used to open became a submenu with ⌘1 / ⌘2 / ⌘4 for 1, 2 and 4 suits.
- **⌘T Show Hint ("tip"):** ⌘H is Hide and ⌘M Minimize. ⌘T is Show Fonts or New Tab elsewhere, and
  this app has no Format menu and no tabs.
- **⌘I Statistics:** like Finder's Get Info; there is no text to make italic.
- **⇧⌘N Restart Game:** pairs with ⌘N; it is only New Folder in Finder.
- **Redo** replays the last undone action as a new move: it costs the move penalty and counts on the
  Moves counter, since undo's own penalty is never refunded. Any new action clears the redo
  history. In Classic XP undo mode, redo can only bring back what undo could reach.
- **Close Window** sits in the Game menu because there is no File menu. Closing the game window quits
  the app (the usual quit-time save rules apply).
- **⌘? Spider Solitaire Help** is the standard Help shortcut (⇧⌘/ on most layouts). It opens a
  single help window (about 560 × 640 pt, resizable) with a sidebar of five
  sections: Rules, Scoring, Tips, Achievements and Keyboard Shortcuts. The text lives as data in
  `HelpContent` (SpiderBoard). The scoring numbers come from `ScoringRules`, the achievements table
  from `Achievement.all`, and the shortcuts table from `MenuCommand` plus the standard app and window
  shortcuts, so tests catch any drift.
- **The app owns the menu bar.** It uses the AppKit app lifecycle (`NSApplication` with an app
  delegate) and hosts its SwiftUI views in `NSWindow`s, so there are no SwiftUI `Commands` at all.
  With SwiftUI `Commands`, SwiftUI rebuilt the menu bar whenever the observed game changed and
  re-added its standard View and Format menus each time, so they flickered in and out even when a
  clean-up removed them afterwards. Now `MainMenuBuilder` builds the bar once at launch from
  `MenuBarLayout` (SpiderBoard, tested: exactly app, Game, Window and Help; every `MenuCommand` once;
  Enter Full Screen once, in the Window menu, as AppKit's `toggleFullScreen:`, which AppKit retitles
  to Exit Full Screen). Nothing edits the bar afterwards. Undo, Redo, Open Saved Game and the
  Difficulty check marks come from `validateMenuItem(_:)`, which AppKit runs only when a menu opens
  or a shortcut is pressed. `NSApp.windowsMenu` and `NSApp.helpMenu` are set, so macOS adds the
  window list and the Help search field. `NSFullScreenMenuItemEverywhere`, window tabbing,
  `NSDisabledDictationMenuItem` and `NSDisabledCharacterPaletteMenuItem` are switched off so AppKit
  adds no items of its own.
- On macOS 15 and later, AppKit adds its own visible Enter Full Screen item (shortcut 🌐F) beside
  the app's and hides the app's one, which keeps ⌃⌘F working. The menu shows the item once.
- `SpiderSolitaire --menu-probe 10` plays moves for 10 seconds while printing the menu bar four
  times a second. It exits with status 0 only if the bar never changed, its menus are exactly
  those of `MenuBarLayout`, and one Full Screen item is visible.

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
- Settings → Card faces: **Classic** (default) or **Simple**. It is saved in options.json; older files
  without the key decode as Classic.
- Classic: 240 × 360 px PNGs, the source's own 2:3 aspect, drawn with `.aspectRatio(contentMode: .fit)` (uniform
  scale, white side margins). The source deck's pips are drawn 2:3 (too tall); the build rescales them to normal
  proportions from Dmitry Fomin's CC0 English-pattern deck. The ace
  of spades has Byron Knoll's public-domain ornate spade. The images live in the app target's resources
  (`.copy("Resources/Cards")`), and sources and licences are listed in `Resources/Cards/CREDITS.md`.
- CardView draws the image on the white card, clipped to the rounded rect, with the usual border.
- Card back: blue gradient, white lattice, gold frame and a gold rosette in a lozenge (no spider). The icon
  shows a blue back and a white card with a large spade. Both come from `VectorArt.swift`. If
  an image can't be found, it falls back to the code-drawn face. Card backs are unchanged.

### 3.6b Winnable deals and the game clock
- Settings → "Only deal winnable games" (off by default; older options.json files decode as off).
- With it on, a new game uses a seed the solver (§6) has proved winnable:
  1. a seed found earlier in the background (`winnable.json`), so the deal is instant;
  2. otherwise a search of random seeds for up to 5 s, off the main thread, while the board shows
     "Dealing a winnable game…" with a Cancel button (Cancel deals an unchecked random game);
  3. if the search runs out of time, the next of 24 bundled, verified seeds for that difficulty;
  4. only if none is available, a random deal with a notice.
  After each winnable deal a background search refills the cache to 3 seeds per difficulty.
  Restart replays the same seed. Statistics count these games like any other.
- The score box shows **Time** (m:ss) under Score and Moves. The clock runs while the app is active,
  the game is not won and no dialog, sheet, deal search or win animation is up. It is saved with the game.

### 3.6c Achievements
- 14 achievements (§7). When one unlocks, a banner slides in at the top of the board for about 3 s
  (no slide with animations off; the "Purr" sound with sounds on). Click it to dismiss it.
- Game ▸ Achievements… (⇧⌘A) opens a window with a grid of medals drawn in code (`BadgeArt`):
  gold with the unlock date once earned, grey with the hint before. No spider motifs.

### 3.6d Settings and updates
- Settings (⌘,) is a toolbar tab window: General (save on quit, what opens at launch, sounds, automatic update
  check), Gameplay (winnable deals, undo rules; difficulty stays in Game ▸ Difficulty), Appearance (live
  previews of the Classic and Simple faces and the card back, animations) and Credits (links to every art source, the repo and the website).
- Check for Updates… (app menu) reads `releases/latest` from GitHub's public API, compares semver with
  CFBundleShortVersionString (`SpiderUpdates`) and offers Download (zip to ~/Downloads, shown in
  Finder) or Later. The automatic check runs at launch at most once a day and is silent unless a newer
  release exists. Drafts, prereleases and non version tags are ignored. No self replacement (that needs
  Developer ID signing and Sparkle).
- Help ▸ Visit Website opens https://dansailer.github.io/SpiderSolitaire/ (source in `docs/`).

### 3.7 Sound
- The game plays short cues for deal, drop, cannot-deal, hint, no-hint and win.
- The cues are built-in macOS system sounds played with `NSSound(named:)` (Pop, Tink, Basso, Ping, Funk,
  Glass, Hero, and Purr for an achievement); no Microsoft or bundled audio. Settings → "Play sounds" is off by default.

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
  - sounds, card faces, only deal winnable games

  Missing or unknown fields fall back to their defaults.
- **Achievements** (`achievements.json`): `{"firstWin": <seconds since 1970>, ...}`. Unknown names are
  skipped, so a newer file never breaks an older app.
- **Winnable seeds** (`winnable.json`): seeds found ahead of time (hex strings, since JSON numbers above
  2^53 are not safe everywhere) and how far through the bundled list each difficulty is.
- The saved game carries a `tracker` (play time, undo count, hint count). Saves from before it existed
  decode with an "unknown history" tracker, which can't earn Purist, No Peeking, Grandmaster or Speedster.
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
│   ├── Solver, WinnableDeals  (best-first solver, bundled and cached winnable seeds)
│   ├── Achievements     (list, GameTracker, AchievementBook, evaluator)
│   └── Statistics
├── SpiderSolitaire     macOS app (SwiftUI; AppKit only where SwiftUI falls short)
│   ├── SpiderSolitaireApp   entry point, app delegate, windows, menu probe
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
- **Packaging:**
  - `scripts/package.sh` runs `swift build -c release`, renders the icon with the `SpiderIcon`
    tool (CoreGraphics), builds the `.icns` with `sips`/`iconutil`, assembles
    `build/Spider Solitaire.app/Contents/{MacOS,Resources,Info.plist,PkgInfo}`, signs it inside out
    (ad hoc, or `SIGN_IDENTITY` with hardened runtime and a secure timestamp) and zips it to
    `build/SpiderSolitaire.zip`. The Release workflow signs with the Developer ID, notarizes and
    staples (`scripts/notarize.sh`).
  - `Info.plist`: `com.dansailer.SpiderSolitaire`, "Spider Solitaire", category
    `public.app-category.card-games` (Apple's games subcategory), `LSMinimumSystemVersion` 14.0.
  - An Xcode project can be generated later if the app goes to the App Store.

## 6. Solver (`SpiderCore/Solver.swift`)
- Pure Swift, deterministic for a given budget. It sees the face-down cards, so "winnable" means a
  solution exists for that seeded deal.
- **Search:** best-first. Each open position gets a score and the best one is expanded next:
  +1000 per finished suit, +40 per empty column, +12 per same-suit link, +3 per out-of-suit link
  (+8 in the "tidy" weights), -6 per break inside a face-up pile (-20 tidy), -20 per face-down card
  (-30 tidy), -2 per card over face-down cards, +2 per card dealt. So building in suit, revealing
  cards and completing runs come first. Dealing from the stock is an ordinary move.
- **Transposition table:** a 64-bit FNV-1a hash of the canonical position (exact columns with face-up
  bits, stock size). The stock's order is fixed by the deal, so its size is enough.
- **Pruning:** only whole same-suit runs move out of their pile unless the split lands in suit; a card
  never moves between two equal out-of-suit parents; into an empty column only the first empty
  column, only whole runs, and never a whole column.
- **Budgets:** node and depth limits plus a `shouldStop` hook (deadline and cancel). Results are
  `.solved([Action])`, `.unsolvable` (the whole space was searched) or `.gaveUp`.
  `Solver.verify` replays a line on a fresh `SpiderGame`; every line the app relies on is verified.
- **Per seed** (`SolverBudget.attempts`): solving time is heavy-tailed (most deals take a few
  thousand positions, a few need a million), so each seed gets two modest attempts and the app moves
  on to the next seed instead of digging:

  | Difficulty | Attempts |
  |---|---|
  | 1 suit | 60k nodes balanced, then 60k tidy |
  | 2 suits | 120k balanced, then 120k tidy |
  | 4 suits | 300k tidy, then 200k balanced |

- **Measured on the box** (Linux, release build, one core; `SpiderTools bench <suits> 50` and
  `SpiderTools find <suits> 20`):

  | Difficulty | Seeds solved (50) | Avg time per seed | Avg time when solved | Avg solution | Time to find a winnable deal (20 runs) |
  |---|---|---|---|---|---|
  | 1 suit | 33 (66 %) | 0.33 s | 0.12 s | 148 moves | median 0.12 s, avg 0.36 s, max 1.8 s; 20/20 within 5 s |
  | 2 suits | 39 (78 %) | 0.47 s | 0.25 s | 250 moves | median 0.22 s, avg 0.60 s, max 3.4 s; 20/20 within 5 s |
  | 4 suits | 13 (26 %) | 1.49 s | 0.70 s | 495 moves | median 3.5 s, avg 4.3 s, max 16.5 s; 13/20 within 5 s |

  No seed was proved unsolvable: "not solved" means the budget ran out, not that the deal is lost.
  With bigger budgets more seeds solve (1 suit: 86 % at 300k nodes, 91 % at 1M), but trying another seed
  is cheaper. For 4 suits the 5 s search fails about a third of the time; then the cache or the
  bundled list supplies the deal.

- `SpiderTools` (dev only, not shipped): `bench`, `find`, `seeds` (generates the bundled lists) and
  `bundled` (re-checks them). `W=key=value,...` tunes the weights.

## 7. Achievements (`SpiderCore/Achievements.swift`)
Data-driven: each entry has an id, title, hint, emblem and a rule. `AchievementEvaluator` checks the
rules after every card move or deal (`played`) and after every result that goes into the statistics
(`resultRecorded`: a win, or a loss from abandoning, quitting without saving or declining a save).

| Achievement | Rule | Threshold |
|---|---|---|
| First Win | win a game | any difficulty |
| Two Suits | win at 2 suits | |
| Four Suits | win at 4 suits | |
| Purist | win without using Undo | any difficulty |
| No Peeking | win without asking for a hint | any difficulty |
| Grandmaster | win at 4 suits without using Undo | |
| Speedster | win within a play time | under 5 min (1 suit), 12 min (2 suits), 25 min (4 suits) |
| Efficient | win with a low Moves counter (moves + deals + undos) | at most 150 (1 suit), 200 (2 suits), 300 (4 suits) |
| Clean Sweep | complete a suit before the first deal | |
| Empty Handed | empty a column before the first deal | |
| Hat Trick | win streak at one difficulty | 3 |
| On a Roll | win streak at one difficulty | 10 |
| Seasoned | games won, all difficulties | 25 |
| Century | games played, all difficulties | 100 |

- **Left out as duplicates:** "Full House" is just a win. "High Roller" (a score threshold) would be the
  same test as Efficient: a win scores 500 + 8 × 100 − card moves − undos, and the Moves counter is
  card moves + undos + deals (5 in a game without undone deals), so a win's score is 1305 − Moves.
  "Score at least 1155" and "at most 150 moves" are the same game.
- Thresholds: the solver's own wins average about 150 moves (1 suit), 250 (2 suits) and 500 (4 suits),
  so Efficient asks for a tidy human game; Speedster's times are a brisk but reachable pace.
- "Before the first deal" means the stock still holds all 50 cards at that moment (an undone deal
  doesn't count as dealt).
- Unlocks are stored with their date in `achievements.json` and never re-locked; resetting statistics
  leaves them alone.

