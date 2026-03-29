import XCTest
@testable import MyClaude

final class SessionEngineTests: XCTestCase {

    var engine: SessionEngine!

    override func setUp() {
        super.setUp()
        engine = SessionEngine(sessionDuration: 5 * 3600)
    }

    // MARK: - Window creation

    func testNoEventsIsInactive() {
        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(engine.remainingTime, 0)
        XCTAssertEqual(engine.currentAlertLevel, .safe)
    }

    func testFirstEventStartsWindow() {
        let event = makeEvent(minutesAgo: 10)
        engine.processEvents([event])

        XCTAssertTrue(engine.isActive)
        XCTAssertNotNil(engine.currentSession)
    }

    func testWindowStartMatchesFirstEvent() {
        let event = makeEvent(minutesAgo: 60)
        engine.processEvents([event])

        let start = engine.currentSession!.windowStart
        XCTAssertEqual(start.timeIntervalSince1970, event.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Remaining time (fixed window)

    func testRemainingTimeCorrect() {
        // Window started 1 hour ago → 4 hours remaining
        let event = makeEvent(minutesAgo: 60)
        engine.processEvents([event])

        let remaining = engine.remainingTime
        XCTAssertTrue(remaining > 235 * 60 && remaining < 245 * 60,
                       "Expected ~240min, got \(remaining / 60)min")
    }

    func testRemainingTimeWithMultipleEvents() {
        // Window starts from the FIRST event, not the last
        let events = [
            makeEvent(minutesAgo: 120), // Window starts here
            makeEvent(minutesAgo: 60),
            makeEvent(minutesAgo: 10),
        ]
        engine.processEvents(events)

        let remaining = engine.remainingTime
        // Started 2h ago → 3h remaining
        XCTAssertTrue(remaining > 175 * 60 && remaining < 185 * 60,
                       "Expected ~180min, got \(remaining / 60)min")
    }

    // MARK: - Window expiration and new window

    func testExpiredWindowDetected() {
        let event = makeEvent(minutesAgo: 310) // > 5 hours ago
        engine.processEvents([event])

        XCTAssertTrue(engine.currentSession?.isExpired ?? false)
    }

    func testNewWindowAfterExpiration() {
        // Old window: event from 6 hours ago (expired)
        // New window: event from 30 min ago
        let oldEvent = makeEvent(minutesAgo: 360)
        let newEvent = makeEvent(minutesAgo: 30)

        engine.processEvents([oldEvent, newEvent])

        // Current session should be the new window
        XCTAssertEqual(engine.currentSession?.eventCount, 1)
        XCTAssertEqual(engine.allSessions.count, 1) // Old window archived

        let remaining = engine.remainingTime
        // New window started 30min ago → ~4h30m remaining
        XCTAssertTrue(remaining > 265 * 60 && remaining < 275 * 60,
                       "Expected ~270min, got \(remaining / 60)min")
    }

    func testTickArchivesExpiredWindow() {
        let event = makeEvent(minutesAgo: 310)
        engine.processEvents([event])

        engine.tick()

        XCTAssertNil(engine.currentSession)
        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(engine.allSessions.count, 1)
    }

    // MARK: - Progress

    func testProgressAtHalfway() {
        let event = makeEvent(minutesAgo: 150) // 2.5h ago = 50%
        engine.processEvents([event])

        let progress = engine.sessionProgress
        XCTAssertTrue(progress > 0.45 && progress < 0.55,
                       "Expected ~0.50, got \(progress)")
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

    // MARK: - Events before window start are ignored

    func testEventsBeforeWindowStartIgnored() {
        // Simulate: old window expired, new window started at -30min
        // An event at -60min should NOT be in the new window
        let events = [
            makeEvent(minutesAgo: 400), // Creates first window (will expire)
            makeEvent(minutesAgo: 30),  // Creates new window after expiry
        ]
        engine.processEvents(events)

        // New window started at -30min, has 1 event
        XCTAssertEqual(engine.currentSession?.eventCount, 1)
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
