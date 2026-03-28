import XCTest
@testable import MyClaude

final class ParserTests: XCTestCase {

    var parser: MyClaudeLogParser!

    override func setUp() {
        super.setUp()
        parser = MyClaudeLogParser()
    }

    // MARK: - Claude Code JSONL format

    func testParseClaudeCodeAssistantEntry() {
        let json = """
        {"type":"assistant","timestamp":"2026-03-28T17:22:05.820Z","sessionId":"db83dddb","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":3,"output_tokens":9,"cache_read_input_tokens":0,"cache_creation_input_tokens":16052}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .response)
        XCTAssertEqual(events[0].tokens, 16064) // 3 + 9 + 0 + 16052
        XCTAssertEqual(events[0].model, "claude-opus-4-6")
        XCTAssertEqual(events[0].sessionId, "db83dddb")
    }

    func testParseClaudeCodeUserEntry() {
        let json = """
        {"type":"user","timestamp":"2026-03-28T17:21:00.000Z","sessionId":"db83dddb","message":{"role":"user","content":"hello"}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .request)
        XCTAssertNil(events[0].tokens)
    }

    func testParseTimestampWithFractionalSeconds() {
        let json = """
        {"type":"assistant","timestamp":"2026-03-28T17:22:05.820Z","message":{"role":"assistant","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: events[0].timestamp)
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 22)
    }

    func testParseTimestampWithoutFractionalSeconds() {
        let json = """
        {"type":"assistant","timestamp":"2026-03-28T17:22:05Z","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
    }

    func testParseCacheTokensIncluded() {
        let json = """
        {"type":"assistant","timestamp":"2026-03-28T10:00:00Z","message":{"role":"assistant","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":16052,"cache_creation_input_tokens":369}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].tokens, 16423) // 1 + 1 + 16052 + 369
    }

    func testParseMultipleLines() {
        let content = """
        {"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":"hi"}}
        {"type":"assistant","timestamp":"2026-03-28T10:00:01Z","message":{"role":"assistant","usage":{"input_tokens":100,"output_tokens":200}}}
        {"type":"user","timestamp":"2026-03-28T10:01:00Z","message":{"role":"user","content":"thanks"}}
        """
        let events = parser.parse(data: content.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[1].tokens, 300)
    }

    // MARK: - Fallback formats

    func testFallbackTopLevelUsage() {
        let json = """
        {"type":"assistant","timestamp":"2025-01-15T10:30:00Z","usage":{"input_tokens":500,"output_tokens":200}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tokens, 700)
    }

    func testFallbackDirectTokens() {
        let json = """
        {"type":"user","timestamp":"2025-01-15T10:30:00Z","tokens":1500}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tokens, 1500)
    }

    // MARK: - Session ID

    func testSessionIdExtracted() {
        let json = """
        {"type":"assistant","timestamp":"2025-01-15T10:30:00Z","sessionId":"abc-123","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].sessionId, "abc-123")
    }

    // MARK: - Empty / corrupt data

    func testEmptyData() {
        let events = parser.parse(data: Data(), fromFile: "test.jsonl")
        XCTAssertTrue(events.isEmpty)
    }

    func testCorruptedLine() {
        let data = "this is not json and not a log line either".data(using: .utf8)!
        let events = parser.parse(data: data, fromFile: "test.jsonl")
        XCTAssertTrue(events.isEmpty)
    }

    func testMixedValidAndInvalidLines() {
        let content = """
        {"type":"user","timestamp":"2025-01-15T10:00:00Z","message":{"role":"user","content":"hi"}}
        garbage line
        {"type":"assistant","timestamp":"2025-01-15T10:00:01Z","message":{"role":"assistant","usage":{"input_tokens":100,"output_tokens":200}}}
        """
        let events = parser.parse(data: content.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Event type from message.role fallback

    func testInferTypeFromMessageRole() {
        let json = """
        {"timestamp":"2025-01-15T10:30:00Z","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        let events = parser.parse(data: json.data(using: .utf8)!, fromFile: "test.jsonl")

        XCTAssertEqual(events[0].type, .response)
    }
}
