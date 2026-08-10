# Better Spotlight

A fast macOS app launcher that does one thing: opens your apps. No web results, no definitions, no unit conversions.

![Better Spotlight](logo.png)

## Features

- **Apps only.** Nothing competes for the top result.
- **Frecency ranking.** Apps you actually use rise to the top, and history for uninstalled apps is pruned automatically.
- **Instant open.** The app list is scanned once and cached, so the launcher never scans your disk on the way up.
- **Configurable shortcut.** `⌥Space`, `⌘Space`, `⌃Space`, or `⌘⌥Space`, with an in-app guide for taking over `⌘Space` from Spotlight.
- **Follows your cursor.** Opens centered on whichever display the mouse is on.
- **Starts with your Mac.** Registered as a login item so the shortcut is always live.
- **Stays out of the way.** No Dock icon, and no menu bar icon unless you turn it on.

## Requirements

- macOS 26.5 or later
- Xcode 26 or later (to build from source)

## Run locally

1. Open `Better Spotlight.xcodeproj`
2. Press **⌘R**
3. On first launch you get a short welcome that scans your apps, then hands off to Settings to pick a shortcut
4. Open the launcher with your shortcut (default **⌥Space**)

## Using the launcher

| Action | Key |
| --- | --- |
| Open / close | Your shortcut (pressing it again hides) |
| Move selection | `↑` `↓` |
| Launch selected | `↩` |
| Dismiss | `Esc`, or click outside |

Search for **Better Spotlight Settings** in the launcher to open preferences. You can also enable the menu bar icon in Settings → Appearance, or double-click the app in Finder.

## Replacing Spotlight with ⌘Space

Select **Command + Space** in Settings and the setup steps appear inline under it:

1. **Free the shortcut.** System Settings → Keyboard → Keyboard Shortcuts → Spotlight → uncheck *Show Spotlight search*.
2. **Grant Accessibility.** System Settings → Privacy & Security → Accessibility → enable Better Spotlight, which lets the app capture `⌘Space` reliably.

Both steps have buttons in Settings that jump straight to the right pane. Settings also shows live hotkey status so you can confirm it registered.

The other presets work immediately and need neither step.

## Refreshing the app list

The catalog is cached at `~/Library/Application Support/Better Spotlight/apps.json` and refreshes when:

- You click **Refresh Apps** in Settings (or in the menu bar menu)
- A search result fails to launch because the app was moved or deleted

Install something new and it won't appear until a refresh. Launch history lives beside it in `usage.json`.

## Replay the first-run flow (development)

```bash
./scripts/reset-first-run.sh            # also clears launch history
./scripts/reset-first-run.sh --keep-usage
```

Stop the app in Xcode (⌘.) before resetting, then Run (⌘R) after. If the app is still running, macOS can write your old preferences back over the reset.

## Versioning

This project uses [SemVer](https://semver.org): `MAJOR.MINOR.PATCH`

| File / setting | Purpose |
| --- | --- |
| `VERSION` | Canonical marketing version |
| `CHANGELOG.md` | Human-readable release notes |
| Xcode `MARKETING_VERSION` | Shown in Settings / About |
| Xcode `CURRENT_PROJECT_VERSION` | Build number |

Bump version:

```bash
./scripts/set-version.sh 1.1.0
```

Then update `CHANGELOG.md` under `## [1.1.0]`.

## Publish a release

### One-time setup

1. Create a GitHub repo and push this project:

```bash
gh repo create better-spotlight --private --source=. --remote=origin --push
# or: git remote add origin git@github.com:YOU/better-spotlight.git && git push -u origin main
```

2. Ensure GitHub Actions is enabled for the repo.

### Cut a release (recommended)

1. Update `CHANGELOG.md`, moving notes from `[Unreleased]` into a new `## [X.Y.Z] - YYYY-MM-DD` section.
2. Bump version:

```bash
./scripts/set-version.sh 1.0.1
git add VERSION CHANGELOG.md "Better Spotlight.xcodeproj/project.pbxproj"
git commit -m "Release v1.0.1"
git push
```

3. Tag and push (this triggers `.github/workflows/release.yml`):

```bash
git tag v1.0.1
git push origin v1.0.1
```

4. GitHub Actions will:
   - build a Release `.app`
   - zip it as `BetterSpotlight-X.Y.Z.zip`
   - publish a GitHub Release with changelog + zip + SHA-256

### Manual local zip

```bash
./scripts/set-version.sh 1.0.1
./scripts/build-release.sh
open build/export
```

## Distribution notes (macOS Gatekeeper)

The CI zip is **ad-hoc signed** for easy testing. For public distribution:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/)
2. Archive in Xcode with **Developer ID Application** signing
3. Notarize (`xcrun notarytool`) and staple
4. Ship the notarized zip/DMG on GitHub Releases

Without notarization, users may need **Right-click → Open** the first time.

Login items are also more reliable from an installed `.app` than from an Xcode build. If Settings shows *Waiting for approval*, enable Better Spotlight in System Settings → General → Login Items.

## License

Private / your choice. Add a `LICENSE` before making the repo public.
