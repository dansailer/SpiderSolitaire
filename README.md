# Spider Solitaire (macOS)

A native macOS clone of Windows XP Spider Solitaire, written in Swift and SwiftUI.

- The rules and UI are described in [SPEC.md](SPEC.md).
- It builds, tests and packages on macOS 14; the rules engine also builds and tests on Linux.

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

The script also copies SwiftPM's resource bundle (`SpiderSolitaire_SpiderSolitaire.bundle`, which holds the
Classic card faces) into `Contents/Resources` in the standard bundle layout, so the app works outside the
build folder.

## Artwork previews on any platform
```bash
swift run SpiderIcon icon.svg                # app icon (on a Mac, icon.png renders with CoreGraphics)
swift run SpiderIcon --card-back back.svg    # card back at 120 x 162 pt
swift run SpiderIcon --badges badges/        # every achievement medal, locked and unlocked
python3 scripts/cards/preview_faces.py faces.png
```
The icon and card back are described once as data in `Sources/SpiderBoard/VectorArt.swift`. SwiftUI,
CoreGraphics and SVG all draw from that description. The back has a gold rosette and the icon has a
spade card; there are no spider motifs anywhere.

## Classic card art
The Classic faces come from Dmitry Fomin's "English pattern" deck on Wikimedia Commons (CC0). That deck
draws every suit pip into a tall 2:3 box, so the build script rescales each pip about its centre to the
usual proportions (hearts about 1:1). The PNGs keep the source's 2:3 aspect (240 x 360), and CardView fits
them onto the 71:96 card with one uniform scale. The ace of
spades also uses the ornate centre spade from Byron Knoll's public-domain deck. To regenerate them, you need
Pillow, `rsvg-convert`, `pngquant` and `optipng`; run `python3 scripts/cards/build_classic_cards.py`. It checks
each file page's licence and writes `Resources/Cards/CREDITS.md`.

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
- **Click the stock** (bottom right) or choose Game ▸ Deal Next Row (⌘D) to deal a row.
- **Click the score box**, or Game ▸ Show Hint (⌘T), to flash the next available move. Repeat to cycle.
- **Settings…** (⌘,) has animations, sounds (off by default; macOS system sounds), **Card faces:
  Classic / Simple**, **Only deal winnable games**, the undo mode and the save/open-at-launch rules.
  Changes apply at once.
- **Only deal winnable games:** new games use deals a built-in solver has proved winnable. Usually
  instant; otherwise "Dealing a winnable game…" appears for up to 5 s (Cancel deals a random game).
- **Achievements** (Game ▸ Achievements…, ⇧⌘A): 14 medals, listed with their thresholds in SPEC.md §7.
  A banner appears at the top of the board when one unlocks. The score box shows the game's play time.
- After a win, click or press any key to skip the celebration.

### Menus and shortcuts
| Menu | Item | Shortcut |
|---|---|---|
| Spider Solitaire | About Spider Solitaire, Settings… (⌘,), Services, Hide (⌘H), Hide Others (⌥⌘H), Show All, Quit (⌘Q) | |
| Game | New Game | ⌘N |
| | Restart Game | ⇧⌘N |
| | Undo / Redo | ⌘Z / ⇧⌘Z |
| | Deal Next Row | ⌘D |
| | Show Hint | ⌘T |
| | Difficulty ▸ One Suit / Two Suits / Four Suits | ⌘1 / ⌘2 / ⌘4 |
| | Statistics… | ⌘I |
| | Achievements… | ⇧⌘A |
| | Save Game / Open Saved Game | ⌘S / ⌘O |
| | Close Window | ⌘W |
| Window | Minimize, Zoom, Enter Full Screen | ⌘M, –, ⌃⌘F |
| Help | Spider Solitaire Help: rules, scoring, tips, achievements and every shortcut | ⌘? |

There is no File, Edit or View menu and no window tabs. SPEC.md §3.5 explains each choice.

## Solver tool (developers)
```bash
swift build -c release --product SpiderTools
.build/release/SpiderTools bench 2 50     # success rate and time per seed, as the app runs it
.build/release/SpiderTools find 4 20      # time to find one winnable deal
.build/release/SpiderTools seeds 1 24     # generate verified seeds for WinnableDeals.bundled
.build/release/SpiderTools help           # the help window's text as Markdown
```

`python3 scripts/check_builders.py` flags any SwiftUI builder block with more than 10 direct
children (the `Commands` and `Scene` builders stop at 10, and Linux can't compile the app target).

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
Sources/SpiderIcon/        renders VectorArt (app icon, card back, badges) to PNG (CoreGraphics) or SVG (any platform)
Sources/SpiderTools/       dev-only solver tool: bench, find, seeds, bundled (not part of the app)
Sources/SpiderSolitaire/Resources/Cards/  Classic card faces (52 PNGs, CC0/public domain, see CREDITS.md)
scripts/cards/             build_classic_cards.py (download, licence check, pip fix, render), preview.py, preview_faces.py
Packaging/Info.plist       app bundle Info.plist template
scripts/package.sh         builds, signs and zips build/Spider Solitaire.app
Tests/SpiderCoreTests/     XCTest suite for the rules
Tests/SpiderBoardTests/    XCTest suite for layout, hit-testing, drag/drop and double-click
Tests/SpiderPersistenceTests/ XCTest suite for saving, loading and quit/resume
SPEC.md
```
