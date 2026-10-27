# Spider Solitaire (macOS)

A native macOS clone of Windows XP Spider Solitaire, written in Swift and SwiftUI.

- The rules and UI are described in [SPEC.md](SPEC.md).
- The plan is in [MILESTONES.md](MILESTONES.md). Milestone **M1** (the rules engine) is done. **M2** (the
  board, with cards drawn in code) and **M3** (drag and drop, click the stock to deal, double-click to
  auto-move) build on a Mac. **M4** (deal and completed-suit animations) and **M5** (hints, undo modes,
  the no-more-moves dialog) are implemented.

## Requirements
- macOS 14 (Sonoma) or later
- Xcode 15 or later (it includes Swift 5.9 or later), or the matching Command Line Tools

## Build, run and test from the terminal
```bash
cd spider-solitaire
swift build                  # builds SpiderCore and the app
swift run SpiderSolitaire    # launches the game window
swift test                   # runs the SpiderCore XCTest suite
```

If `swift run` opens a window that won't take keyboard focus, click it once.

## Package as a `.app`
```bash
./scripts/package.sh                 # or: bash scripts/package.sh
open "build/Spider Solitaire.app"
```
The script (macOS only):
1. Runs `swift build -c release`.
2. Renders the icon in code (`swift run SpiderIcon`, CoreGraphics) and turns it into `AppIcon.icns`
   with `sips` and `iconutil`.
3. Assembles `build/Spider Solitaire.app` from `Packaging/Info.plist` (bundle id
   `com.dansailer.SpiderSolitaire`, minimum macOS 14).
4. Ad-hoc signs it (`codesign --force --deep -s -`) and zips it to `build/SpiderSolitaire.zip`.

Options: `VERSION=1.2.0` sets the version (default 1.0.0), `BUILD_NUMBER` defaults to the git commit
count, and `UNIVERSAL=1` builds arm64 + x86_64 (needs full Xcode). The app is ad-hoc signed, not
notarized: on another Mac, right-click ▸ Open the first time.

CI: `.github/workflows/ci.yml` runs the tests on Linux and macOS 14 and uploads the zip.

## Open in Xcode
```bash
open Package.swift           # or: xed .
```
Then:
1. Pick the **SpiderSolitaire** scheme and **My Mac** as the destination.
2. Press ⌘R to run or ⌘U to run the tests.

Xcode opens the Swift package directly, so no `.xcodeproj` is needed.

## Controls
- **Drag** any face-up card that starts a same-suit descending run (the run comes with it) onto a
  card one rank higher, or onto an empty column. An illegal drop slides the cards back.
- **Double-click** a card to send its run to the best legal column.
- **Click the stock** (bottom right) or press **D** to deal a row.
- **M**, or a click on the score box, flashes the next available move. Press again to cycle through them.
- **Options** (Game ▸ Options…) has a "Play sounds" switch (off by default; macOS system sounds).
- After a win, click or press any key to skip the celebration.
- **⌘Z** undoes a move. Game ▸ Classic XP Undo makes undo stop at deals and completed suits, like
  XP. **⌘N** starts a new game. File ▸ New Game With Difficulty chooses 1, 2 or 4
  suits.

## Linux (rules engine only)
`SpiderCore` and `SpiderBoard` use only the Swift standard library, so they build and test anywhere Swift runs:
```bash
swift build --target SpiderCore
swift test
```
On Linux, the app target compiles to a small console stub, because SwiftUI is not available there.

## Layout
```
Package.swift
Sources/SpiderCore/        rules engine (Card, Deck, GameState, SpiderGame, Hints, Statistics)
Sources/SpiderBoard/       pure-Swift board geometry and pointer handling (BoardLayout, PointerController)
Sources/SpiderPersistence/ JSON files in Application Support (SpiderStore)
Sources/SpiderSolitaire/   SwiftUI app (App and menus, GameModel, BoardView, CardView, WinCelebrationView)
Sources/SpiderIcon/        code-drawn app icon renderer (CoreGraphics → 1024 px PNG)
Packaging/Info.plist       app bundle Info.plist template
scripts/package.sh         builds, signs and zips build/Spider Solitaire.app
Tests/SpiderCoreTests/     XCTest suite for the rules
Tests/SpiderBoardTests/    XCTest suite for layout, hit-testing, drag/drop and double-click
Tests/SpiderPersistenceTests/ XCTest suite for saving, loading and quit/resume
SPEC.md  MILESTONES.md
```
