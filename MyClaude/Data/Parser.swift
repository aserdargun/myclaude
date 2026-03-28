import Foundation

protocol ParserProtocol {
    func parse(data: Data, fromFile path: String) -> [UsageEvent]
    func parseLine(_ line: String) -> UsageEvent?
}

final class MyClaudeLogParser: ParserProtocol {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) {
                return date
            }
            // Try millisecond timestamp
            if let ms = Double(str) {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    // MARK: - JSONL parsing (one JSON object per line)

    func parse(data: Data, fromFile path: String) -> [UsageEvent] {
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines)
        return lines.compactMap { parseLine($0) }
    }

    func parseLine(_ line: String) -> UsageEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try JSON parsing first
        if let event = parseJSON(trimmed) {
            return event
        }

        // Fallback: regex-based text parsing
        return parseText(trimmed)
    }

    // MARK: - JSON parsing

    private func parseJSON(_ text: String) -> UsageEvent? {
        guard let data = text.data(using: .utf8) else { return nil }

        // Try generic JSON object
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let timestamp = extractTimestamp(from: json) ?? Date()
        let tokens = extractTokens(from: json)
        let type = extractEventType(from: json)
        let model = json["model"] as? String
        let sessionId = json["session_id"] as? String
            ?? json["sessionId"] as? String

        return UsageEvent(
            timestamp: timestamp,
            tokens: tokens,
            type: type,
            model: model,
            sessionId: sessionId
        )
    }

    private func extractTimestamp(from json: [String: Any]) -> Date? {
        for key in ["timestamp", "ts", "time", "created_at", "date"] {
            if let str = json[key] as? String {
                if let date = ISO8601DateFormatter().date(from: str) {
                    return date
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                if let date = formatter.date(from: str) {
                    return date
                }
            } else if let num = json[key] as? Double {
                // Unix timestamp (seconds or milliseconds)
                if num > 1_000_000_000_000 {
                    return Date(timeIntervalSince1970: num / 1000)
                }
                return Date(timeIntervalSince1970: num)
            }
        }
        return nil
    }

    private func extractTokens(from json: [String: Any]) -> Int? {
        // Direct token fields
        for key in ["tokens", "total_tokens", "token_count"] {
            if let val = json[key] as? Int { return val }
        }

        // Nested usage object
        if let usage = json["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            if input + output > 0 { return input + output }
        }

        // costUSD-based estimation (rough: $3/MTok input, $15/MTok output for Opus)
        if let cost = json["costUSD"] as? Double, cost > 0 {
            // Rough estimate: average ~$9/MTok → tokens ≈ cost / 9 * 1_000_000
            return Int(cost / 9.0 * 1_000_000)
        }

        return nil
    }

    private func extractEventType(from json: [String: Any]) -> EventType {
        if let typeStr = json["type"] as? String {
            switch typeStr.lowercased() {
            case "request", "human", "user", "input":
                return .request
            case "response", "assistant", "output", "completion":
                return .response
            case "error":
                return .error
            default:
                return .unknown
            }
        }

        // Infer from structure
        if json["role"] as? String == "assistant" || json["completion"] != nil {
            return .response
        }
        if json["role"] as? String == "user" || json["prompt"] != nil {
            return .request
        }
        if json["error"] != nil {
            return .error
        }

        return .unknown
    }

    // MARK: - Text-based fallback parsing

    private func parseText(_ text: String) -> UsageEvent? {
        // Pattern: [timestamp] type: details
        let timestampPattern = #"\[?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[^\]]*)\]?"#
        let tokenPattern = #"(\d+)\s*tokens?"#

        var timestamp: Date?
        var tokens: Int?
        var type: EventType = .unknown

        if let match = text.range(of: timestampPattern, options: .regularExpression) {
            let ts = String(text[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            timestamp = ISO8601DateFormatter().date(from: ts)
        }

        if let match = text.range(of: tokenPattern, options: .regularExpression) {
            let numStr = String(text[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            tokens = Int(numStr)
        }

        if text.lowercased().contains("request") || text.lowercased().contains("input") {
            type = .request
        } else if text.lowercased().contains("response") || text.lowercased().contains("output") {
            type = .response
        } else if text.lowercased().contains("error") {
            type = .error
        }

        guard timestamp != nil || tokens != nil else { return nil }

        return UsageEvent(
            timestamp: timestamp ?? Date(),
            tokens: tokens,
            type: type
        )
    }
}
