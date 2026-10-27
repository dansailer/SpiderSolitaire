/// Finds a winning line for a deal. The solver sees the face-down cards, so "winnable" means
/// "a solution exists for this seeded deal". Pure, deterministic for a given budget (the optional
/// `shouldStop` hook is the only outside input, for wall-clock limits and cancellation).
///
/// Search: best-first. Every open position is scored by `Search.evaluate` (finished suits, cards
/// built in suit, revealed cards, empty columns, ...) and the best one is expanded next, so moves
/// that build in suit, reveal face-down cards and complete runs are tried first. Dealing from the
/// stock is an ordinary move. A transposition table of 64-bit hashes of the canonical position
/// skips positions already queued. See SPEC.md §6 for the measured performance.
public struct SolverBudget: Sendable, Hashable {
    /// Positions expanded before giving up.
    public var maxNodes: Int
    /// Longest line considered (card moves + deals).
    public var maxDepth: Int
    /// Position evaluation weights.
    public var weights: SolverWeights

    public init(maxNodes: Int, maxDepth: Int = 1_500, weights: SolverWeights = .balanced) {
        self.maxNodes = maxNodes
        self.maxDepth = maxDepth
        self.weights = weights
    }

    /// The attempts made per seed when looking for a winnable deal, in order. Solving time is
    /// heavy-tailed (most deals solve in a few thousand positions, a few need a million), so the
    /// app gives each seed a modest budget and moves on to the next seed rather than digging.
    public static func attempts(for difficulty: Difficulty) -> [SolverBudget] {
        switch difficulty {
        case .oneSuit: return [SolverBudget(maxNodes: 60_000), SolverBudget(maxNodes: 60_000, weights: .tidy)]
        case .twoSuits: return [SolverBudget(maxNodes: 120_000), SolverBudget(maxNodes: 120_000, weights: .tidy)]
        case .fourSuits: return [SolverBudget(maxNodes: 300_000, weights: .tidy), SolverBudget(maxNodes: 200_000)]
        }
    }
}

/// Evaluation weights (tuned on the box with `SpiderTools bench`).
public struct SolverWeights: Sendable, Hashable {
    public var completedSuit = 1_000
    public var emptyColumn = 40
    public var sameSuitLink = 12
    public var naturalLink = 3
    public var brokenLink = -6
    public var hiddenCard = -20
    public var coverOverHidden = -2
    /// Per card dealt from the stock.
    public var dealDone = 2

    public init() {}

    /// Best for 1 and 2 suits.
    public static let balanced = SolverWeights()

    /// Values out-of-suit (natural) order and punishes mess: best for 4 suits.
    public static let tidy: SolverWeights = {
        var w = SolverWeights()
        w.naturalLink = 8
        w.brokenLink = -20
        w.hiddenCard = -30
        return w
    }()
}

public enum SolverResult: Sendable, Hashable {
    /// A full winning line, playable with `SpiderGame.perform`.
    case solved([Action])
    /// The whole reachable space was searched: this deal cannot be won.
    case unsolvable
    /// Budget or time ran out first.
    case gaveUp
}

public struct SolverReport: Sendable, Hashable {
    public var result: SolverResult
    public var nodes: Int
}

public enum Solver {
    /// Searches from the start of `difficulty`/`seed`.
    public static func solve(
        difficulty: Difficulty, seed: UInt64, budget: SolverBudget,
        shouldStop: (() -> Bool)? = nil
    ) -> SolverReport {
        solve(GameState.newGame(difficulty: difficulty, seed: seed), budget: budget, shouldStop: shouldStop)
    }

    public static func solve(_ start: GameState, budget: SolverBudget, shouldStop: (() -> Bool)? = nil) -> SolverReport
    {
        var search = Search(root: Position(start), budget: budget, shouldStop: shouldStop)
        let result = search.run()
        return SolverReport(result: result, nodes: search.nodes)
    }

    /// Runs `SolverBudget.attempts(for:)` and returns a verified winning line, or nil.
    public static func winningLine(
        difficulty: Difficulty, seed: UInt64,
        shouldStop: (() -> Bool)? = nil
    ) -> [Action]? {
        for budget in SolverBudget.attempts(for: difficulty) {
            if let shouldStop, shouldStop() { return nil }
            switch solve(difficulty: difficulty, seed: seed, budget: budget, shouldStop: shouldStop).result {
            case .solved(let actions):
                return verify(difficulty: difficulty, seed: seed, actions: actions) ? actions : nil
            case .unsolvable:
                return nil
            case .gaveUp:
                continue
            }
        }
        return nil
    }

    /// Plays `actions` on a fresh game and reports whether they are all legal and end in a win.
    public static func verify(difficulty: Difficulty, seed: UInt64, actions: [Action]) -> Bool {
        var game = SpiderGame(difficulty: difficulty, seed: seed)
        for action in actions {
            guard game.canPerform(action), (try? game.perform(action)) != nil else { return false }
        }
        return game.state.isWon
    }
}

// MARK: - Compact position

