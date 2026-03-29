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
- Google Chrome (for browser scraping)
- An active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) subscription — you must be logged in to `claude.ai` in Chrome

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

## Setup

### 1. Enable JavaScript from Apple Events in Chrome

myClaude reads usage data from your browser via AppleScript. This requires a Chrome developer setting:

1. Open Google Chrome
2. Go to **View → Developer → Allow JavaScript from Apple Events**
3. Confirm the prompt

> This setting must be re-enabled after each Chrome update.

### 2. Log in to Claude

Open `https://claude.ai/settings/usage` in Chrome and make sure you are logged in. myClaude scrapes this page to read your session and weekly usage percentages.

### 3. Grant Automation Permission

On first launch, macOS will prompt for:

- **Automation** — allow myClaude to control Google Chrome (System Settings → Privacy & Security → Automation)
