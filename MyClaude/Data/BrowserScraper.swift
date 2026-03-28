import Foundation
import AppKit

/// Data scraped from claude.ai/settings usage page.
struct ScrapedUsageData {
    /// Current session percentage used (e.g. 41.0)
    let sessionPercent: Double
    /// Weekly "All models" percentage used (e.g. 55.0)
    let weeklyPercent: Double
    /// Seconds until the current session resets
    let sessionResetsIn: TimeInterval
}

enum BrowserScraperError: LocalizedError {
    case noBrowserFound
    case noClaudeSettingsTab
    case scriptExecutionFailed(String)
    case parseFailure(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .noBrowserFound:
            return "No supported browser running. Open Chrome or Safari."
        case .noClaudeSettingsTab:
            return "No claude.ai/settings tab found. Open claude.ai → Settings → Usage in your browser."
        case .scriptExecutionFailed(let detail):
            return "Script failed: \(detail)"
        case .parseFailure(let detail):
            return "Could not parse usage data: \(detail)"
        case .permissionDenied(let browser):
            return "Permission denied for \(browser). Allow myClaude in System Settings → Privacy → Automation."
        }
    }
}

/// Scrapes Claude usage percentages from an open browser tab via AppleScript.
///
/// Supports Google Chrome and Safari. Finds a tab with claude.ai/settings,
/// executes JavaScript to extract session % and weekly % values, and parses
/// the result.
final class BrowserScraper {

