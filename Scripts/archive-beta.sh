#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Keep build products outside file-provider folders to avoid FinderInfo signing errors.
beta_root="${POCKET_CANVAS_BUILD_ROOT:-$HOME/Library/Developer/Xcode/PocketCanvas}"
mkdir -p "$beta_root"
xcodebuild -project QwenOffline.xcodeproj -scheme QwenOffline \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$beta_root/DerivedData" \
  -archivePath "$beta_root/PocketCanvas.xcarchive" \
  -allowProvisioningUpdates PRODUCT_BUNDLE_IDENTIFIER=com.buberlo.pocketcanvas archive
