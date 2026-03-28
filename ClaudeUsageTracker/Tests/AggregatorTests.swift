import XCTest
@testable import ClaudeUsageTracker

final class AggregatorTests: XCTestCase {

    var aggregator: UsageAggregator!

    override func setUp() {
        super.setUp()
        aggregator = UsageAggregator()
    }

    // MARK: - Session usage

    func testCurrentSessionUsage() {
        let session = UsageSession(
            startTime: Date().addingTimeInterval(-3600),
            events: [
                makeEvent(tokens: 100),
                makeEvent(tokens: 200),
                makeEvent(tokens: 300),
            ]
        )

        let usage = aggregator.currentSessionUsage(session: session)
        XCTAssertEqual(usage, 600)
    }

    func testNilSessionReturnsZero() {
        XCTAssertEqual(aggregator.currentSessionUsage(session: nil), 0)
    }

    // MARK: - Weekly stats

    func testWeeklyStatsAggregation() {
        let events = (0..<5).flatMap { day -> [UsageEvent] in
            (0..<3).map { _ in
                UsageEvent(
                    timestamp: Date().addingTimeInterval(-Double(day) * 86400),
                    tokens: 1000,
                    type: .request
                )
            }
        }

        aggregator.addEvents(events)
        let stats = aggregator.weeklyStats()

        XCTAssertEqual(stats.totalTokens, 15000)
        XCTAssertEqual(stats.totalEvents, 15)
        XCTAssertTrue(stats.dailyBreakdown.count > 0)
    }

    // MARK: - Today stats

    func testTodayStats() {
        let todayEvents = [
            makeEvent(tokens: 500),
            makeEvent(tokens: 300),
        ]
        let oldEvent = UsageEvent(
            timestamp: Date().addingTimeInterval(-2 * 86400),
            tokens: 1000,
            type: .request
        )

        aggregator.addEvents(todayEvents + [oldEvent])
        let today = aggregator.todayStats()

        XCTAssertEqual(today.totalTokens, 800)
        XCTAssertEqual(today.eventCount, 2)
    }

    // MARK: - Pruning

    func testOldEventsPruned() {
        let oldEvent = UsageEvent(
            timestamp: Date().addingTimeInterval(-40 * 86400), // 40 days ago
            tokens: 1000,
            type: .request
        )
        let recentEvent = makeEvent(tokens: 500)

        aggregator.addEvents([oldEvent, recentEvent])
        let stats = aggregator.weeklyStats()

        // Old event should be pruned
        XCTAssertEqual(stats.totalTokens, 500)
    }

    // MARK: - Helpers

    private func makeEvent(tokens: Int) -> UsageEvent {
        UsageEvent(
            timestamp: Date(),
            tokens: tokens,
            type: .request
        )
    }
}
