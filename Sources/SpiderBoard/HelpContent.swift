import SpiderCore

/// One piece of a help page.
public enum HelpBlock: Hashable, Sendable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    /// A two-column table (left: name or shortcut, right: what it does).
    case table(header: [String], rows: [[String]])
}

public struct HelpSection: Hashable, Sendable, Identifiable {
    public enum ID: String, CaseIterable, Sendable {
        case rules, scoring, tips, achievements, shortcuts
    }

    public let id: ID
    public let title: String
    /// SF Symbol for the sidebar.
    public let symbol: String
    public let blocks: [HelpBlock]
}

/// The built-in help (Help ▸ Spider Solitaire Help). Written as data so tests can check it against
/// the game: the scoring numbers come from `ScoringRules` and `GameState`, the achievements from
/// `Achievement.all`, and the shortcuts from `MenuCommand`, so the text never drifts from the code.
public enum HelpContent {
    public static var sections: [HelpSection] {
        [rules, scoring, tips, achievements, shortcuts]
    }

    public static func section(_ id: HelpSection.ID) -> HelpSection {
        sections.first { $0.id == id }!
    }

    // MARK: Rules

    static var rules: HelpSection {
        let deals = GameState.fullStockCount / GameState.columnCount
        return HelpSection(
            id: .rules, title: "Rules", symbol: "book",
            blocks: [
                .heading("The goal"),
                .paragraph(
                    "Build eight complete runs, King down to Ace in a single suit. Each finished run leaves "
                        + "the table on its own. When all eight are done, you win."),
                .heading("The layout"),
                .paragraph(
                    "Two packs (104 cards) are dealt into \(GameState.columnCount) columns: the first four get 6 cards, "
                        + "the other six get 5. Only the top card of each column is face up. The other "
                        + "\(GameState.fullStockCount) cards wait in the stock at the bottom right, enough for \(deals) more deals."
                ),
                .heading("Moving cards"),
                .bullets([
                    "Drag a face-up card onto a card exactly one rank higher, in any suit: a 7 goes on any 8.",
                    "You can move several cards at once only if they are in order and all the same suit, "
                        + "such as 9♥ 8♥ 7♥.",
                    "When a move uncovers a face-down card, it turns over by itself.",
                    "Double-click a card to send it (with the cards on top of it) to the best place.",
                ]),
                .heading("Empty columns"),
                .paragraph(
                    "Any card, or any run in one suit, can go into an empty column. Empty columns are your best "
                        + "tool for sorting cards, so use them carefully."),
                .heading("Dealing"),
                .paragraph(
                    "Click the stock, or choose Game ▸ Deal Next Row, to put one new card face up on every column. "
                        + "You can't deal while a column is empty: fill it first. (The one exception is near the end, "
                        + "when there are fewer than \(GameState.columnCount) cards on the table.)"),
                .heading("Completing suits"),
                .paragraph(
                    "As soon as a column ends with King to Ace in one suit, those 13 cards fly to the bottom left "
                        + "and the card under them turns face up."),
                .heading("Difficulty"),
                .bullets([
                    "One Suit: every card is a spade. The gentlest start.",
                    "Two Suits: spades and hearts. You'll need to keep the suits apart.",
                    "Four Suits: all four suits. A real challenge; many deals take several tries.",
                ]),
                .paragraph("Change it from Game ▸ Difficulty. A new game starts at the chosen level."),
            ])
    }

    // MARK: Scoring

    static var scoring: HelpSection {
        let r = ScoringRules()
        let start = GameState.initialScore
        let suits = GameState.suitsToWin
        let deals = GameState.fullStockCount / GameState.columnCount
        let best = start + suits * r.completedSuitBonus
        func points(_ n: Int) -> String { n == 1 ? "1 point" : "\(n) points" }
        return HelpSection(
            id: .scoring, title: "Scoring", symbol: "number",
            blocks: [
                .paragraph("Every game starts at \(start) points."),
                .table(
                    header: ["Event", "Points"],
                    rows: [
                        ["Each completed suit", "+\(r.completedSuitBonus)"],
                        ["Each move", "−\(r.movePenalty)"],
                        ["Each undo", "−\(r.undoPenalty) (the undone move's point is not given back)"],
                        ["Each redo", "−\(r.movePenalty) (it counts as a move)"],
                        ["Dealing a row", r.dealPenalty == 0 ? "free" : "−\(r.dealPenalty)"],
                    ]),
                .paragraph(
                    "So a perfect game would score \(best) points (\(start) + \(suits) × \(r.completedSuitBonus)), and "
                        + "every move and undo takes \(points(r.movePenalty)) off. The Moves counter counts moves, undos and "
                        + "deals. In a won game with the usual \(deals) deals, your final score is \(best + deals * r.movePenalty) "
                        + "minus the Moves counter: fewer moves, higher score."),
                .heading("Time"),
                .paragraph(
                    "The score box also shows how long you've played this game. The clock pauses while Spider "
                        + "Solitaire is in the background or a dialog is open, and it is saved with the game. Time doesn't "
                        + "change the score, but some achievements ask for a quick win."),
            ])
    }

