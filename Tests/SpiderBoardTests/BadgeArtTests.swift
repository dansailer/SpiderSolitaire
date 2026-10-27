import SpiderCore
import XCTest

@testable import SpiderBoard

final class BadgeArtTests: XCTestCase {
    func testEveryEmblemDrawsInsideTheBadge() {
        for emblem in AchievementEmblem.allCases {
            for unlocked in [false, true] {
                let scene = BadgeArt.scene(emblem, unlocked: unlocked, size: 64)
                XCTAssertEqual(scene.size, BoardSize(width: 64, height: 64))
                XCTAssertGreaterThan(scene.items.count, 4, "\(emblem) has an emblem")
                for item in scene.items {
                    let b = item.path.bounds
                    XCTAssertGreaterThanOrEqual(b.minX, 0, "\(emblem)")
                    XCTAssertGreaterThanOrEqual(b.minY, 0, "\(emblem)")
                    XCTAssertLessThanOrEqual(b.maxX, 64, "\(emblem)")
                    XCTAssertLessThanOrEqual(b.maxY, 64, "\(emblem)")
                }
            }
        }
    }

    func testEmblemsAreDistinctAndLockedIsGrey() {
        let emblems = AchievementEmblem.allCases.map { BadgeArt.emblemItems($0, ink: RGBA(0, 0, 0)) }
        XCTAssertEqual(Set(emblems).count, emblems.count)

        func colours(_ scene: VectorScene) -> [RGBA] {
            scene.items.flatMap { item -> [RGBA] in
                var out: [RGBA] = []
                switch item.fill {
                case .solid(let c)?: out.append(c)
                case .linear(_, _, let a, let b)?, .radial(_, _, let a, let b)?: out += [a, b]
                case nil: break
                }
                if let s = item.stroke { out.append(s.color) }
                return out
            }
        }
        for emblem in AchievementEmblem.allCases {
            let locked = colours(BadgeArt.scene(emblem, unlocked: false, size: 64))
            XCTAssertTrue(
                locked.allSatisfy { abs($0.r - $0.g) < 0.001 && abs($0.g - $0.b) < 0.001 }, "\(emblem) locked is grey")
            let gold = colours(BadgeArt.scene(emblem, unlocked: true, size: 64))
            XCTAssertTrue(gold.contains { $0.r - $0.b > 0.3 }, "\(emblem) unlocked is gold")
        }
    }

    func testBadgeSVGIsSelfContained() {
        let svg = BadgeArt.scene(.crown, unlocked: true, size: 100).svg()
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertFalse(svg.contains("<image"))
    }

    func testPlayClockText() {
        XCTAssertEqual(PlayClock.text(0), "0:00")
        XCTAssertEqual(PlayClock.text(65), "1:05")
        XCTAssertEqual(PlayClock.text(599), "9:59")
        XCTAssertEqual(PlayClock.text(3_725), "1:02:05")
        XCTAssertEqual(PlayClock.text(-3), "0:00")
    }

    func testAchievementHasItsOwnSound() {
        XCTAssertEqual(SoundCue.achievement.systemSoundName, "Purr")
        XCTAssertEqual(Set(SoundCue.allCases.map(\.systemSoundName)).count, SoundCue.allCases.count)
    }
}
