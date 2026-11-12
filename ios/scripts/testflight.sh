#!/usr/bin/env bash
# Build Drizon for iOS and upload it to TestFlight. Run on a Mac:
#
#   ./ios/scripts/testflight.sh
#
# Needs: Xcode signed in to the Apple Developer team WSH6T8F59M (Xcode ▸
# Settings ▸ Accounts), and an app record for bundle id com.oye.oye in App
# Store Connect. To upload without an Xcode login (e.g. CI), set an App Store
# Connect API key instead:
#   ASC_KEY_ID=…  ASC_ISSUER_ID=…  ASC_KEY_PATH=/path/AuthKey_XXXX.p8
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

# Embedded Python + yt-dlp (first run, or when missing).
if [ ! -d ios/Python.xcframework ]; then
  ./ios/scripts/setup_python.sh
fi

flutter pub get

# Every TestFlight upload needs a new build number; a timestamp always grows.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
echo "→ Building build $BUILD_NUMBER"
flutter build ipa --release --build-number "$BUILD_NUMBER"

AUTH=()
if [ -n "${ASC_KEY_ID:-}" ]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH")
fi

echo "→ Uploading to App Store Connect"
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ios/ExportOptions-TestFlight.plist \
  -exportPath build/ios/testflight \
  -allowProvisioningUpdates "${AUTH[@]}"

echo
echo "Uploaded build $BUILD_NUMBER. It appears in TestFlight after Apple finishes processing (usually 5–30 min)."
