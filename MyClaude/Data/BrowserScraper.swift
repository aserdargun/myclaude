import Foundation
import AppKit

/// Describes when a weekly limit resets.
enum WeeklyResetInfo {
    /// Relative: resets in N seconds
    case resetsIn(TimeInterval)
    /// Absolute: resets on a specific day/time (e.g. "Sun", "3:00 PM")
    case resetsAt(day: String, time: String)
}

/// Data scraped from claude.ai/settings usage page.
struct ScrapedUsageData {
    /// Current session percentage used (e.g. 41.0)
    let sessionPercent: Double
    /// Weekly "All models" percentage used (e.g. 55.0)
    let weeklyPercent: Double
    /// Weekly "Sonnet only" percentage used (e.g. 30.0), nil if not found
    let sonnetPercent: Double?
    /// Seconds until the current session resets, nil if no active session
    let sessionResetsIn: TimeInterval?
    /// When the All Models weekly limit resets
    let allModelsReset: WeeklyResetInfo?
    /// When the Sonnet only weekly limit resets
    let sonnetReset: WeeklyResetInfo?
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
            return "No claude.ai/settings/usage tab found. Open \(Constants.claudeUsageURL) in your browser."
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

        // Weekly section: split at "All models" and "Sonnet" boundaries
        // Find "All models" subsection and "Sonnet" subsection within weekly text
        var sonnetIdx = weeklyText.indexOf('Sonnet');
        var allModelsText = weeklyText;
        var sonnetText = '';
        if (sonnetIdx !== -1) {
            allModelsText = weeklyText.substring(0, sonnetIdx);
            sonnetText = weeklyText.substring(sonnetIdx);
        }

        // Weekly "All models" %: find "XX% used" in all models subsection
        var wPct = allModelsText.match(/(\d+)%\s*used/);
        if (wPct) result.weekly_pct = parseInt(wPct[1]);

        // Sonnet only %: find "XX% used" in sonnet subsection
        if (sonnetText) {
            var sPctSonnet = sonnetText.match(/(\d+)%\s*used/);
            if (sPctSonnet) result.sonnet_pct = parseInt(sPctSonnet[1]);
        }

        // Session "Resets in" from session section only
        var sReset = sessionText.match(/Resets in\s+(?:(\d+)\s*hr?\s+)?(\d+)\s*min/i);
        if (sReset) {
            result.resets_h = sReset[1] ? parseInt(sReset[1]) : 0;
            result.resets_m = parseInt(sReset[2]);
        }

        // All Models reset time: try "Resets in" or "Resets <Day> <Time>" formats
        var amReset = allModelsText.match(/Resets in\s+(?:(\d+)\s*days?\s+)?(?:(\d+)\s*hr?\s+)?(\d+)\s*min/i);
        if (amReset) {
            result.am_resets_d = amReset[1] ? parseInt(amReset[1]) : 0;
            result.am_resets_h = amReset[2] ? parseInt(amReset[2]) : 0;
            result.am_resets_m = parseInt(amReset[3]);
        } else {
            var amResetDate = allModelsText.match(/Resets\s+(\w+)\s+(\d{1,2}:\d{2}\s*[AP]M)/i);
            if (amResetDate) {
                result.am_resets_day = amResetDate[1];
                result.am_resets_time = amResetDate[2];
            }
        }

        // Sonnet reset time: try "Resets in" or "Resets <Day> <Time>" formats
        if (sonnetText) {
            var snReset = sonnetText.match(/Resets in\s+(?:(\d+)\s*days?\s+)?(?:(\d+)\s*hr?\s+)?(\d+)\s*min/i);
            if (snReset) {
                result.sn_resets_d = snReset[1] ? parseInt(snReset[1]) : 0;
                result.sn_resets_h = snReset[2] ? parseInt(snReset[2]) : 0;
                result.sn_resets_m = parseInt(snReset[3]);
            } else {
                var snResetDate = sonnetText.match(/Resets\s+(\w+)\s+(\d{1,2}:\d{2}\s*[AP]M)/i);
                if (snResetDate) {
                    result.sn_resets_day = snResetDate[1];
                    result.sn_resets_time = snResetDate[2];
                }
            }
        }

