// Developer tool, not part of the app.
//   swift run -c release SpiderTools bench <suits 1|2|4> <count> [maxNodes]
//   swift run -c release SpiderTools seeds <suits> <wanted> [maxNodes]   (Swift array literal)
//   swift run -c release SpiderTools find <suits> <runs>      (time to find one winnable seed, like the app)
//   swift run -c release SpiderTools bundled <suits> 0         (re-check WinnableDeals.bundled)
import SpiderCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

func getenvString(_ name: String) -> String? {
    guard let value = getenv(name) else { return nil }
    return String(cString: value)
}

func difficulty(_ text: String) -> Difficulty {
    guard let n = Int(text), let d = Difficulty(rawValue: n) else { fatalError("suits must be 1, 2 or 4") }
    return d
}

func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

func fmt(_ x: Double) -> String {
    let milli = Int((x * 1000).rounded())
    let frac = String(milli % 1000)
    return "\(milli / 1000)." + String(repeating: "0", count: 3 - frac.count) + frac
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else { fatalError("usage: SpiderTools bench|seeds <suits> <count> [maxNodes]") }
let diff = difficulty(args[1])
let count = Int(args[2]) ?? 10
// Without W= and maxNodes, bench and seeds use the app's attempts (SolverBudget.attempts).
let custom = getenvString("W") != nil || args.count > 3
var budget = SolverBudget(maxNodes: 300_000, weights: getenvString("TIDY") != nil ? .tidy : .balanced)
if args.count > 3, let nodes = Int(args[3]) { budget.maxNodes = nodes }
// Tuning: W=key=value,key=value (e.g. W=hidden=-30,deal=5); TIDY=1 starts from .tidy
if let spec = getenvString("W") {
    for pair in spec.split(separator: ",") {
        let kv = pair.split(separator: "=")
        guard kv.count == 2, let v = Int(kv[1]) else { continue }
        switch kv[0] {
        case "suit": budget.weights.completedSuit = v
        case "empty": budget.weights.emptyColumn = v
        case "same": budget.weights.sameSuitLink = v
        case "natural": budget.weights.naturalLink = v
        case "broken": budget.weights.brokenLink = v
        case "hidden": budget.weights.hiddenCard = v
        case "cover": budget.weights.coverOverHidden = v
        case "deal": budget.weights.dealDone = v
        default: fatalError("unknown weight \(kv[0])")
        }
    }
}
let clock = ContinuousClock()

/// One seed: the custom budget, or the app's attempts.
func attempt(_ seed: UInt64) -> (SolverResult, Int) {
    if custom {
        let report = Solver.solve(difficulty: diff, seed: seed, budget: budget)
        return (report.result, report.nodes)
    }
    var nodes = 0
    for b in SolverBudget.attempts(for: diff) {
        let report = Solver.solve(difficulty: diff, seed: seed, budget: b)
        nodes += report.nodes
        if case .gaveUp = report.result { continue }
        return (report.result, nodes)
    }
    return (.gaveUp, nodes)
}

extension SolverResult {
    var label: String {
        switch self {
        case .solved(let a): return "solved(\(a.count))"
        case .unsolvable: return "unsolvable"
        case .gaveUp: return "gave up"
        }
    }
}

switch args[0] {
case "bench":
    var solved = 0, unsolvable = 0, gaveUp = 0
    var totalTime = 0.0, solvedTime = 0.0, maxTime = 0.0, totalNodes = 0, lengths: [Int] = []
    for i in 0..<count {
        let seed = UInt64(i) &* 0x9E37_79B9_7F4A_7C15 &+ 12345
        let start = clock.now
        let (result, nodes) = attempt(seed)
        let t = seconds(clock.now - start)
        totalTime += t; maxTime = max(maxTime, t); totalNodes += nodes
        if getenvString("VERBOSE") != nil { print("  deal \(i) seed \(seed): \(result.label) nodes \(nodes) " + fmt(t) + " s") }
        switch result {
        case .solved(let actions):
            precondition(Solver.verify(difficulty: diff, seed: seed, actions: actions), "bad solution for \(seed)")
            solved += 1; solvedTime += t; lengths.append(actions.count)
        case .unsolvable: unsolvable += 1
        case .gaveUp: gaveUp += 1
        }
    }
    let avgLen = lengths.isEmpty ? 0 : lengths.reduce(0, +) / lengths.count
    print("suits=\(diff.rawValue) deals=\(count) budget=\(custom ? String(budget.maxNodes) : "app attempts"): solved \(solved) (\(solved * 100 / count)%), unsolvable \(unsolvable), gave up \(gaveUp)")
    let avgTime: Double = totalTime / Double(count)
    let avgSolved: Double = solved > 0 ? solvedTime / Double(solved) : 0
    let line: String = "  avg time " + fmt(avgTime) + " s (solved only " + fmt(avgSolved) + " s), max " + fmt(maxTime)
        + " s, avg nodes \(totalNodes / count), avg solution \(avgLen) moves (min \(lengths.min() ?? 0), max \(lengths.max() ?? 0))"
    print(line)
case "find":
    // Simulates the app: time to find one winnable seed, from `count` different random streams.
    var times: [Double] = [], tries: [Int] = []
    for i in 0..<count {
        var rng = SeededGenerator(seed: 0xF17D &+ UInt64(i))
        let start = clock.now
        var n = 0
        while true {
            n += 1
            if Solver.winningLine(difficulty: diff, seed: rng.next()) != nil { break }
        }
        times.append(seconds(clock.now - start)); tries.append(n)
    }
    let sorted = times.sorted()
    print("suits=\(diff.rawValue) runs=\(count): avg " + fmt(times.reduce(0, +) / Double(count)) + " s, median "
        + fmt(sorted[count / 2]) + " s, max " + fmt(sorted.last ?? 0) + " s, within 5 s \(times.filter { $0 <= 5 }.count)/\(count), avg seeds tried \(tries.reduce(0, +) / count)")
case "bundled":
    // Nodes each bundled seed needs with the app's attempts (count is ignored).
    for seed in WinnableDeals.bundled[diff] ?? [] {
        let (result, nodes) = attempt(seed)
        print("0x" + String(seed, radix: 16, uppercase: true) + " \(result.label) \(nodes)")
    }
case "seeds":
    var found: [UInt64] = []
    var seed: UInt64 = 0xC0FFEE &+ UInt64(diff.rawValue)
    var rng = SeededGenerator(seed: seed)
    while found.count < count {
        seed = rng.next()
        if case .solved(let actions) = attempt(seed).0,
           Solver.verify(difficulty: diff, seed: seed, actions: actions) {
            found.append(seed)
        }
    }
    print(found.map { "0x" + String($0, radix: 16, uppercase: true) }.joined(separator: ", "))
default:
    fatalError("unknown command \(args[0])")
}
