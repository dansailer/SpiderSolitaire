#if canImport(AppKit)
import AppKit
import SpiderBoard
import SpiderCore

/// `--snapshot <dir> --win-frames` (debug check of the win animation, SPEC.md §3.6): the bundled
/// two-suit deal played to its win, board frames taken across the celebration, then the win panel,
/// then the board after Close. Like the other snapshots it uses `cacheDisplay`, so it needs no
/// screen recording permission.
@MainActor
extension SnapshotMode {
    static var winFrames: Bool { CommandLine.arguments.contains("--win-frames") }

    static let winFrameTimes: [Double] = [0.4, 1.2, 2.5, 4.0, 6.0, 8.0, 10.0, 11.5]

    static func runWinFrames(model: GameModel, windows: WindowController, into directory: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let board: NSWindow = windows.showBoard()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            model.prepareWinSnapshot(difficulty: Difficulty.twoSuits)
            let start: Double = ProcessInfo.processInfo.systemUptime
            for t in winFrameTimes {
                try? await Task.sleep(nanoseconds: nanoseconds(until: start + t))
                let ms: Int = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                save(board, String(format: "win-%05dms", ms), directory)
            }
            while model.winSummary == nil, ProcessInfo.processInfo.systemUptime - start < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let ended: Int = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            print(String(format: "WINPANEL %dms", ended))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            save(board, "win-panel", directory)
            model.closeWinSummary()
            try? await Task.sleep(nanoseconds: 800_000_000)
            save(board, "win-closed", directory)
            exit(0)
        }
    }

    private static func nanoseconds(until uptime: Double) -> UInt64 {
        UInt64(max(0, uptime - ProcessInfo.processInfo.systemUptime) * 1_000_000_000)
    }
}
#endif
