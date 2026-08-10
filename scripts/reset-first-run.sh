#!/usr/bin/env bash
set -euo pipefail

# Wipes local state so the next launch feels like a fresh install.
# Usage: ./scripts/reset-first-run.sh [--keep-usage]

BUNDLE_ID="cjsingg.Better-Spotlight"
PREFS_PLIST="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
SUPPORT_DIR="$HOME/Library/Application Support/Better Spotlight"
KEEP_USAGE=0

if [[ "${1:-}" == "--keep-usage" ]]; then
  KEEP_USAGE=1
fi

quit_app() {
  if ! pgrep -x "Better Spotlight" >/dev/null 2>&1; then
    return 0
  fi

  echo "Quitting Better Spotlight…"
  osascript -e 'quit app "Better Spotlight"' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "Better Spotlight" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Force quitting…"
  killall "Better Spotlight" >/dev/null 2>&1 || true
  sleep 0.5
}

quit_app

if pgrep -x "Better Spotlight" >/dev/null 2>&1; then
  echo "Could not quit Better Spotlight. Stop it in Xcode (⌘.) then run this script again." >&2
  exit 1
fi

# Must delete after the app exits, or macOS writes prefs back from memory.
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$PREFS_PLIST"
rm -f "$SUPPORT_DIR/apps.json"
mkdir -p "$SUPPORT_DIR"
touch "$SUPPORT_DIR/.force-welcome"

if [[ "$KEEP_USAGE" -eq 0 ]]; then
  rm -f "$SUPPORT_DIR/usage.json"
  echo "Cleared preferences, cached app list, and launch history."
else
  echo "Cleared preferences and cached app list (launch history kept)."
fi

if [[ -f "$PREFS_PLIST" ]]; then
  echo "Warning: preferences file still exists at $PREFS_PLIST" >&2
  exit 1
fi

echo "Ready. In Xcode: Stop (⌘.) then Run (⌘R) to see the welcome flow."
