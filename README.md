# myClaude - macOS Menu Bar Usage Tracker

<p align="center">
  <img src="MyClaude/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="myClaude icon">
</p>

A macOS menu bar app that tracks Claude Code CLI usage with real-time session countdowns, weekly limits, and automated browser scraping from claude.ai.

<p align="center">
  <video src="https://github.com/aserdargun/myclaude/raw/claude/macos-menu-bar-app-e8nEs/myClaude_demo.mov" width="600" autoplay loop muted></video>
</p>

## Features

- **Color-coded menu bar** — `250m-50%-4%` with per-segment coloring (green/yellow/red)
- **Automated browser scraping** — reads session and weekly usage % from `claude.ai/settings/usage` via Chrome/Safari
- **5-hour session countdown** — tracks Claude's rolling session window with time remaining
- **Weekly limits** — All Models and Sonnet only progress bars with reset times
- **Local usage tracking** — tokens, events, sessions from `~/.claude/` log files
- **Cost-weighted tokens** — output×1.0, input×0.25, cache_creation×0.31, cache_read×0.025
- **Daily breakdown** — Sunday to Saturday usage chart
- **Auto-refresh** — configurable scrape interval (default: 300 seconds)

## Color Codes

| Color | Usage % | Time Remaining |
|-------|---------|----------------|
| Green | < 60% | > 1 hour |
| Yellow | 60–80% | 30min – 1 hour |
| Red | > 80% | < 30 minutes |

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.10+
- Google Chrome or Safari (for browser scraping)

## Build & Run

### Using Xcode

1. Open `MyClaude/Package.swift` in Xcode
2. Select the `MyClaude` scheme
3. Build and Run (Cmd+R)

### Using Command Line

```bash
cd MyClaude
swift build
swift run
```

### Create .app Bundle

```bash
./build.sh
open build/myClaude.app
```

## Architecture

```
Browser Scraping → BrowserScraper → CalibrationManager
                                          ↓
Log Files → LogReader → Parser → SessionEngine → Aggregator → ViewModel → UI
                                                                    ↓
                                                              AlertEngine → Notifications
```

## Project Structure

```
MyClaude/
├── App/              # App entry point, NSStatusItem, panel
├── UI/               # SwiftUI views and components
│   └── Components/   # Reusable UI (ProgressBar, MyClaudeIcon)
├── ViewModels/       # Observable view model
├── Domain/           # Session engine, aggregator, alerts
├── Data/             # Log reader, parser, storage, models, browser scraper, calibration
├── Utils/            # Extensions and constants
├── Resources/        # App icon assets
└── Tests/            # Unit tests
```

## Settings

Accessible via the gear icon in the dropdown:

- **Source URL** — browser page to scrape (default: `https://claude.ai/settings/usage`)
- **Auto-refresh** — scrape interval in seconds (default: 300)

## Permissions

On first launch, macOS will prompt for:

- **Automation** — allow myClaude to read browser tabs (System Settings → Privacy → Automation)