/// Card byte: bit 7 face up, bits 4-5 suit, bits 0-3 rank (1...13).
struct Position {
    static let faceUp: UInt8 = 0x80

    var columns: [[UInt8]]
    var stock: [UInt8]
    var completed: Int

    init(_ state: GameState) {
        columns = state.columns.map { $0.map(Position.code) }
        stock = state.stock.map(Position.code)
        completed = state.completed.count
    }

    static func code(_ card: Card) -> UInt8 {
        (card.isFaceUp ? faceUp : 0) | UInt8(card.suit.rawValue) << 4 | UInt8(card.rank.rawValue)
    }

    @inline(__always) static func rank(_ c: UInt8) -> UInt8 { c & 0x0F }
    @inline(__always) static func suit(_ c: UInt8) -> UInt8 { (c >> 4) & 0x03 }
    @inline(__always) static func isUp(_ c: UInt8) -> Bool { c & faceUp != 0 }
    @inline(__always) static func continues(_ c: UInt8, on parent: UInt8) -> Bool {
        isUp(parent) && suit(c) == suit(parent) && rank(c) + 1 == rank(parent)
    }

    var isWon: Bool { completed == GameState.suitsToWin }

    /// Start of the movable same-suit run at the top of `column`.
    func runStart(_ column: Int) -> Int? {
        let cards = columns[column]
        guard var start = cards.indices.last, Position.isUp(cards[start]) else { return nil }
        while start > 0, Position.continues(cards[start], on: cards[start - 1]) { start -= 1 }
        return start
    }

    var canDeal: Bool {
        guard !stock.isEmpty else { return false }
        let tableau = columns.reduce(0) { $0 + $1.count }
        return !columns.contains { $0.isEmpty } || tableau < GameState.columnCount
    }

    mutating func flipTop(_ column: Int) -> Bool {
        guard let last = columns[column].indices.last, !Position.isUp(columns[column][last]) else { return false }
        columns[column][last] |= Position.faceUp
        return true
    }

    /// Removes a K..A same-suit run from the top of `column` if there is one.
    mutating func removeRun(_ column: Int) -> Bool {
        let cards = columns[column]
        guard cards.count >= 13 else { return false }
        let base = cards.count - 13
        guard Position.isUp(cards[base]), Position.rank(cards[base]) == 13 else { return false }
        for i in (base + 1)..<cards.count where !Position.continues(cards[i], on: cards[i - 1]) { return false }
        columns[column].removeLast(13)
        completed += 1
        _ = flipTop(column)
        return true
    }

    mutating func apply(_ move: Move) {
        switch move {
        case .move(let from, let index, let to):
            columns[to].append(contentsOf: columns[from][index...])
            columns[from].removeSubrange(index...)
            _ = flipTop(from)
            _ = removeRun(to)
        case .deal:
            for column in 0..<GameState.columnCount {
                guard let card = stock.popLast() else { break }
                columns[column].append(card | Position.faceUp)
            }
            for column in 0..<GameState.columnCount { _ = removeRun(column) }
        }
    }

    /// FNV-1a over the canonical layout (exact columns, stock size, suits done).
    var hash: UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        @inline(__always) func mix(_ byte: UInt8) {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        mix(UInt8(stock.count))
        for column in columns {
            for card in column { mix(card) }
            mix(0xFF)
        }
        return h
    }
}

enum Move: Hashable {
    case move(from: Int, index: Int, to: Int)
    case deal

    var action: Action {
        switch self {
        case .move(let from, let index, let to): return .move(from: from, index: index, to: to)
        case .deal: return .deal
        }
    }
}

// MARK: - Search

/// Best-first search: always expand the most promising open position (see `evaluate`). Positions
/// are stored packed (one byte per card, plus the stock size); the stock's order is fixed by the
/// deal, so only how many cards are left matters.
struct Search {
    let budget: SolverBudget
    let shouldStop: (() -> Bool)?
    var nodes = 0
    private let stock: [UInt8]
    private var visited = Set<UInt64>()
    private var packed: [[UInt8]] = []
    private var parent: [Int32] = []
    private var via: [Move?] = []
    private var depth: [Int16] = []
    private var open = Heap()
    private var root: Position

    init(root: Position, budget: SolverBudget, shouldStop: (() -> Bool)?) {
        self.budget = budget
        self.shouldStop = shouldStop
        self.root = root
        stock = root.stock
    }

    mutating func run() -> SolverResult {
        if root.isWon { return .solved([]) }
        add(root, parent: -1, move: nil, depth: 0)
        var truncated = false
        while let (_, index) = open.pop() {
            let position = unpack(packed[index])
            nodes += 1
            if nodes >= budget.maxNodes { return .gaveUp }
            if nodes & 1023 == 0, let shouldStop, shouldStop() { return .gaveUp }
            let d = Int(depth[index])
            if d >= budget.maxDepth {
                truncated = true
                continue
            }
            for move in Search.legalMoves(position) {
                var child = position
                child.apply(move)
                if child.isWon { return .solved(line(to: index) + [move.action]) }
                let key = child.hash
                guard visited.insert(key).inserted else { continue }
                add(child, parent: Int32(index), move: move, depth: d + 1)
            }
            packed[index] = [] // expanded: free its bytes
        }
        return truncated ? .gaveUp : .unsolvable
    }

