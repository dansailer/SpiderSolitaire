/// Winnable deals: seeds proved winnable by the solver, from three sources in order: seeds found
/// earlier in the background (`WinnableSeedCache`, stored as winnable.json), a fresh search, and
/// the bundled seeds below. All bundled seeds were generated and verified on the box with
/// `SpiderTools seeds` (a test re-solves some of them).
public enum WinnableDeals {
    public static let bundled: [Difficulty: [UInt64]] = [
        .oneSuit: [
            0x2EBBC4EFF8587641, 0x5E003B0244D36B45, 0x191E0AF7A2221814, 0x2146E79F2AD00128, 0xC6DAFE42F42F1B9A,
            0xB031B9275173928F, 0x3613587062BAAB8E, 0xF9AC4C42EB94C353, 0x17757F4C37248AE9, 0xFDB6A51F6276E327,
            0x6C75AC02A2E6C34B, 0x7471EED976178455, 0xB03C3B4EC6F12846, 0x4CF5379DAF387BE1, 0x15283716A20603E9,
            0xA81C470F62A16779, 0xA40BB4C31664D9EF, 0xD86C2B0F476DD11A, 0xF0DAB80E3F026A0E, 0xF2BC70DBA4839C8F,
            0x39CDFAD77A4DC831, 0xDD59B73D09E01A7E, 0xDFB6C5A2ACAC31B8, 0x9DDDBBD7F9D04EC8,
        ],
        .twoSuits: [
            0xA09BA6DFB5126A4E, 0x646C0D2428B6191D, 0x795EBEEBC365AA19, 0x9154741E269861E0, 0x0264695631E08819,
            0x86C2DA733C28161F, 0xC6DAD6CF902F144F, 0xF47FE705799F4B9A, 0x4FD44CAA99521E5B, 0xC3B207B13C107DA5,
            0x3DBD3222C2D2705B, 0xF7650E8F16688724, 0x0CBE14A9497CF2DF, 0x5F50C6F70F5EEE42, 0xDCF11AAF3962DE91,
            0x5DDDD6ADFDBCA0EC, 0xDC04FFB8EFD29DF6, 0x9F97A7CE5A45CA0A, 0x13CB961A41177942, 0xCEBB1F1F6C0D7F4D,
            0x4796C7E899C6A618, 0x41DE564D776B890C, 0xA8D63A190F4DE3B8, 0x2E3DBE90181EED08,
        ],
        .fourSuits: [
            0x2808673D3B82CB3C, 0x0BBFD1B61B3E1C70, 0xE1FAB38E70C4E43D, 0x763DA038237BB817, 0x32412BC93F804E62,
            0xA31B52DCCBBC51F3, 0xEF4A50C661A8FB6B, 0x7508B238EC0F5E2F, 0xB37E8C7015DB24D8, 0xE7D467F0B31C3407,
            0xD04120D1C4079E64, 0x518D9A2E28553DCC, 0xE63375E2A3048768, 0x5EF039FFA5103611, 0x132C4F94C84172CA,
            0x9951B58E4D8A0570, 0x912697D140DB2954, 0xB6B3655560D54411, 0x2ED4FD81C5DF810F, 0x549481B7B720DAD0,
            0xCD451F0879C42927, 0x99100FB371C5BE59, 0xD7B7E82F59A1CE7F, 0x6E0DCD0E47E9474C,
        ],
    ]

    /// How long the app searches before falling back (seconds).
    public static let searchSeconds: Double = 5
    /// Seeds the background search keeps ready per difficulty.
    public static let cacheTarget = 3

    /// Tries seeds from `nextSeed` until one is proved winnable. Nil when `shouldStop` says stop
    /// (deadline or cancel) first.
    public static func search(
        difficulty: Difficulty, nextSeed: () -> UInt64,
        shouldStop: @escaping () -> Bool
    ) -> UInt64? {
        while !shouldStop() {
            let seed = nextSeed()
            if Solver.winningLine(difficulty: difficulty, seed: seed, shouldStop: shouldStop) != nil { return seed }
        }
        return nil
    }
}

/// Seeds found ahead of time, plus how far through the bundled list each difficulty is.
/// Seeds are stored as hex strings (JSON numbers above 2^53 are not safe everywhere).
public struct WinnableSeedCache: Codable, Sendable, Hashable {
    private var ready: [String: [String]] = [:]
    private var bundledUsed: [String: Int] = [:]

    public init() {}

    private static func key(_ d: Difficulty) -> String { String(d.rawValue) }

    public func count(_ difficulty: Difficulty) -> Int { ready[Self.key(difficulty)]?.count ?? 0 }

    public mutating func add(_ seed: UInt64, for difficulty: Difficulty) {
        let hex = String(seed, radix: 16)
        guard !(ready[Self.key(difficulty)] ?? []).contains(hex) else { return }
        ready[Self.key(difficulty), default: []].append(hex)
    }

    /// Takes the oldest ready seed.
    public mutating func takeReady(_ difficulty: Difficulty) -> UInt64? {
        let k = Self.key(difficulty)
        while var list = ready[k], !list.isEmpty {
            let hex = list.removeFirst()
            ready[k] = list
            if let seed = UInt64(hex, radix: 16) { return seed }
        }
        return nil
    }

    /// The next bundled seed (cycles once all have been used).
    public mutating func takeBundled(_ difficulty: Difficulty) -> UInt64? {
        guard let list = WinnableDeals.bundled[difficulty], !list.isEmpty else { return nil }
        let k = Self.key(difficulty)
        let i = bundledUsed[k] ?? 0
        bundledUsed[k] = i + 1
        return list[i % list.count]
    }
}