        return JSON.stringify(result);
    })()
    """#

    // MARK: - Public API

    /// Scrape Claude usage data from an open browser tab.
    /// If Chrome is not running or has no claude.ai/settings tab,
    /// opens Chrome with the settings page and waits for it to load.
    func scrape(url: String = Constants.claudeUsageURL, reload: Bool = false) async throws -> ScrapedUsageData {
        let searchDomain = extractDomain(from: url)

        // Try Chrome first
        if isAppRunning("Google Chrome") {
            do {
                return try await scrapeFromChrome(matching: searchDomain, reload: reload)
            } catch BrowserScraperError.permissionDenied {
                throw BrowserScraperError.permissionDenied("Google Chrome")
            } catch BrowserScraperError.noClaudeSettingsTab {
                return try await openAndScrapeInChrome(url, matching: searchDomain)
            }
        }

        // Try Safari
        if isAppRunning("Safari") {
            do {
                return try await scrapeFromSafari(matching: searchDomain)
            } catch BrowserScraperError.permissionDenied {
                throw BrowserScraperError.permissionDenied("Safari")
            } catch BrowserScraperError.noClaudeSettingsTab {
                // Fall through to open Chrome
            }
        }

        // Neither browser has the tab — open Chrome with the page
        return try await openAndScrapeInChrome(url, matching: searchDomain)
    }

    private func extractDomain(from url: String) -> String {
        // Extract "claude.ai/settings" from full URL for tab matching
        guard let u = URL(string: url), let host = u.host else {
            return "claude.ai/settings"
        }
        return "\(host)\(u.path)"
    }

    // MARK: - Open Chrome with claude.ai/settings

    /// Opens Chrome (launching if needed) with the given URL, waits for load,
    /// then scrapes.
    private func openAndScrapeInChrome(_ url: String, matching domain: String) async throws -> ScrapedUsageData {
        let jxa = """
        (function() {
            var chrome = Application('Google Chrome');
            chrome.activate();
            if (chrome.windows().length === 0) {
                chrome.Window().make();
            }
            var win = chrome.windows()[0];
            var tab = chrome.Tab();
            win.tabs.push(tab);
            tab.url = '\(url)';
            delay(1);
            var maxWait = 15;
            while (tab.loading() && maxWait > 0) {
                delay(1);
                maxWait--;
            }
            // Wait for SPA content to render after page load
            var contentWait = 10;
            while (contentWait > 0) {
                var check = tab.execute({javascript: 'document.body ? document.body.innerText : ""'});
                if (check && check.indexOf('% used') !== -1) break;
                delay(1);
                contentWait--;
            }
            var result = tab.execute({javascript: \(scrapeJS.jxaEscaped)});
            return result;
        })()
        """
        let output = try await runOsascript(language: "JavaScript", script: jxa)
        return try parseResult(output)
    }

    // MARK: - Chrome

    private func scrapeFromChrome(matching domain: String, reload: Bool = false) async throws -> ScrapedUsageData {
        // Single JXA call: find tab → optionally reload & wait → scrape
        let reloadFlag = reload ? "true" : "false"
        let jxa = """
        (function() {
            var chrome = Application('Google Chrome');
            var windows = chrome.windows();
            var doReload = \(reloadFlag);
            for (var i = 0; i < windows.length; i++) {
                var tabs = windows[i].tabs();
                for (var j = 0; j < tabs.length; j++) {
                    var url = tabs[j].url();
                    if (url && url.indexOf('\(domain)') !== -1) {
                        if (doReload) {
                            tabs[j].reload();
                            delay(1);
                            var maxWait = 15;
                            while (tabs[j].loading() && maxWait > 0) {
                                delay(1);
                                maxWait--;
                            }
                            // Wait for SPA content to render after page load
                            var contentWait = 10;
                            while (contentWait > 0) {
                                var check = tabs[j].execute({javascript: 'document.body ? document.body.innerText : ""'});
                                if (check && check.indexOf('% used') !== -1) break;
                                delay(1);
                                contentWait--;
                            }
                        }
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

    private func scrapeFromSafari(matching domain: String) async throws -> ScrapedUsageData {
        let jxa = """
        (function() {
            var safari = Application('Safari');
            var windows = safari.windows();
            for (var i = 0; i < windows.length; i++) {
                var tabs = windows[i].tabs();
                for (var j = 0; j < tabs.length; j++) {
                    var url = tabs[j].url();
                    if (url && url.indexOf('\(domain)') !== -1) {
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

        // Session % — defaults to 0 if no active session ("Starts when a message is sent")
        let sessionPct = json["session_pct"] as? Int ?? 0
        let weeklyPct = json["weekly_pct"] as? Int

        // If neither session nor weekly data found, the page likely hasn't rendered yet
        guard sessionPct > 0 || weeklyPct != nil else {
            throw BrowserScraperError.parseFailure("No usage data found. Is the Usage section visible?")
        }

        // Session reset time — nil when no active session
        let hours = json["resets_h"] as? Int ?? 0
        let minutes = json["resets_m"] as? Int ?? 0
        let resetsInTotal = hours * 3600 + minutes * 60
        let resetsIn: TimeInterval? = resetsInTotal > 0 ? TimeInterval(resetsInTotal) : nil

        // Sonnet %
        let sonnetPct = json["sonnet_pct"] as? Int

        // All Models reset
        let allModelsReset = parseWeeklyReset(json: json, prefix: "am")

        // Sonnet reset
        let sonnetReset = parseWeeklyReset(json: json, prefix: "sn")

        return ScrapedUsageData(
            sessionPercent: Double(sessionPct),
            weeklyPercent: Double(weeklyPct ?? 0),
            sonnetPercent: sonnetPct.map { Double($0) },
            sessionResetsIn: resetsIn,
            allModelsReset: allModelsReset,
            sonnetReset: sonnetReset
        )
    }

    private func parseWeeklyReset(json: [String: Any], prefix: String) -> WeeklyResetInfo? {
        // Try relative format: "Resets in Xd Xh Xm"
        let days = json["\(prefix)_resets_d"] as? Int ?? 0
        let hours = json["\(prefix)_resets_h"] as? Int ?? 0
        let minutes = json["\(prefix)_resets_m"] as? Int ?? 0
        let total = days * 86400 + hours * 3600 + minutes * 60
        if total > 0 {
            return .resetsIn(TimeInterval(total))
        }
        // Try absolute format: "Resets Sun 3:00 PM"
        if let day = json["\(prefix)_resets_day"] as? String,
           let time = json["\(prefix)_resets_time"] as? String {
            return .resetsAt(day: day, time: time)
        }
        return nil
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
    /// Escapes backslashes, quotes, backticks, newlines, carriage returns,
    /// and other special characters to prevent injection.
    var jxaEscaped: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\0", with: "")
        return "'\(escaped)'"
    }
}
