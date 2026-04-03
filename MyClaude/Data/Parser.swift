import Foundation

protocol ParserProtocol {
    func parse(data: Data, fromFile path: String) -> [UsageEvent]
    func parseLine(_ line: String) -> UsageEvent?
}

final class MyClaudeLogParser: ParserProtocol {

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
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
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseClaudeCodeEntry(json)
    }

    // MARK: - Claude Code JSONL entry parsing

    private func parseClaudeCodeEntry(_ json: [String: Any]) -> UsageEvent? {
        let timestamp = extractTimestamp(from: json)
        let type = extractEventType(from: json)
        let message = json["message"] as? [String: Any]
        let (tokens, weighted) = extractTokens(from: json, message: message)
        let model = message?["model"] as? String
        let sessionId = json["sessionId"] as? String

        // Skip entries with no useful data (no timestamp and no tokens)
        guard timestamp != nil || tokens != nil else { return nil }

        return UsageEvent(
            timestamp: timestamp ?? Date(),
            tokens: tokens,
            weightedTokens: weighted,
            type: type,
            model: model,
            sessionId: sessionId
        )
    }

    // MARK: - Timestamp

    private func extractTimestamp(from json: [String: Any]) -> Date? {
        guard let str = json["timestamp"] as? String else { return nil }
        // Try with fractional seconds first (e.g., "2026-03-28T17:22:05.820Z")
        if let date = isoFormatter.date(from: str) { return date }
        // Fallback without fractional seconds
        if let date = isoFormatterNoFraction.date(from: str) { return date }
        return nil
    }

    // MARK: - Tokens

    /// Returns (rawTokens, weightedTokens).
    ///
    /// Raw = sum of all token fields (for display).
    /// Weighted = cost-approximated tokens matching Claude's rate limiter.
    ///
    /// Weights based on Anthropic API pricing ratios:
    ///   output_tokens:              1.0   (most expensive, base unit)
    ///   input_tokens:               0.25  (4× cheaper than output)
    ///   cache_creation_input:       0.3125 (slightly more than input)
    ///   cache_read_input:           0.025  (40× cheaper than output)
    private func extractTokens(from json: [String: Any], message: [String: Any]?) -> (Int?, Int?) {
        // Claude Code format: message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}
        if let usage = message?["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            // Raw total: only input + output (matches CLI display).
            // Cache tokens are excluded from the display total — they represent
            // re-reads of the cached prompt context and massively inflate counts.
            let total = input + output
            if total > 0 || cacheRead > 0 || cacheCreation > 0 {
                let weighted = Int(
                    Double(output) * 1.0
                    + Double(input) * 0.25
                    + Double(cacheCreation) * 0.3125
                    + Double(cacheRead) * 0.025
                )
                return (total > 0 ? total : nil, weighted)
            }
        }

        // Fallback: top-level usage object
        if let usage = json["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let total = input + output
            if total > 0 {
                let weighted = Int(Double(output) * 1.0 + Double(input) * 0.25)
                return (total, weighted)
            }
        }

        // Fallback: direct token fields (no breakdown, use raw as weighted)
        for key in ["tokens", "total_tokens", "token_count"] {
            if let val = json[key] as? Int { return (val, val) }
        }

        return (nil, nil)
    }

    // MARK: - Event type

    private func extractEventType(from json: [String: Any]) -> EventType {
        // Claude Code uses top-level "type" field: "assistant", "user", etc.
        if let typeStr = json["type"] as? String {
            switch typeStr.lowercased() {
            case "user", "human", "request", "input":
                return .request
            case "assistant", "response", "output", "completion":
                return .response
            case "error":
                return .error
            default:
                break
            }
        }

        // Fallback: check message.role
        if let message = json["message"] as? [String: Any],
           let role = message["role"] as? String {
            switch role {
            case "assistant": return .response
            case "user": return .request
            default: break
            }
        }

        return .unknown
    }
}
