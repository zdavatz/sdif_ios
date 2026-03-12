# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project (required after changing project.yml)
xcodegen generate

# Build for simulator
xcodebuild -project SDIF.xcodeproj -scheme SDIF \
  -destination 'platform=iOS Simulator,id=86422F52-1CD5-4E9A-92A6-231FF2BDA72C' build

# Run UI tests / generate screenshots
xcodebuild test -project SDIF.xcodeproj -scheme SDIFUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'

# Physical device requires signing team set in Xcode
```

## Architecture

SwiftUI app with 3 tabs, no external dependencies. Uses SQLite3 C API directly.

### Key Files

- `project.yml` — xcodegen project definition (iOS 17.0+, universal device family)
- `SDIF/SDIFApp.swift` → `ContentView.swift` — app entry with TabView, settings sheet
- `SDIF/DatabaseManager.swift` — singleton SQLite access layer, all queries. Mark `@unchecked Sendable`. Prefers downloaded DB in Documents dir, falls back to bundled. Has `reloadDatabase()` for post-download refresh.
- `SDIF/InteractionChecker.swift` — ports 4 interaction detection strategies from Rust `web.rs`: substance match, ATC class-level, CYP enzyme, EPha curated. Mark `@unchecked Sendable`.
- `SDIF/Models.swift` — all data models + `Int` severity extensions
- `SDIF/BasketCheckView.swift` — Tab 1: drug search, basket, interaction check. Contains `FlowLayout`.
- `SDIF/ClinicalSearchView.swift` — Tab 2: clinical term search with suggestions + pagination
- `SDIF/ATCClassView.swift` — Tab 3: sortable ATC class table
- `SDIF/InteractionCardView.swift` — reusable severity-colored card with context menu copy, `routeBadge()` helper
- `SDIF/SettingsView.swift` — DB download from pillbox.oddb.org, app info
- `SDIF/AppIconButton.swift` — reusable toolbar icon that opens settings
- `SDIF/Resources/interactions.db` — 57MB SQLite database (not tracked in git, gitignored)
- `SDIFUITests/ScreenshotTests.swift` — automated UI test that generates App Store screenshots and app preview video
- `screenshots/` — generated screenshots (6 PNGs + app_preview.mp4)

### Threading

All heavy DB operations must use `Task.detached(priority: .userInitiated)` to avoid blocking the main thread. SwiftUI `.task` and `Task {}` inherit `@MainActor`. The iOS watchdog will kill the app if the main thread is blocked too long.

### Patterns

- Debounced search: cancel previous `Task`, sleep 200ms, check `!Task.isCancelled`
- Suggestion selection with multi-word terms: use `skipNextSuggest` flag to prevent `onChange` from re-triggering suggestions
- Severity: score 0–3 mapped to colors/labels via `Int` extensions in Models.swift
- Each tab view takes `@Binding var showSettings: Bool` from ContentView
- InteractionCardView: `.textSelection(.enabled)` + `.contextMenu` with "Alles kopieren" for full card copy
- ATS exception in project.yml for HTTP download from pillbox.oddb.org

## Database

Downloaded at runtime from `http://pillbox.oddb.org/interactions.db` to Documents dir. Bundled copy in Resources as fallback. Tables: `drugs`, `interactions`, `epha_interactions`, `substance_brand_map`, `class_keywords`, `cyp_rules`.

## License

GPLv3
