import XCTest
@testable import ClaudeUsageTracker

final class SessionEngineTests: XCTestCase {

    var engine: SessionEngine!

    override func setUp() {
        super.setUp()
        engine = SessionEngine(sessionDuration: 5 * 3600, idleThreshold: 30 * 60)
    }

    // MARK: - New session creation

    func testNewSessionCreatedOnFirstEvent() {
        let event = makeEvent(minutesAgo: 1)
        engine.processEvent(event)

        XCTAssertNotNil(engine.currentSession)
        XCTAssertEqual(engine.currentSession?.eventCount, 1)
        XCTAssertTrue(engine.isActive)
    }

    // MARK: - Events within session

    func testEventsAddedToExistingSession() {
        let e1 = makeEvent(minutesAgo: 60)
        let e2 = makeEvent(minutesAgo: 30)
        let e3 = makeEvent(minutesAgo: 5)

        engine.processEvents([e1, e2, e3])

        XCTAssertEqual(engine.currentSession?.eventCount, 3)
    }

    // MARK: - Session expiration

    func testSessionExpiresAfterDuration() {
        let event = makeEvent(minutesAgo: 301) // > 5 hours ago
        engine.processEvent(event)

        XCTAssertTrue(engine.currentSession?.isExpired ?? false)
    }

    func testNewSessionAfterExpiration() {
        let oldEvent = makeEvent(minutesAgo: 400) // well past 5 hours
        engine.processEvent(oldEvent)

        let newEvent = makeEvent(minutesAgo: 1)
        engine.processEvent(newEvent)

        // Should have started a new session
        XCTAssertEqual(engine.currentSession?.eventCount, 1)
        XCTAssertEqual(engine.sessionHistory.count, 1)
    }

    // MARK: - Remaining time

    func testRemainingTimeCalculation() {
        let event = makeEvent(minutesAgo: 60)
        engine.processEvent(event)

        let remaining = engine.remainingTime
        // Should be approximately 4 hours (240 min)
        XCTAssertTrue(remaining > 230 * 60 && remaining < 250 * 60)
    }

    // MARK: - Progress

    func testProgressCalculation() {
        let event = makeEvent(minutesAgo: 150) // 2.5 hours ago = 50%
        engine.processEvent(event)

        let progress = engine.sessionProgress
        XCTAssertTrue(progress > 0.45 && progress < 0.55)
    }

    // MARK: - Alert levels

    func testSafeAlertLevel() {
        let event = makeEvent(minutesAgo: 30)
        engine.processEvent(event)
        XCTAssertEqual(engine.currentAlertLevel, .safe)
    }

    func testWarningAlertLevel() {
        let event = makeEvent(minutesAgo: 245) // ~4h5m ago, ~55min left
        engine.processEvent(event)
        XCTAssertEqual(engine.currentAlertLevel, .warning)
    }

    func testCriticalAlertLevel() {
        let event = makeEvent(minutesAgo: 280) // ~4h40m ago, ~20min left
        engine.processEvent(event)
        XCTAssertEqual(engine.currentAlertLevel, .critical)
    }

    // MARK: - Reconstruction

    func testReconstructFromEvents() {
        let events = [
            makeEvent(minutesAgo: 120),
            makeEvent(minutesAgo: 90),
            makeEvent(minutesAgo: 60),
            makeEvent(minutesAgo: 30),
        ]

        engine.reconstruct(from: events)

        XCTAssertNotNil(engine.currentSession)
        XCTAssertEqual(engine.currentSession?.eventCount, 4)
    }

    // MARK: - Empty state

    func testNoSessionInitially() {
        XCTAssertNil(engine.currentSession)
        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(engine.remainingTime, 0)
        XCTAssertEqual(engine.currentAlertLevel, .safe)
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
