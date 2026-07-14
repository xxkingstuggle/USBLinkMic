#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/mac-native/USBLinkMicNative.xcodeproj"
DERIVED_DATA="${TMPDIR%/}/USBLinkMicReleaseDerivedData"
DESTINATION="${1:-/Applications/USB LinkMic.app}"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/USB LinkMic.app"
BACKUP_APP=""

xcodebuild \
  -project "$PROJECT" \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

codesign --force --deep --sign - "$BUILT_APP"
codesign --verify --deep --strict "$BUILT_APP"

if [[ -e "$DESTINATION" ]]; then
  BACKUP_APP="${TMPDIR%/}/USBLinkMic-previous-$$.app"
  pkill -x "USB LinkMic" 2>/dev/null || true
  mv "$DESTINATION" "$BACKUP_APP"
fi

restore_previous() {
  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" && ! -e "$DESTINATION" ]]; then
    mv "$BACKUP_APP" "$DESTINATION"
  fi
}
trap restore_previous ERR

ditto "$BUILT_APP" "$DESTINATION"

if [[ -e "$DESTINATION/Contents/MacOS/USB LinkMic.debug.dylib" ]]; then
  echo "refusing to install a Debug build" >&2
  mv "$DESTINATION" "${TMPDIR%/}/USBLinkMic-rejected-$$.app"
  restore_previous
  exit 1
fi

plutil -p "$DESTINATION/Contents/Info.plist" \
  | grep -E 'CFBundleShortVersionString|CFBundleVersion'
file "$DESTINATION/Contents/MacOS/USB LinkMic"
codesign --verify --deep --strict "$DESTINATION"

trap - ERR
if [[ "${USBLINKMIC_NO_LAUNCH:-0}" != "1" ]]; then
  open "$DESTINATION"
fi

echo "installed=$DESTINATION"
if [[ -n "$BACKUP_APP" ]]; then
  echo "previous=$BACKUP_APP"
fi
