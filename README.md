# Spider Solitaire (macOS)

A native macOS clone of Windows XP Spider Solitaire, written in Swift and SwiftUI.

- The rules and UI are described in [SPEC.md](SPEC.md).
- It builds, tests and packages on macOS 14; the rules engine also builds and tests on Linux.
- Website: https://dansailer.github.io/SpiderSolitaire/ · Downloads: https://github.com/dansailer/SpiderSolitaire/releases/latest
- Code: MIT ([LICENSE](LICENSE)). Card art: CC0 / public domain ([CREDITS.md](Sources/SpiderSolitaire/Resources/Cards/CREDITS.md)).
- Outside contributions are not accepted ([CONTRIBUTING.md](CONTRIBUTING.md)); report security issues privately ([SECURITY.md](SECURITY.md)).

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
4. Signs it, inside out without `--deep` (ad hoc by default, or with `SIGN_IDENTITY`), and zips it to
   `build/SpiderSolitaire.zip`.

Options: `VERSION=1.2.0` sets the version (default 1.0.0), `BUILD_NUMBER` defaults to the git commit
count, and `UNIVERSAL=1` builds arm64 + x86_64 (needs full Xcode).
`SIGN_IDENTITY="Developer ID Application: Daniel Sailer (595TEE9LSF)"` signs with that keychain identity,
hardened runtime and a secure timestamp (`SIGN_KEYCHAIN` limits the lookup to one keychain); without
it the app is ad-hoc signed, and on another Mac it has to be opened with right-click ▸ Open (or
System Settings ▸ Privacy & Security ▸ Open Anyway) the first time.

Releases after 1.0.0 are Developer ID signed, notarized by Apple and stapled by the Release
workflow, so they open with a double click. v1.0.0 was ad-hoc signed and still needs right-click ▸
Open the first time.

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
| Spider Solitaire | About Spider Solitaire, Check for Updates…, Settings… (⌘,), Services, Hide (⌘H), Hide Others (⌥⌘H), Show All, Quit (⌘Q) | |
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
| | Visit Website (https://dansailer.github.io/SpiderSolitaire/) | |

There is no File, Edit or View menu and no window tabs. SPEC.md §3.5 explains each choice.

### Updates
Spider Solitaire ▸ Check for Updates… asks GitHub's public API for the latest release
(no account, no token, nothing else is sent) and compares it with the running version. If there is
a newer one, Install downloads it with a progress bar and checks it: the zip's SHA-256 against the
release's `.sha256` file, and the app's signature (it must be signed with this project's Developer ID
and be a newer version). Then choose Restart to Update, which quits, swaps in the new version (keeping
the old one until the new one is in place) and reopens it, or Later, which keeps your version and
deletes the download until the next check. If the app can't replace itself (for example it runs
from Downloads, where macOS opens it from a temporary read-only location, or its folder isn't
writable), Install saves `SpiderSolitaire.zip` to Downloads and shows it in Finder instead. When you
open it from Downloads, it offers once to move itself to Applications. With "Check for updates
automatically" on (Settings ▸ General, the default) it checks at launch, at most once a day, and
stays silent unless an update exists.

## Releases, CI and the website
Work happens on branches; `main` only changes through pull requests whose checks passed. The cycle
(details in [CONTRIBUTING.md](CONTRIBUTING.md)):

1. Branch from `main` (`feature/…`, `fix/…`, `ci/…`), commit, run `swift test` and `scripts/lint.sh`.
2. Push and open a pull request into `main`.
3. The required checks run: **Linux tests**, **macOS build and tests**, **SwiftLint**,
   **swift-format** and **jactionlint**. The `protect-main` ruleset blocks the merge until all are
   green and the branch is up to date with `main`; direct pushes to `main` are rejected.
4. Merge (squash, merge commit or rebase); the branch is deleted.
5. To release, tag the merged `main` (the tag is the version), which runs the Release workflow.

Workflows only run in `dansailer/SpiderSolitaire`: for `dansailer`'s pull requests from branches of
this repository, `v*` tags, Pages deploys and manual dispatches (CI does not rerun on `main` after a
merge; the up-to-date pull request was already checked), and for Dependabot's pull
requests (the required checks run on them too). They use `pull_request` (never
`pull_request_target`), so pull request runs get a read-only token and no secrets; fork pull
requests also need approval before anything runs. Every action is pinned to a commit SHA, each job
gets only the permissions it needs, and checkouts do not keep credentials.

