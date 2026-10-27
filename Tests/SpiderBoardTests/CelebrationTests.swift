import XCTest
import SpiderCore
@testable import SpiderBoard

final class CelebrationTests: XCTestCase {
    let suits: [Suit] = [.spades, .hearts, .spades, .hearts, .spades, .hearts, .spades, .hearts]

    private func celebration(_ w: Double = 900, _ h: Double = 650, seed: UInt64 = 4) -> WinCelebration {
        WinCelebration(layout: BoardLayout(boardSize: BoardSize(width: w, height: h)), suits: suits, seed: seed)
    }

    func testDeterministicPerSeed() {
        XCTAssertEqual(celebration().sprites(at: 2.5), celebration().sprites(at: 2.5))
        XCTAssertNotEqual(celebration(seed: 1).sprites(at: 2.5), celebration(seed: 2).sprites(at: 2.5))
    }

    func testCardsUseCompletedSuitsAndNegativeIDs() {
        let c = celebration()
        XCTAssertFalse(c.cards.isEmpty)
        XCTAssertTrue(c.cards.allSatisfy { $0.id < 0 && $0.isFaceUp && suits.contains($0.suit) })
        XCTAssertEqual(Set(c.cards.map(\.id)).count, c.cards.count)
        XCTAssertEqual(c.cards.first?.rank, .king)
    }

    func testCardsNeverFallThroughTheFloorAndBouncesShrink() {
        let c = celebration()
        for launch in c.launches.prefix(6) {
            var peaks: [Double] = []
            var lastY = launch.origin.y
            var rising = false
            var tau = 0.0
            while tau < 4 {
                let p = c.position(of: launch, tau: tau)!
                XCTAssertLessThanOrEqual(p.y, c.floorY + 1e-6)
                if p.y < lastY { rising = true } else if rising { peaks.append(lastY); rising = false }
                lastY = p.y
                tau += 0.004
            }
            // Peaks after the first bounce get lower (y grows downwards, so peak y increases).
            let afterFirst = Array(peaks.dropFirst())
            XCTAssertGreaterThanOrEqual(afterFirst.count, 2)
            for (a, b) in zip(afterFirst, afterFirst.dropFirst()) { XCTAssertGreaterThan(b, a - 1e-6) }
        }
    }

    func testEverythingIsGoneByTheNominalDurationAtAnySize() {
        for (w, h) in [(640.0, 480.0), (900.0, 650.0), (1800.0, 1100.0), (3000.0, 1900.0)] {
            for seed in UInt64(0)..<5 {
                let c = celebration(w, h, seed: seed)
                XCTAssertTrue(c.sprites(at: WinCelebration.nominalDuration).isEmpty, "\(w)x\(h) seed \(seed)")
                XCTAssertFalse(c.sprites(at: 1.5).isEmpty)
            }
        }
    }

    func testSpritesAreSaneAndTrailsAreFainter() {
        let c = celebration()
        let sprites = c.sprites(at: 3)
        XCTAssertTrue(sprites.allSatisfy { (0...1).contains($0.alpha) })
        let cards = sprites.filter { if case .card = $0.kind { return true } else { return false } }
        let heads = cards.filter { $0.alpha == 1 }
        let trails = cards.filter { $0.alpha < 1 }
        XCTAssertFalse(heads.isEmpty)
        XCTAssertFalse(trails.isEmpty)
        XCTAssertTrue(trails.allSatisfy { $0.alpha <= 0.55 })
        let sparks = sprites.compactMap { sprite -> Int? in
            if case .spark(let colour) = sprite.kind { return colour } else { return nil }
        }
        XCTAssertFalse(sparks.isEmpty)
        XCTAssertTrue(sparks.allSatisfy { (0..<WinCelebration.paletteSize).contains($0) })
        XCTAssertTrue(c.sprites(at: -1).isEmpty)
    }

    func testCardsStartAtTheFoundation() {
        let layout = BoardLayout(boardSize: BoardSize(width: 900, height: 650))
        let c = WinCelebration(layout: layout, suits: suits, seed: 9)
        let first = c.launches[0]
        XCTAssertEqual(first.origin, layout.foundationFrames(count: suits.count)[0].center)
        XCTAssertEqual(c.position(of: first, tau: 0), first.origin)
        XCTAssertNil(c.position(of: first, tau: -0.1))
    }
}

final class SoundTests: XCTestCase {
    func testSoundCuesUseBuiltInMacSoundsOnly() {
        for cue in SoundCue.allCases {
            XCTAssertTrue(SoundCue.macOSSystemSounds.contains(cue.systemSoundName), "\(cue)")
        }
    }
}
