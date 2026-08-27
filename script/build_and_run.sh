#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="StoryMentor"
BUNDLE_ID="com.liuyicheng.StoryMentor"
PROJECT_NAME="编剧台.xcodeproj"
SCHEME_NAME="StoryMentor"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="Release"
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  CONFIGURATION="Debug"
fi
DERIVED_DATA="$ROOT_DIR/.build/StoryMentorRun-$CONFIGURATION"

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
STAGED_APP="/Applications/.$APP_NAME.installing.app"
BACKUP_APP="/Applications/.$APP_NAME.previous.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "build succeeded but app bundle is missing: $BUILT_APP" >&2
  exit 1
fi

BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist")"
if [[ "$BUILT_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "refusing to install unexpected bundle id: $BUILT_BUNDLE_ID" >&2
  exit 1
fi

# Recover a previous interrupted swap, then stage and verify the new bundle.
if [[ ! -d "$INSTALLED_APP" && -d "$BACKUP_APP" ]]; then
  /bin/mv "$BACKUP_APP" "$INSTALLED_APP"
elif [[ -d "$BACKUP_APP" ]]; then
  /bin/rm -rf "/Applications/.$APP_NAME.previous.app"
fi
/bin/rm -rf "/Applications/.$APP_NAME.installing.app"
/usr/bin/ditto "$BUILT_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

if [[ -d "$INSTALLED_APP" ]]; then
  /bin/mv "$INSTALLED_APP" "$BACKUP_APP"
fi
if ! /bin/mv "$STAGED_APP" "$INSTALLED_APP"; then
  if [[ -d "$BACKUP_APP" && ! -d "$INSTALLED_APP" ]]; then
    /bin/mv "$BACKUP_APP" "$INSTALLED_APP"
  fi
  exit 1
fi
/bin/rm -rf "/Applications/.$APP_NAME.previous.app"

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED_APP/Contents/Info.plist")"
INSTALLED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED_APP/Contents/Info.plist")"
echo "installed $APP_NAME $INSTALLED_VERSION ($INSTALLED_BUILD) at $INSTALLED_APP"

open_app() {
  /usr/bin/open -n "$INSTALLED_APP"
}

verify_process() {
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not launch" >&2
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
