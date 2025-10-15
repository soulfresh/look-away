# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

LookAway is a macOS menu bar application built with SwiftUI that enforces
periodic eye breaks by blocking screen interaction. It follows a configurable
work/break cycle schedule and provides visual blocking windows during breaks.

## Build and Development Commands

```bash
# Configure sourcekit-lsp for IDE support
make configure

# Build the application (Debug mode)
make build

# Run the application from command line
make run

# Run all tests
make test

# Run only unit tests (LookAwayTests target)
make test.unit

# Run specific test(s)
make test TEST_ARGS="-only-testing LookAwayTests/BreakTests"

# Clean build artifacts
make clean
```

**Important**: This is an Xcode project (`LookAway.xcodeproj`). All build
commands use `xcodebuild` under the hood.

## Core Architecture

### State Management Flow

The app uses a hierarchical state management pattern:

1. **AppDelegate** (LookAwayApp.swift:68) - Top-level lifecycle manager
   - Creates and owns `AppState`
   - Manages window lifecycle (settings window, blocker windows)
   - Subscribes to state changes via Combine publishers
   - Handles keyboard shortcuts registration

2. **AppState** (services/AppState.swift) - Global application coordinator
   - Owns the `BreakSchedule` instance
   - Manages `showSettings` flag
   - Serves as environment object for SwiftUI views

3. **BreakSchedule** (services/BreakSchedule.swift) - Schedule orchestrator
   - Manages array of `WorkCycle` instances
   - Publishes `isBlocking`, `isPaused`, `remainingTime`
   - Tracks metrics: `skipped`, `delayed`, `count`, `completed`
   - Handles system sleep/wake events via `SystemSleepMonitor`
   - Cycles through work cycles in sequence

4. **WorkCycle** (services/WorkCycle.swift) - Individual cycle state machine
   - Phases: `idle`, `working(remaining)`, `waiting`, `breaking(remaining)`, `finished`
   - Self-contained async timer using Swift Clock protocol
   - Waits for user inactivity via `InactivityListener` before starting breaks
   - Can be paused/resumed independently

### Key Behavioral Logic

**Inactivity Detection** (services/InactivityListener.swift):
- Blocks break start until both camera is disconnected AND user is inactive
- Uses `CameraActivityMonitor` to detect active video calls
- Uses `UserActivityMonitor` to track keyboard/mouse/system activity
- Prevents interrupting users during video meetings or active work

**Sleep/Wake Handling** (BreakSchedule.swift:274):
- On sleep: pauses current work cycle
- On wake (same day): restarts current work cycle from working phase
- On wake (next day): restarts entire schedule from beginning

**Blocker Windows** (components/BlockingWindow.swift):
- Full-screen windows created for each display
- Uses `.screenSaver` window level to float above all apps
- Disables app switching, Mission Control, dock during breaks
- Keyboard shortcuts for delay (Space, 1-9, 0) and skip (Escape)

### Storage and Configuration

**Persistence** (services/Storage.swift):
- Saves/loads schedule configuration via UserDefaults
- Key: `"schedule"` stores array of `WorkCycleConfig`
- Default schedule: 3x 15min work/10s break, 1x 15min work/5min break
- Debug mode uses 15s work/10s break cycles

**WorkCycleConfig** structure:
- `workLength: TimeSpan` - time between breaks
- `breakLength: TimeSpan` - duration of blocking screen
- Persisted as JSON via Codable

### UI Structure

**Menu Bar**: AppMenu shows pause/resume, take break, settings, quit, next break time

**Settings Window**: LookAwaySettings (screens/settings/) manages schedule configuration

**Blocker UI**: LookAwayContent (screens/LookAwayContent.swift)
- Shows countdown timer
- Displays break counts (completed, delayed, skipped)
- Animated gradient background
- Action buttons for delay/skip with staggered animation

### Testing

Tests use a custom `BreakClock` (LookAwayTests/services/BreakClock.swift) to control time progression in tests. The `Clock` protocol is injected into time-dependent classes (`WorkCycle`, `InactivityListener`) allowing deterministic testing.

## Development Notes

- Use `Environment.isPreview` and `Environment.isTesting` to detect runtime context
- Logger instances are disabled during tests via `Logger(enabled: !Environment.isTesting)`
- Color extensions in extensions/String+Colors.swift provide terminal coloring for logs
- Keyboard shortcuts defined in screens/KeyboardShortcuts.swift:
  - Cmd+Opt+Ctrl+P: toggle pause
  - Cmd+Opt+Ctrl+B: take break now
