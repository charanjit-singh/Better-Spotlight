# Changelog

All notable changes to Better Spotlight are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Install instructions no longer suggest right-click → Open, which macOS 15 removed as a Gatekeeper bypass. Documented clearing the download quarantine and the **Open Anyway** flow instead
- Release notes now include install and Gatekeeper steps, so they are visible on the Releases page

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

[Unreleased]: https://github.com/charanjit-singh/Better-Spotlight/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/charanjit-singh/Better-Spotlight/compare/bb10d00...v1.1.0
[1.0.0]: https://github.com/charanjit-singh/Better-Spotlight/commit/bb10d00
