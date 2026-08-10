#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/set-version.sh 1.2.3 [build_number]
VERSION="${1:?semantic version required, e.g. 1.2.3}"
BUILD="${2:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be semver X.Y.Z (got: $VERSION)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/Better Spotlight.xcodeproj/project.pbxproj"

if [[ -z "$BUILD" ]]; then
  BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
fi

echo "$VERSION" > "$ROOT/VERSION"

# Update MARKETING_VERSION / CURRENT_PROJECT_VERSION in the Xcode project.
/usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${BUILD};/g" "$PBXPROJ"

echo "Set version ${VERSION} (build ${BUILD})"
