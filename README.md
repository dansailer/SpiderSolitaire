# Spider Solitaire (macOS)

A native macOS clone of Windows XP Spider Solitaire, written in Swift and SwiftUI.

- The rules and UI are described in [SPEC.md](SPEC.md).
- The plan is in [MILESTONES.md](MILESTONES.md). Milestone **M1** (the rules engine and its tests)
  is done. The app window is still a placeholder board.

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

If `swift run` opens a window that won't take keyboard focus, click it once. Packaging the game as a
proper `.app` bundle comes in M8.

## Open in Xcode
```bash
open Package.swift           # or: xed .
```
Then:
1. Pick the **SpiderSolitaire** scheme and **My Mac** as the destination.
2. Press ⌘R to run or ⌘U to run the tests.

Xcode opens the Swift package directly, so no `.xcodeproj` is needed.

## Linux (rules engine only)
`SpiderCore` uses only the Swift standard library, so it builds and tests anywhere Swift runs:
```bash
swift build --target SpiderCore
swift test
```
On Linux, the app target compiles to a small console stub, because SwiftUI is not available there.

## Layout
```
Package.swift
Sources/SpiderCore/        rules engine (Card, Deck, GameState, SpiderGame, Hints, Statistics)
Sources/SpiderSolitaire/   SwiftUI app (placeholder board for now)
Tests/SpiderCoreTests/     XCTest suite for the rules
SPEC.md  MILESTONES.md
```
