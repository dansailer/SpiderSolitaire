import SpiderCore
import XCTest

@testable import SpiderBoard

final class CelebrationTests: XCTestCase {
    let suits: [Suit] = [.spades, .hearts, .spades, .hearts, .spades, .hearts, .spades, .hearts]
    let sizes: [(Double, Double)] = [(640, 480), (900, 650), (1800, 1100), (3000, 1900)]

    private func layout(_ w: Double = 900, _ h: Double = 650) -> BoardLayout {
        BoardLayout(boardSize: BoardSize(width: w, height: h))
    }

    private func celebration(seed: UInt64 = 4) -> WinCelebration {
        WinCelebration(suits: suits, seed: seed)
    }

    func testDeterministicPerSeed() {
        XCTAssertEqual(celebration().flights, celebration().flights)
        XCTAssertEqual(celebration().sparks(at: 4, layout: layout()), celebration().sparks(at: 4, layout: layout()))
        XCTAssertEqual(celebration().endTime, celebration().endTime)
        XCTAssertNotEqual(celebration(seed: 1).flights, celebration(seed: 2).flights)
    }

    func testEveryCardOfEveryCompletedSuitFlies() {
        let c = celebration()
        XCTAssertEqual(c.flights.count, suits.count * 13)
        XCTAssertTrue(c.cards.allSatisfy { $0.id < 0 && $0.isFaceUp })
        XCTAssertEqual(Set(c.cards.map(\.id)).count, c.cards.count)
        for (pile, suit) in suits.enumerated() {
            let ranks = c.flights.filter { $0.pile == pile }.map(\.card)
            XCTAssertTrue(ranks.allSatisfy { $0.suit == suit })
            XCTAssertEqual(ranks.map(\.rank), Rank.allCases.reversed(), "pile \(pile): king first, ace last")
        }
    }

    func testPilesEmptyOneByOneFromTheTopPile() {
        let c = celebration()
        // The rightmost pile (drawn on top) goes first, and each pile empties before the next starts.
        XCTAssertEqual(c.flights.map(\.pile), suits.indices.reversed().flatMap { Array(repeating: $0, count: 13) })
        XCTAssertTrue(zip(c.flights, c.flights.dropFirst()).allSatisfy { $0.start < $1.start })
        XCTAssertEqual(c.pileTops(at: -1).map(\.pile), Array(suits.indices))
        XCTAssertTrue(c.pileTops(at: -1).allSatisfy { $0.card.rank == .king })
        let afterFirstKing = c.pileTops(at: c.flights[0].start)
        XCTAssertEqual(afterFirstKing.last?.card.rank, .queen)
        let lastPileStart = c.flights.first { $0.pile == 0 }!.start
        XCTAssertEqual(c.pileTops(at: lastPileStart - 0.001).map(\.pile), [0])
        XCTAssertTrue(c.pileTops(at: c.flights.last!.start).isEmpty)
    }

    func testCardsStartAtTheirPileAndNeverFallThroughTheFloor() {
        let c = celebration()
        for (w, h) in sizes {
            let l = layout(w, h)
            let floorY = h - l.cardSize.height / 2
            let slots = l.foundationFrames(count: suits.count)
            for flight in c.flights.prefix(20) {
                XCTAssertEqual(c.position(of: flight, tau: 0, layout: l), slots[flight.pile].center)
                var tau = 0.0
                var highest = Double.infinity
                while let p = c.position(of: flight, tau: tau, layout: l) {
                    XCTAssertLessThanOrEqual(p.y, floorY + 1e-6)
                    XCTAssertGreaterThanOrEqual(p.y, l.cardSize.height / 2 - 1e-6, "never above the top edge")
                    highest = min(highest, p.y)
                    tau += 0.01
                }
                XCTAssertLessThan(highest, h * 0.75, "\(w)x\(h): every card jumps well up")
            }
        }
    }

    func testCardsGoBothWaysAndLeaveTheBoardOnTime() {
        let c = celebration()
        let directions = Set(c.flights.map(\.direction))
        XCTAssertEqual(directions, [-1, 1])
        for (w, h) in sizes {
            let l = layout(w, h)
            for flight in c.flights {
                let last = c.position(of: flight, tau: flight.duration - 1e-6, layout: l)!
                XCTAssertTrue(
                    last.x + l.cardSize.width / 2 < 1 || last.x - l.cardSize.width / 2 > w - 1,
                    "\(w)x\(h): off the board at the end of its flight")
                XCTAssertNil(c.position(of: flight, tau: flight.duration, layout: l))
            }
        }
    }

    func testFireworksFollowTheCascadeAndEndInAFinale() {
        let c = celebration()
        let times = c.burstTimes
        XCTAssertGreaterThanOrEqual(times.min()!, 1.9, "cards only at first")
        XCTAssertTrue(c.sparks(at: 1.5, layout: layout()).isEmpty)
        let finale = times.suffix(WinCelebration.finaleBursts)
        XCTAssertLessThan(finale.last! - finale.first!, 0.5, "the finale's bursts go off together")
        let beforeFinale = times.dropLast(WinCelebration.finaleBursts).max()!
        XCTAssertGreaterThan(finale.first! - beforeFinale, 0.5, "a pause before the finale")
        let sparks = c.sparks(at: 5, layout: layout())
        XCTAssertFalse(sparks.isEmpty)
        XCTAssertTrue(sparks.allSatisfy { (0...1).contains($0.alpha) })
        XCTAssertTrue(sparks.allSatisfy { (0..<WinCelebration.paletteSize).contains($0.colorIndex) })
    }

    func testTheShowEndsWhenEverythingIsGone() {
        for seed in UInt64(0)..<8 {
            let c = celebration(seed: seed)
            XCTAssertGreaterThan(c.endTime, 10, "seed \(seed)")
            XCTAssertLessThan(c.endTime, 14, "seed \(seed)")
            XCTAssertEqual(c.endTime, max(c.flights.map(\.end).max()!, c.burstTimes.max()! + 1.4), accuracy: 1e-9)
            for (w, h) in sizes {
                let l = layout(w, h)
                XCTAssertTrue(c.cardsInFlight(at: c.endTime, layout: l).isEmpty, "\(w)x\(h) seed \(seed)")
                XCTAssertTrue(c.sparks(at: c.endTime, layout: l).isEmpty, "\(w)x\(h) seed \(seed)")
                XCTAssertFalse(c.cardsInFlight(at: 1.5, layout: l).isEmpty)
            }
            XCTAssertTrue(c.pileTops(at: c.endTime).isEmpty)
        }
    }

    func testFewerSuitsStillCelebrate() {
        let c = WinCelebration(suits: [], seed: 3)
        XCTAssertEqual(c.flights.count, 13)
        XCTAssertGreaterThan(c.endTime, 3)
        XCTAssertTrue(c.sparks(at: c.endTime, layout: layout()).isEmpty)
    }
}
