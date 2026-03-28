import XCTest
@testable import ClaudeUsageTracker

final class ParserTests: XCTestCase {

    var parser: ClaudeLogParser!

    override func setUp() {
        super.setUp()
        parser = ClaudeLogParser()
    }

    // MARK: - JSON parsing

    func testParseJSONWithUsage() {
        let json = """
        {"type":"response","timestamp":"2025-01-15T10:30:00Z","usage":{"input_tokens":500,"output_tokens":200},"model":"claude-opus-4-6"}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .response)
        XCTAssertEqual(events[0].tokens, 700)
        XCTAssertEqual(events[0].model, "claude-opus-4-6")
    }

    func testParseJSONWithDirectTokens() {
        let json = """
        {"type":"request","timestamp":"2025-01-15T10:30:00Z","tokens":1500}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tokens, 1500)
    }

    func testParseMultipleJSONLines() {
        let json = """
        {"type":"request","timestamp":"2025-01-15T10:00:00Z","tokens":100}
        {"type":"response","timestamp":"2025-01-15T10:00:01Z","tokens":200}
        {"type":"request","timestamp":"2025-01-15T10:01:00Z","tokens":150}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 3)
    }

    // MARK: - Event type inference

    func testInferResponseFromRole() {
        let json = """
        {"role":"assistant","timestamp":"2025-01-15T10:30:00Z","tokens":500}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].type, .response)
    }

    func testInferRequestFromRole() {
        let json = """
        {"role":"user","timestamp":"2025-01-15T10:30:00Z","tokens":200}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].type, .request)
    }

    // MARK: - Timestamp formats

    func testUnixTimestampMillis() {
        let json = """
        {"type":"request","timestamp":1705312200000,"tokens":100}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(events[0].timestamp)
    }

    // MARK: - Empty / corrupt data

    func testEmptyData() {
        let events = parser.parse(data: Data(), fromFile: "test.jsonl")
        XCTAssertTrue(events.isEmpty)
    }

    func testCorruptedLine() {
        let data = "this is not json and not a log line either".data(using: .utf8)!
        let events = parser.parse(data: data, fromFile: "test.log")
        XCTAssertTrue(events.isEmpty)
    }

    func testMixedValidAndInvalidLines() {
        let content = """
        {"type":"request","timestamp":"2025-01-15T10:00:00Z","tokens":100}
        garbage line
        {"type":"response","timestamp":"2025-01-15T10:00:01Z","tokens":200}
        """
        let events = parser.parse(data: content.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Session ID

    func testSessionIdExtracted() {
        let json = """
        {"type":"request","timestamp":"2025-01-15T10:30:00Z","session_id":"abc123","tokens":100}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].sessionId, "abc123")
    }

    // MARK: - Cost-based token estimation

    func testCostBasedTokenEstimation() {
        let json = """
        {"type":"response","timestamp":"2025-01-15T10:30:00Z","costUSD":0.09}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(events[0].tokens)
        XCTAssertTrue(events[0].tokens! > 0)
    }
}
