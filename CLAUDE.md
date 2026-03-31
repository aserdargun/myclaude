# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

myClaude is a **macOS menu bar app** (Swift 5.10, macOS 14+) that tracks Claude Code CLI usage with real-time session countdowns, weekly limits, and automated browser scraping from claude.ai. It uses Swift Package Manager (not Xcode project files).

## Build & Run Commands

```bash
# Build (from repo root)
cd MyClaude && swift build

# Build release + create .app bundle
./build.sh          # outputs build/myClaude.app

# Run
cd MyClaude && swift run

# Run tests
cd MyClaude && swift test
```

The package is defined in `MyClaude/Package.swift`. The executable target includes all Swift files under `MyClaude/` (excluding Tests/, Resources/, Package.swift, Info.plist). The test target is `MyClaudeTests` at `MyClaude/Tests/`.

## Architecture

```
Browser (Chrome/Safari) → BrowserScraper → CalibrationManager
                                                 ↓
~/.claude/projects/*.jsonl → LogReader → Parser → SessionEngine → UsageAggregator → UsageViewModel → UI
                                                                                          ↓
                                                                                    AlertEngine → Notifications
```

### Data Flow

1. **LogReader** watches `~/.claude/projects/` for `.jsonl` files (last 7 days, skips `/subagents/`). Uses DispatchSource file monitoring + polling fallback (10s). Reads incrementally from last position, tail-reads up to 10MB on first encounter.

2. **Parser** (`MyClaudeLogParser`) extracts `UsageEvent` from Claude Code JSONL entries. Computes **weighted tokens** using API pricing ratios: output×1.0, input×0.25, cache_creation×0.3125, cache_read×0.025.

3. **SessionEngine** detects sessions two ways:
   - **Gap-based**: finds gaps >1 hour in events within the last 5h window to approximate server-side session boundaries (which include Chat/Cowork usage we can't see)
   - **Calibrated**: when browser scraping provides a session start time, uses fixed 5h period grid with continuous rollover

4. **BrowserScraper** uses AppleScript/JXA to execute JavaScript in Chrome or Safari tabs matching `claude.ai/settings/usage`. Two-tier scrape strategy: fast DOM reads (most cycles) + periodic page reload (every 60s) for fresh server data. Parses session %, weekly %, Sonnet %, and reset times.

5. **CalibrationManager** correlates scraped percentages with local weighted token counts to compute burn rates, enabling percentage estimates between scrapes.

6. **UsageViewModel** (`@Observable`) orchestrates everything. Owns the scrape timer (default 300s, configurable), UI timer (5s), and all delegate callbacks. Exposes computed properties for estimated session/weekly percentages.

7. **AppDelegate** manages the `NSStatusItem` with a custom two-line `MenuBarStatusView` (frame-based drawing, no Auto Layout — intentional to avoid layout recursion inside NSStatusBarButton). Panel is a non-activating `NSPanel` with SwiftUI content.

### Key Domain Concepts

- **5-hour session window**: Claude's rolling rate-limit period. `Constants.sessionDuration = 18000s`
- **Calibration**: syncs local token tracking with server-side percentages scraped from the browser. Becomes stale after 1 hour. Period changes (new 5h window) trigger recalibration reminders.
- **Alert levels**: safe (green, >1h remaining), warning (yellow, 30m–1h), critical (red, <30m), expired (gray)

## Key Files

| File | Purpose |
|------|---------|
| `App/MyClaudeApp.swift` | `@main` AppDelegate, NSStatusItem, MenuBarPanel, two-line menubar rendering |
| `ViewModels/UsageViewModel.swift` | Central orchestrator, all state, scrape/UI timers, calibration logic |
| `Domain/SessionEngine.swift` | Gap-based + calibrated session detection, 5h window tracking |
| `Data/BrowserScraper.swift` | AppleScript/JXA Chrome/Safari scraping, JavaScript injection |
| `Data/CalibrationSettings.swift` | Burn-rate calibration, percentage estimation |
| `Data/Parser.swift` | JSONL parsing, weighted token calculation |
| `Data/LogReader.swift` | File watching, incremental reading of ~/.claude/projects/ |
| `Data/Models.swift` | UsageEvent, UsageSession, DailyStats, WeeklyStats, AlertLevel |
| `Utils/Constants.swift` | Durations, thresholds, log paths, storage keys |

## Conventions

- Uses delegate pattern (not Combine) for component communication: `LogReaderDelegate`, `SessionEngineDelegate`, `AlertEngineDelegate`
- `UsageViewModel` uses Swift 5.9 `@Observable` macro (not `ObservableObject`)
- App runs as `.accessory` (no dock icon) with `ProcessInfo.beginActivity` to prevent App Nap
- Settings persisted via `UserDefaults` (scrape interval, source URL, daily targets, calibration data)
- `StorageProtocol` abstracts persistence for testability