    /// JavaScript injected into the browser tab to scrape usage data.
    /// Searches for text patterns rather than CSS selectors for resilience.
    /// Returns a JSON string: {"session_pct":41,"weekly_pct":55,"resets_h":1,"resets_m":24}
    private let scrapeJS: String = #"""
    (function() {
        var body = document.body ? document.body.innerText : '';
        var result = {};

        // Split body into sections around "Current session" and "All models"/"Weekly"
        // to reliably separate session vs weekly data.
        var sessionIdx = body.indexOf('Current session');
        var weeklyIdx = body.indexOf('All models');
        if (weeklyIdx === -1) weeklyIdx = body.indexOf('Weekly limits');

        // Extract session section text (from "Current session" to "All models"/"Weekly")
        var sessionText = '';
        var weeklyText = '';
        if (sessionIdx !== -1 && weeklyIdx !== -1 && weeklyIdx > sessionIdx) {
            sessionText = body.substring(sessionIdx, weeklyIdx);
            weeklyText = body.substring(weeklyIdx);
        } else if (sessionIdx !== -1) {
            sessionText = body.substring(sessionIdx);
        } else {
            sessionText = body;
        }
        if (!weeklyText) weeklyText = body;

        // Session %: find "XX% used" in session section
        var sPct = sessionText.match(/(\d+)%\s*used/);
        if (sPct) result.session_pct = parseInt(sPct[1]);

        // Weekly %: find "XX% used" in weekly section
        var wPct = weeklyText.match(/(\d+)%\s*used/);
        if (wPct) result.weekly_pct = parseInt(wPct[1]);

        // Session "Resets in" from session section only
        var sReset = sessionText.match(/Resets in\s+(?:(\d+)\s*hr?\s+)?(\d+)\s*min/i);
        if (sReset) {
            result.resets_h = sReset[1] ? parseInt(sReset[1]) : 0;
            result.resets_m = parseInt(sReset[2]);
        }

        return JSON.stringify(result);
    })()
    """#

    // MARK: - Public API

    /// Scrape Claude usage data from an open browser tab.
    /// Tries Chrome first, then Safari.
    func scrape() async throws -> ScrapedUsageData {
        // Try Chrome first
        if isAppRunning("Google Chrome") {
            do {
                return try await scrapeFromChrome()
            } catch BrowserScraperError.permissionDenied {
                throw BrowserScraperError.permissionDenied("Google Chrome")
            } catch BrowserScraperError.noClaudeSettingsTab {
                // Fall through to Safari
            }
        }

        // Try Safari
        if isAppRunning("Safari") {
            do {
                return try await scrapeFromSafari()
            } catch BrowserScraperError.permissionDenied {
                throw BrowserScraperError.permissionDenied("Safari")
            } catch BrowserScraperError.noClaudeSettingsTab {
                // Neither browser has the tab
            }
        }

        if !isAppRunning("Google Chrome") && !isAppRunning("Safari") {
            throw BrowserScraperError.noBrowserFound
        }
        throw BrowserScraperError.noClaudeSettingsTab
    }

    // MARK: - Chrome

    private func scrapeFromChrome() async throws -> ScrapedUsageData {
        // JXA (JavaScript for Automation) script for Chrome
        // Wrapped in a function — top-level `return` is not valid in JXA.
        let jxa = """
        (function() {
            var chrome = Application('Google Chrome');
            var windows = chrome.windows();
            for (var i = 0; i < windows.length; i++) {
                var tabs = windows[i].tabs();
                for (var j = 0; j < tabs.length; j++) {
                    var url = tabs[j].url();
                    if (url && url.indexOf('claude.ai/settings') !== -1) {
                        var result = tabs[j].execute({javascript: \(scrapeJS.jxaEscaped)});
                        return result;
                    }
                }
            }
            return '__NO_TAB__';
        })()
        """
        let output = try await runOsascript(language: "JavaScript", script: jxa)
        if output.contains("__NO_TAB__") {
            throw BrowserScraperError.noClaudeSettingsTab
        }
        return try parseResult(output)
    }

    // MARK: - Safari

    private func scrapeFromSafari() async throws -> ScrapedUsageData {
        let jxa = """
        (function() {
            var safari = Application('Safari');
            var windows = safari.windows();
            for (var i = 0; i < windows.length; i++) {
                var tabs = windows[i].tabs();
                for (var j = 0; j < tabs.length; j++) {
                    var url = tabs[j].url();
                    if (url && url.indexOf('claude.ai/settings') !== -1) {
                        var result = safari.doJavaScript(\(scrapeJS.jxaEscaped), {in: tabs[j]});
                        return result;
                    }
                }
            }
            return '__NO_TAB__';
        })()
        """
        let output = try await runOsascript(language: "JavaScript", script: jxa)
        if output.contains("__NO_TAB__") {
            throw BrowserScraperError.noClaudeSettingsTab
        }
        return try parseResult(output)
    }

    // MARK: - Execution

    private func runOsascript(language: String, script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", language, "-e", script]

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    if errorOutput.contains("not authorized") || errorOutput.contains("assistive") || errorOutput.contains("permission") {
                        continuation.resume(throwing: BrowserScraperError.permissionDenied("browser"))
                    } else {
                        continuation.resume(throwing: BrowserScraperError.scriptExecutionFailed(errorOutput))
                    }
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: BrowserScraperError.scriptExecutionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Parsing

    private func parseResult(_ jsonString: String) throws -> ScrapedUsageData {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowserScraperError.parseFailure("Invalid JSON: \(jsonString.prefix(200))")
        }

        guard let sessionPct = json["session_pct"] as? Int else {
            throw BrowserScraperError.parseFailure("Could not find session %. Is the Usage section visible?")
        }

        guard let weeklyPct = json["weekly_pct"] as? Int else {
            throw BrowserScraperError.parseFailure("Could not find weekly %. Is the Usage section visible?")
        }

        let hours = json["resets_h"] as? Int ?? 0
        let minutes = json["resets_m"] as? Int ?? 0
        let resetsIn = TimeInterval(hours * 3600 + minutes * 60)

        if resetsIn <= 0 {
            throw BrowserScraperError.parseFailure("Could not find 'Resets in' time. Is the page fully loaded?")
        }

        return ScrapedUsageData(
            sessionPercent: Double(sessionPct),
            weeklyPercent: Double(weeklyPct),
            sessionResetsIn: resetsIn
        )
    }

    // MARK: - Helpers

    private func isAppRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == name
        }
    }
}

// MARK: - String extension for JXA escaping

private extension String {
    /// Wraps the string as a JXA string literal with proper escaping.
    var jxaEscaped: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }
}
