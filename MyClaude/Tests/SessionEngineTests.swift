import XCTest
@testable import MyClaude

final class SessionEngineTests: XCTestCase {

    var engine: SessionEngine!

    override func setUp() {
        super.setUp()
        engine = SessionEngine(sessionDuration: 5 * 3600)
    }

    // MARK: - Rolling window basics

    func testNoEventsIsInactive() {
        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(engine.remainingTime, 0)
        XCTAssertEqual(engine.currentAlertLevel, .safe)
    }

    func testRecentEventMakesActive() {
        let event = makeEvent(minutesAgo: 10)
        engine.processEvents([event])

        XCTAssertTrue(engine.isActive)
    }

    func testRemainingTimeIsCorrect() {
        // Event from 1 hour ago → oldest event expires in 4 hours
        let event = makeEvent(minutesAgo: 60)
        engine.processEvents([event])

        let remaining = engine.remainingTime
        // Should be approximately 4 hours (240 min)
        XCTAssertTrue(remaining > 235 * 60 && remaining < 245 * 60,
                       "Expected ~240min, got \(remaining / 60)min")
    }

    func testMultipleEventsUsesOldest() {
        // Oldest event is 2 hours ago → resets in ~3 hours
        let events = [
            makeEvent(minutesAgo: 120),
            makeEvent(minutesAgo: 60),
            makeEvent(minutesAgo: 10),
        ]
        engine.processEvents(events)

        let remaining = engine.remainingTime
        // Should be approximately 3 hours (180 min)
        XCTAssertTrue(remaining > 175 * 60 && remaining < 185 * 60,
                       "Expected ~180min, got \(remaining / 60)min")
    }

    // MARK: - Window expiration

    func testOldEventsGetPruned() {
        // Event from 6 hours ago — outside the 5h window
        let oldEvent = makeEvent(minutesAgo: 360)
        let recentEvent = makeEvent(minutesAgo: 30)

        engine.processEvents([oldEvent, recentEvent])
        engine.tick() // triggers pruning

        XCTAssertEqual(engine.currentSession.eventCount, 1)
    }

    func testAllEventsExpiredMeansInactive() {
        let oldEvent = makeEvent(minutesAgo: 400) // well past 5 hours
        engine.processEvents([oldEvent])
        engine.tick()

        XCTAssertFalse(engine.isActive)
    }

    // MARK: - Progress

    func testProgressAtHalfway() {
        // Event from 2.5 hours ago = 50% of window filled
        let event = makeEvent(minutesAgo: 150)
        engine.processEvents([event])

        let progress = engine.sessionProgress
        XCTAssertTrue(progress > 0.45 && progress < 0.55,
                       "Expected ~0.50, got \(progress)")
    }

    func testProgressNearEnd() {
        // Event from 4.5 hours ago = 90%
        let event = makeEvent(minutesAgo: 270)
        engine.processEvents([event])

        let progress = engine.sessionProgress
        XCTAssertTrue(progress > 0.85 && progress < 0.95,
                       "Expected ~0.90, got \(progress)")
    }

    // MARK: - Alert levels

    func testSafeAlertLevel() {
        let event = makeEvent(minutesAgo: 30) // 4h30m remaining
        engine.processEvents([event])
        XCTAssertEqual(engine.currentAlertLevel, .safe)
    }

    func testWarningAlertLevel() {
        let event = makeEvent(minutesAgo: 245) // ~55min remaining
        engine.processEvents([event])
        XCTAssertEqual(engine.currentAlertLevel, .warning)
    }

    func testCriticalAlertLevel() {
        let event = makeEvent(minutesAgo: 280) // ~20min remaining
        engine.processEvents([event])
        XCTAssertEqual(engine.currentAlertLevel, .critical)
    }

    // MARK: - Token counting

    func testWindowTokensOnlyCountRecent() {
        let oldEvent = makeEvent(minutesAgo: 400, tokens: 5000) // outside window
        let recentEvent = makeEvent(minutesAgo: 30, tokens: 1000)

        engine.processEvents([oldEvent, recentEvent])
        engine.tick()

        XCTAssertEqual(engine.currentSession.totalTokens, 1000)
    }

    // MARK: - Helpers

    private func makeEvent(minutesAgo: Int, tokens: Int? = 100) -> UsageEvent {
        UsageEvent(
            timestamp: Date().addingTimeInterval(-Double(minutesAgo) * 60),
            tokens: tokens,
            type: .request
        )
    }
}
