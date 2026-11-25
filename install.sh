#!/bin/sh
# Builds writestuff and installs it to /Applications.
set -e
cd "$(dirname "$0")/app"
flutter build macos --release --config-only
cd macos
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES FLUTTER_TARGET=lib/main.dart \
  -derivedDataPath ../build/macos -quiet
if pgrep -f "/Applications/writestuff.app" >/dev/null; then
  echo "Quit writestuff first, then run this again." >&2
  exit 1
fi
rm -rf /Applications/writestuff.app
ditto ../build/macos/Build/Products/Release/writestuff.app /Applications/writestuff.app
echo "Installed /Applications/writestuff.app"
