#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Better Spotlight"
CONFIG="Release"
DERIVED="$ROOT/build/DerivedData"
ARCHIVE_PATH="$ROOT/build/BetterSpotlight.xcarchive"
EXPORT_DIR="$ROOT/build/export"
APP_NAME="Better Spotlight.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

mkdir -p "$ROOT/build"
rm -rf "$DERIVED" "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer)}"

echo "==> Building ${APP_NAME} ${VERSION}"

# Ad-hoc / development-friendly build suitable for zip distribution.
# For Developer ID notarized builds, replace with archive + exportOptions.plist.
xcodebuild \
  -project "Better Spotlight.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build

APP_SRC="$DERIVED/Build/Products/${CONFIG}/${APP_NAME}"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Built app not found at $APP_SRC" >&2
  exit 1
fi

cp -R "$APP_SRC" "$EXPORT_DIR/"

# Ensure the copied app is runnable locally.
codesign --force --deep --sign - "$EXPORT_DIR/${APP_NAME}" 2>/dev/null || true

ZIP_NAME="BetterSpotlight-${VERSION}.zip"
(
  cd "$EXPORT_DIR"
  /usr/bin/ditto -c -k --keepParent "$APP_NAME" "$ZIP_NAME"
  shasum -a 256 "$ZIP_NAME" | tee "${ZIP_NAME}.sha256"
)

echo "$EXPORT_DIR/$ZIP_NAME"