    // MARK: Tips

    static var tips: HelpSection {
        HelpSection(
            id: .tips, title: "Tips", symbol: "lightbulb",
            blocks: [
                .heading("Ask for a hint"),
                .paragraph(
                    "Choose Game ▸ Show Hint (\(MenuCommand.showHint.shortcut!)) or click the score box. The cards "
                        + "that can move light up, then where they can go. Ask again to see the next idea. If there are no "
                        + "moves left, the game tells you."),
                .heading("Play winnable deals"),
                .paragraph(
                    "Turn on \"Only deal winnable games\" in Settings and every new game is one a built-in solver "
                        + "has already won. It usually takes a moment at most; with four suits it can take a few seconds."
                ),
                .heading("Undo the way you like"),
                .paragraph(
                    "Undo (\(MenuCommand.undo.shortcut!)) can go back to the start of the game, and Redo "
                        + "(\(MenuCommand.redo.shortcut!)) brings moves back. For a stricter game, choose Classic XP undo in "
                        + "Settings: then undo stops at each deal and each completed suit, like the original."),
                .heading("A few strategy ideas"),
                .bullets([
                    "Uncover face-down cards early, especially in the tallest columns.",
                    "Build in one suit when you can; mixed runs have to be taken apart later.",
                    "Keep an empty column free for as long as possible rather than parking a single card there.",
                    "Before dealing, tidy up: a deal drops a card on every column, including your best runs.",
                ]),
            ])
    }

    // MARK: Achievements

    static var achievements: HelpSection {
        HelpSection(
            id: .achievements, title: "Achievements", symbol: "rosette",
            blocks: [
                .paragraph(
                    "Achievements unlock as you play and stay unlocked. A banner slides in when you earn one, "
                        + "and Game ▸ Achievements… (\(MenuCommand.achievements.shortcut!)) shows them all, with the date "
                        + "you earned each."),
                .table(
                    header: ["Achievement", "How to earn it"],
                    rows: Achievement.all.map { [$0.title, $0.hint] }),
                .paragraph(
                    "Wins and streaks count from your Statistics. A game resumed from a save made by an older "
                        + "version can't earn the ones about undo, hints or time, because its history isn't known."),
            ])
    }

    // MARK: Shortcuts

    /// Shortcuts macOS gives every app, shown after the game's own.
    public static let standardShortcuts: [(title: String, shortcut: MenuShortcut)] = [
        ("Settings…", MenuShortcut(",")),
        ("Hide Spider Solitaire", MenuShortcut("h")),
        ("Hide Others", MenuShortcut("h", option: true)),
        ("Quit Spider Solitaire", MenuShortcut("q")),
        ("Minimize", MenuShortcut("m")),
    ]

    static var shortcuts: HelpSection {
        func rows(_ menu: MenuCommand.Menu, prefix: String = "") -> [[String]] {
            MenuCommand.items(in: menu).compactMap { command in
                command.shortcut.map { [$0.description, prefix + command.title] }
            }
        }
        return HelpSection(
            id: .shortcuts, title: "Keyboard Shortcuts", symbol: "keyboard",
            blocks: [
                .heading("Game"),
                .table(
                    header: ["Keys", "Command"],
                    rows: rows(.game) + rows(.difficulty, prefix: "Difficulty: ")),
                .heading("Window and app"),
                .table(
                    header: ["Keys", "Command"],
                    rows: rows(.window) + rows(.help) + standardShortcuts.map { [$0.shortcut.description, $0.title] }),
                .heading("Mouse"),
                .bullets([
                    "Click the stock to deal a row.",
                    "Click the score box for a hint.",
                    "Double-click a card to move it to the best place.",
                    "During the win celebration, click or press any key to skip it.",
                ]),
            ])
    }

    // MARK: Plain text

    /// Markdown version of a section (previews, and a readable form for tests).
    public static func markdown(_ section: HelpSection) -> String {
        var out = "# \(section.title)\n"
        for block in section.blocks {
            switch block {
            case .heading(let text): out += "\n## \(text)\n"
            case .paragraph(let text): out += "\n\(text)\n"
            case .bullets(let items): out += "\n" + items.map { "- \($0)\n" }.joined()
            case .table(let header, let rows):
                out += "\n| " + header.joined(separator: " | ") + " |\n|" + header.map { _ in "---|" }.joined() + "\n"
                out += rows.map { "| " + $0.joined(separator: " | ") + " |\n" }.joined()
            }
        }
        return out
    }
}
