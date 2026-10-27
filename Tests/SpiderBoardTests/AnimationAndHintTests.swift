import SpiderCore
import XCTest

@testable import SpiderBoard

final class DealAnimationTests: XCTestCase {
    let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))

    func testDealtCardsWaitFaceDownOnTheirOldPileThenReleaseInOrder() throws {
        var game = SpiderGame(difficulty: .fourSuits, seed: 9)
        let dealsBefore = game.state.dealsRemaining
        let outcome = try game.perform(.deal)
        var anim = BoardAnimations()
        anim.beginDeal(outcome, dealsBefore: dealsBefore)
        XCTAssertEqual(anim.dealHold?.waitingIDs, outcome.dealtCardIDs)
        XCTAssertFalse(anim.isIdle)

        let pile = layout.stockFrames(dealsRemaining: dealsBefore).last!
        var byID = Dictionary(
            uniqueKeysWithValues: layout.placements(for: game.state, animations: anim).map { ($0.id, $0) })
        for id in outcome.dealtCardIDs {
            XCTAssertEqual(byID[id]!.frame, pile)
            XCTAssertFalse(byID[id]!.card.isFaceUp, "drawn as a back while waiting")
        }
        XCTAssertEqual(byID.count, 104)

        // Release column 1's card: it moves to its real spot, face up; the rest still wait.
        let first = outcome.dealtCardIDs[0]
        XCTAssertTrue(anim.releaseDealtCard(first))
        XCTAssertFalse(anim.releaseDealtCard(first), "only once")
        byID = Dictionary(
            uniqueKeysWithValues: layout.placements(for: game.state, animations: anim).map { ($0.id, $0) })
        XCTAssertEqual(byID[first]!.frame, layout.cardFrames(in: game.state)[0].last!)
        XCTAssertTrue(byID[first]!.card.isFaceUp)
        XCTAssertEqual(byID[outcome.dealtCardIDs[1]]!.frame, pile)
        // Next to fly is drawn on top of the waiting pile.
        XCTAssertGreaterThan(byID[outcome.dealtCardIDs[1]]!.zIndex, byID[outcome.dealtCardIDs[9]]!.zIndex)

        for id in outcome.dealtCardIDs.dropFirst() { anim.releaseDealtCard(id) }
        XCTAssertTrue(anim.isIdle)
        XCTAssertEqual(layout.placements(for: game.state, animations: anim), layout.placements(for: game.state))
    }

    func testCardsCompletedByTheDealFlyInsteadOfWaiting() throws {
        var t = Cards()
        var stock = (0..<10).map { _ in t.c(.five, .clubs, up: false) }
        stock[9] = t.c(.ace, .spades, up: false)
        let run = stride(from: 13, through: 2, by: -1).map { t.c(Rank(rawValue: $0)!, .spades) }
        var cols: [[Card]] = [[t.c(.four, .hearts, up: false)] + run]
        for _ in 1..<10 { cols.append([t.c(.king, .clubs)]) }
        var game = SpiderGame(state: GameState(difficulty: .fourSuits, seed: 0, columns: cols, stock: stock))
        let outcome = try game.perform(.deal)
        var anim = BoardAnimations()
        anim.beginDeal(outcome, dealsBefore: 1)
        anim.beginFlights(outcome.completedRuns, columns: game.state.columns)
        XCTAssertEqual(anim.dealHold?.waitingIDs.count, 9)
        XCTAssertFalse(anim.dealHold!.waitingIDs.contains(stock[9].id))
        XCTAssertEqual(anim.flying.count, 13)
    }
}

final class FlightTests: XCTestCase {
    let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 700))

    private func completeOneSuit() throws -> (SpiderGame, ActionOutcome, Card) {
        var t = Cards()
        let hidden = t.c(.three, .clubs, up: false)
        let run = stride(from: 13, through: 2, by: -1).map { t.c(Rank(rawValue: $0)!, .hearts) }
        let state = t.state([[hidden] + run, [t.c(.ace, .hearts)]])
        var game = SpiderGame(state: state)
        let outcome = try game.perform(.move(from: 1, index: 0, to: 0))
        return (game, outcome, hidden)
    }

    func testRunTakesOffFromWhereItWasAndLandsOnItsSlot() throws {
        let (game, outcome, hidden) = try completeOneSuit()
        var anim = BoardAnimations()
        anim.beginFlights(outcome.completedRuns, columns: game.state.columns)
        XCTAssertEqual(anim.flying.count, 13)
        XCTAssertEqual(anim.flyingSlots, [0])

        // Before take-off each card is exactly where the full column drew it.
        let fullColumn = game.state.columns[0] + outcome.completedRuns[0].cards
        let before = layout.cardFrames(column: 0, cards: fullColumn)
        for flight in anim.flying {
            XCTAssertEqual(layout.frame(of: flight), before[1 + flight.runIndex])
        }
        XCTAssertEqual(game.state.columns[0].map(\.id), [hidden.id])

        // Foundation king is hidden while its run is in the air.
        XCTAssertTrue(layout.foundationPlacements(for: game.state, animations: anim).isEmpty)
        XCTAssertEqual(layout.placements(for: game.state, animations: anim).count, 1 + 13, "hidden card + 13 in flight")

        let order = anim.takeOffOrder(slot: 0)
        XCTAssertEqual(order.first, outcome.completedRuns[0].cards.last!.id, "Ace leaves first")
        XCTAssertEqual(order.last, outcome.completedRuns[0].cards.first!.id, "King last")

        for id in order { anim.land(id) }
        let slot = layout.foundationFrames(count: 1)[0]
        XCTAssertTrue(anim.flying.allSatisfy { layout.frame(of: $0) == slot })
        anim.finishSlot(0)
        XCTAssertTrue(anim.isIdle)
        let kings = layout.foundationPlacements(for: game.state, animations: anim)
        XCTAssertEqual(kings.map(\.card.rank), [.king])
        XCTAssertEqual(kings.map(\.card.suit), [.hearts])
        XCTAssertEqual(kings.first?.frame, slot)
    }

    func testFlyingCardsDrawAboveEverything() throws {
        let (game, outcome, _) = try completeOneSuit()
        var anim = BoardAnimations()
        anim.beginFlights(outcome.completedRuns, columns: game.state.columns)
        let placements = layout.placements(
            for: game.state, drag: PointerController.Drag(from: 1, index: 0, translation: .zero),
            animations: anim)
        let flyingIDs = Set(outcome.completedRuns[0].cards.map(\.id))
        let minFlying = placements.filter { flyingIDs.contains($0.id) }.map(\.zIndex).min()!
        let maxOther = placements.filter { !flyingIDs.contains($0.id) }.map(\.zIndex).max() ?? 0
        XCTAssertGreaterThan(minFlying, maxOther)
        XCTAssertEqual(Set(placements.map(\.id)).count, placements.count, "ids unique")
    }
}

