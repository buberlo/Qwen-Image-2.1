#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo 'Install full Xcode with iOS support and complete its first-run setup.' >&2
  exit 1
fi
if [ ! -f Signing.xcconfig ]; then cp Signing.xcconfig.example Signing.xcconfig; fi
if [ ! -d QwenOffline.xcodeproj ]; then xcodegen generate; fi
xcodebuild -project QwenOffline.xcodeproj -scheme QwenOffline \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