    private mutating func add(_ p: Position, parent index: Int32, move: Move?, depth d: Int) {
        if index < 0 { visited.insert(p.hash) }
        packed.append(pack(p))
        parent.append(index)
        via.append(move)
        depth.append(Int16(min(d, Int(Int16.max))))
        open.push(Search.evaluate(p, budget.weights), packed.count - 1)
    }

    private func line(to index: Int) -> [Action] {
        var actions: [Action] = []
        var i = index
        while i >= 0, let move = via[i] {
            actions.append(move.action)
            i = Int(parent[i])
        }
        return actions.reversed()
    }

    private func pack(_ p: Position) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(p.stock.count), UInt8(p.completed)]
        bytes.reserveCapacity(12 + 104)
        for column in p.columns { bytes.append(UInt8(column.count)) }
        for column in p.columns { bytes.append(contentsOf: column) }
        return bytes
    }

    private func unpack(_ bytes: [UInt8]) -> Position {
        var p = root
        let stockCount = Int(bytes[0])
        p.stock = Array(stock.prefix(stockCount))
        p.completed = Int(bytes[1])
        var offset = 2 + GameState.columnCount
        for c in 0..<GameState.columnCount {
            let n = Int(bytes[2 + c])
            p.columns[c] = Array(bytes[offset..<(offset + n)])
            offset += n
        }
        return p
    }

    /// Higher is better: finished suits, long same-suit runs, few hidden cards, empty columns.
    static func evaluate(_ p: Position, _ w: SolverWeights) -> Int {
        var score = p.completed * w.completedSuit
        for column in p.columns {
            if column.isEmpty {
                score += w.emptyColumn
                continue
            }
            var hidden = 0
            for (i, card) in column.enumerated() {
                if !Position.isUp(card) {
                    hidden += 1
                    continue
                }
                guard i > 0 else { continue }
                let below = column[i - 1]
                if Position.continues(card, on: below) {
                    score += w.sameSuitLink
                } else if Position.isUp(below), Position.rank(below) == Position.rank(card) + 1 {
                    score += w.naturalLink
                } else if Position.isUp(below) {
                    score += w.brokenLink // a break inside the face-up part
                }
            }
            score += hidden * w.hiddenCard
            // Hidden cards under a short face-up pile are close to being revealed.
            if hidden > 0 { score += (column.count - hidden) * w.coverOverHidden }
        }
        // Dealt cards are needed eventually; each dealt card is worth a little.
        score += (50 - p.stock.count) * w.dealDone
        return score
    }

    /// Legal moves minus the pointless ones (order does not matter: the heap ranks the children).
    static func legalMoves(_ p: Position) -> [Move] {
        var moves: [Move] = []
        let firstEmpty = p.columns.indices.first { p.columns[$0].isEmpty }
        for from in p.columns.indices {
            guard let start = p.runStart(from) else { continue }
            let cards = p.columns[from]
            for index in start..<cards.count {
                let card = cards[index]
                let parent: UInt8? = index > 0 ? cards[index - 1] : nil
                let onNaturalParent =
                    parent.map { Position.isUp($0) && Position.rank($0) == Position.rank(card) + 1 } ?? false
                for to in p.columns.indices where to != from {
                    guard let target = p.columns[to].last, Position.isUp(target),
                        Position.rank(target) == Position.rank(card) + 1
                    else { continue }
                    let sameSuit = Position.suit(target) == Position.suit(card)
                    // Splitting a run, or moving between two equal parents, only pays off in suit.
                    if index > start || onNaturalParent, !sameSuit { continue }
                    moves.append(.move(from: from, index: index, to: to))
                }
                // Into an empty column: the first one only, whole runs only, never a whole column.
                if let to = firstEmpty, index > 0, index == start {
                    moves.append(.move(from: from, index: index, to: to))
                }
            }
        }
        if p.canDeal { moves.append(.deal) }
        return moves
    }
}

/// Max-heap of (priority, node); ties go to the newer node (deeper lines first).
struct Heap {
    private var items: [(Int, Int)] = []

    private func above(_ a: (Int, Int), _ b: (Int, Int)) -> Bool { a.0 != b.0 ? a.0 > b.0 : a.1 > b.1 }

    mutating func push(_ priority: Int, _ value: Int) {
        items.append((priority, value))
        var i = items.count - 1
        while i > 0 {
            let up = (i - 1) / 2
            guard above(items[i], items[up]) else { break }
            items.swapAt(i, up)
            i = up
        }
    }

    mutating func pop() -> (Int, Int)? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var best = i
                if l < items.count, above(items[l], items[best]) { best = l }
                if r < items.count, above(items[r], items[best]) { best = r }
                if best == i { break }
                items.swapAt(i, best)
                i = best
            }
        }
        return first
    }
}