final class HintCyclerTests: XCTestCase {
    func testCyclesThroughAllHintsAndWraps() {
        var k = Cards()
        let state = k.state([
            [k.c(.two, up: false), k.c(.five, .hearts)],
            [k.c(.six, .clubs)],
            [k.c(.six, .hearts)],
            [k.c(.three, up: false), k.c(.four, .spades)],
            [k.c(.king, .diamonds)],
        ])
        let all = state.hints()
        XCTAssertGreaterThanOrEqual(all.count, 3)
        var cycler = HintCycler()
        var seen: [HintStep] = []
        for _ in 0..<(all.count * 2) { seen.append(cycler.next(for: state)) }
        XCTAssertEqual(seen, (all + all).map { HintStep.move($0) })
    }

    func testRestartsWhenPositionChanges() throws {
        var game = SpiderGame(difficulty: .twoSuits, seed: 30)
        var cycler = HintCycler()
        _ = cycler.next(for: game.state)
        _ = cycler.next(for: game.state)
        try game.perform(.deal)
        let first = game.state.hints().first
        XCTAssertEqual(cycler.next(for: game.state), first.map { HintStep.move($0) } ?? .deal)
    }

    func testDealThenNoMoves() {
        var k = Cards()
        let blocked = (0..<10).map { i in [k.c(i % 2 == 0 ? .two : .nine)] }
        var cycler = HintCycler()
        XCTAssertEqual(cycler.next(for: k.state(blocked, stock: 10)), .deal)
        XCTAssertEqual(cycler.next(for: k.state(blocked)), .noMoves)
    }

    func testHighlightSequenceAndIDs() {
        var k = Cards()
        let state = k.state([[k.c(.two, up: false), k.c(.nine), k.c(.eight)], [k.c(.ten, .hearts)], []], stock: 20)
        let hint = Hint(from: 0, index: 1, to: 1, kind: .otherSuit)
        let seq = HintHighlight.sequence(for: .move(hint))
        XCTAssertEqual(seq, [HintHighlight.source(column: 0, index: 1), HintHighlight.target(column: 1)])
        XCTAssertEqual(seq[0].cardIDs(in: state), Set(state.columns[0][1...].map(\.id)))
        XCTAssertEqual(seq[1].cardIDs(in: state), [state.columns[1][0].id])
        XCTAssertEqual(HintHighlight.stock.cardIDs(in: state), Set(state.stock.suffix(10).map(\.id)))
        XCTAssertEqual(HintHighlight.target(column: 2).highlightedSlot(in: state), 2)
        XCTAssertNil(HintHighlight.target(column: 1).highlightedSlot(in: state))
        XCTAssertTrue(HintHighlight.sequence(for: .noMoves).isEmpty)
        XCTAssertTrue(HintHighlight.source(column: 9, index: 5).cardIDs(in: state).isEmpty, "stale index is safe")

        let layout = BoardLayout(boardSize: BoardSize(width: 800, height: 600))
        let lit = layout.placements(for: state, highlightedIDs: seq[0].cardIDs(in: state)).filter { $0.isHighlighted }
        XCTAssertEqual(Set(lit.map { $0.card.id }), seq[0].cardIDs(in: state))
    }

    func testScoreBoxClickAsksForHint() {
        var k = Cards()
        let layout = BoardLayout(boardSize: BoardSize(width: 800, height: 600))
        let state = k.state([[k.c(.five)]])
        var p = PointerController()
        XCTAssertEqual(
            p.pointerEnded(
                start: layout.scoreBoxFrame.center, translation: .zero, time: 0,
                state: state, layout: layout), .hint)
    }
}