| Workflow | Does |
|---|---|
| `ci.yml` | Linux `swift test` in a pinned container; macOS `swift test` plus `scripts/package.sh`; SwiftLint (pinned, checksum-verified release binary); `swift format lint --strict` in a pinned Swift 6.3 container |
| `jactionlint.yml` | Lints the workflows and `dependabot.yml` with jactionlint, pedantic profile, failing on any finding |
| `release.yml` | On a `v*` tag on `main` or a `release/x.y` branch, in the `release` environment: tests, a universal build signed with the Developer ID (`scripts/signing-keychain.sh`, `scripts/package.sh`), notarized and stapled (`scripts/notarize.sh`), then a GitHub release with `SpiderSolitaire.zip`, its `.sha256` and generated notes (a tag with `-` becomes a prerelease) |
| `pages.yml` | Deploys `docs/` to GitHub Pages on pushes to `main` that change it (Settings ▸ Pages ▸ Source must be "GitHub Actions") |

Cut a release from an up to date `main` after the pull request is merged:
```bash
git switch main && git pull --ff-only
git tag -a v1.1.0 -m "Spider Solitaire 1.1.0"
git push origin v1.1.0
```
If the run fails after the tag exists, fix it and rerun it with the tag as the ref, which the
`release` environment requires: `gh workflow run release.yml --ref v1.1.0 -f tag=v1.1.0` (the
workflow builds the tagged commit). Tags are never moved or reused.

Release builds are signed with a Developer ID certificate and notarized by Apple, using secrets that
only the `release` environment (deployable from `v*` tags only) can read; no pull request job sees them.

Lint locally with `scripts/lint.sh` (`--fix` formats and applies SwiftLint's fixes first): it runs
`swift format` from the toolchain with `.swift-format` and SwiftLint with `.swiftlint.yml`, which
`scripts/install-swiftlint.sh` downloads to `.build/tools` (pinned version, SHA-256 checked). Lint the
workflows with `pipx run jactionlint --profile pedantic` (or `pip install jactionlint`).

The website in `docs/` is static HTML, CSS and a little vanilla JavaScript with no build step and no
third party requests; fonts (Cormorant Garamond, Manrope, SIL OFL) and Phosphor icons are committed.
Its screenshots come from the app itself:
```bash
scripts/package.sh && "build/Spider Solitaire.app/Contents/MacOS/SpiderSolitaire" --snapshot /tmp/snaps
python3 scripts/site_assets.py /tmp/snaps <icon.svg> <back.svg> <fontsource dir> <phosphor dir>
```
`--snapshot <dir>` uses a temporary store and a fixed two suit deal, plays 38 solver moves and writes
PNGs of the board, help, achievements and every Settings tab (no screen recording permission needed).
`--menu-probe <seconds>` plays moves while checking that the menu bar never changes (exit 0 if so).

## Solver tool (developers)
```bash
swift build -c release --product SpiderTools
.build/release/SpiderTools bench 2 50     # success rate and time per seed, as the app runs it
.build/release/SpiderTools find 4 20      # time to find one winnable deal
.build/release/SpiderTools seeds 1 24     # generate verified seeds for WinnableDeals.bundled
.build/release/SpiderTools help           # the help window's text as Markdown
```

`python3 scripts/check_builders.py` flags any SwiftUI builder block with more than 10 direct
children (result builders past 10 items fail to compile, and Linux can't compile the app target).

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
Sources/SpiderSolitaire/   SwiftUI views in an AppKit app (app delegate, windows and menu bar, GameModel, BoardView, CardView, WinCelebrationView)
Sources/SpiderIcon/        renders VectorArt (app icon, card back, badges) to PNG (CoreGraphics) or SVG (any platform)
Sources/SpiderTools/       dev-only solver tool: bench, find, seeds, bundled (not part of the app)
Sources/SpiderSolitaire/Resources/Cards/  Classic card faces (52 PNGs, CC0/public domain, see CREDITS.md)
scripts/cards/             build_classic_cards.py (download, licence check, pip fix, render), preview.py, preview_faces.py
Packaging/Info.plist       app bundle Info.plist template
scripts/package.sh         builds, signs and zips build/Spider Solitaire.app
scripts/lint.sh            swift-format and SwiftLint (.swift-format, .swiftlint.yml), as in CI
scripts/install-swiftlint.sh  downloads the pinned, checksum-verified SwiftLint to .build/tools
Tests/SpiderCoreTests/     XCTest suite for the rules
Tests/SpiderBoardTests/    XCTest suite for layout, hit-testing, drag/drop and double-click
Tests/SpiderPersistenceTests/ XCTest suite for saving, loading and quit/resume
SPEC.md
```
