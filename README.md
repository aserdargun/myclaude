# myClaude - macOS Menu Bar Usage Tracker

A lightweight macOS menu bar application that tracks Claude Code CLI usage with rolling 5-hour session countdowns, weekly statistics, and real-time alerts.

## Features

- **5-hour rolling session countdown** with color-coded status (green/yellow/red)
- **Real-time log parsing** from `~/.claude/` directories
- **Weekly usage statistics** with daily breakdowns
- **Native macOS notifications** at 80% and 95% thresholds
- **Low resource usage** - runs efficiently in background

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.10+
- Xcode 15+

## Build & Run

### Using Xcode

1. Open `ClaudeUsageTracker/Package.swift` in Xcode
2. Select the `ClaudeUsageTracker` scheme
3. Build and Run (Cmd+R)

### Using Command Line

```bash
cd ClaudeUsageTracker
swift build
swift run
```

### Create .app Bundle

```bash
cd ClaudeUsageTracker
swift build -c release
# The binary will be at .build/release/ClaudeUsageTracker
```

## Architecture

```
Log File Change → LogReader → Parser → SessionEngine → Aggregator → ViewModel → UI
                                                         ↓
                                                    AlertEngine → Notifications
```

## Project Structure

```
ClaudeUsageTracker/
├── App/              # App entry point and menu bar controller
├── UI/               # SwiftUI views and components
├── ViewModels/       # Observable view model
├── Domain/           # Session engine, aggregator, alerts
├── Data/             # Log reader, parser, storage, models
├── Utils/            # Extensions and constants
└── Tests/            # Unit tests
```

## Configuration

Edit `Utils/Constants.swift` to customize:

- `sessionDuration` - Rolling window duration (default: 5 hours)
- `idleThreshold` - Idle gap detection (default: 30 minutes)
- `warningThreshold` - Warning alert at 80%
- `criticalThreshold` - Critical alert at 95%
- `uiUpdateInterval` - UI refresh rate (default: 5 seconds)
