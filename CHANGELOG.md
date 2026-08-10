# Changelog

All notable changes to Better Spotlight are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.3] - 2026-08-11

### Changed
- Refresh moved out of the launcher search bar and results list; use the menu bar menu or Settings instead

### Fixed
- **Refresh Apps** silently doing nothing when a scan was already in progress; it now restarts the scan reliably

## [1.1.2] - 2026-08-11

### Added
- Refresh icon in the launcher search bar and **Refresh Apps** in the results list, without logging the action in frecency
- Refresh icon on the menu bar **Refresh Apps** item

## [1.1.1] - 2026-08-11

### Fixed
- Launcher panel shadow and glass layers bleeding past rounded corners on macOS 26
- Results list auto-scrolling on open when the cursor was already over the panel; hover is ignored until the mouse moves, and only keyboard navigation scrolls the list
- Launcher glass tuned for readability on light backgrounds without forcing a heavy dark panel

## [1.1.0] - 2026-08-11

### Added
- First-run welcome flow that scans your apps with progress, then opens Settings to pick a shortcut
- Cached app catalog so the launcher opens without scanning the disk every time
- **Refresh Apps** in Settings and the menu bar menu, plus an automatic refresh when a result fails to launch
- Registers as a login item so the shortcut works after a restart
- Launcher opens on the display under the mouse cursor

### Changed
- ⌘Space setup steps now appear inline under the selected shortcut in Settings
- Pressing the shortcut while the launcher is open hides it immediately
- Menu bar icon stays off by default; the Dock icon appears only while Settings or Welcome is open
- CI and release workflows build on the macOS 26 runner image

### Fixed
- Launcher panel appearing empty because the SwiftUI content was never attached
- Crash on launch caused by a custom app entry point under MainActor isolation
- Crash when moving from the Welcome screen to Settings

## [1.0.0] - 2026-08-10

### Added
- Floating Spotlight-style app launcher with Liquid Glass UI
- Global hotkey presets (⌥Space, ⌘Space, ⌃Space, ⌘⌥Space)
- **Better Spotlight Settings** entry for shortcut + version info
- Frecency ranking for frequently used apps
- Automatic cleanup of usage data when apps are uninstalled
- Menu bar agent (no Dock icon)
- macOS app icon from project logo
- GitHub Actions release workflow with tagged semantic versions

[Unreleased]: https://github.com/charanjit-singh/Better-Spotlight/compare/v1.1.3...HEAD
[1.1.3]: https://github.com/charanjit-singh/Better-Spotlight/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/charanjit-singh/Better-Spotlight/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/charanjit-singh/Better-Spotlight/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/charanjit-singh/Better-Spotlight/compare/bb10d00...v1.1.0
[1.0.0]: https://github.com/charanjit-singh/Better-Spotlight/commit/bb10d00
