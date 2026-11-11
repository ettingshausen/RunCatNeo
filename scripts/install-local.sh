#!/usr/bin/env zsh
# Builds, signs, and installs RunCatNeo locally.
#
# The app is signed with a stable Apple Development identity on purpose: an
# ad-hoc signed app gets a cdhash-based designated requirement, so every
# rebuild invalidates its Input Monitoring (TCC) grant. A certificate-backed
# signature keeps the grant across builds.

set -euo pipefail
cd "$(dirname "$0")/.."

identity="${RUNCAT_SIGN_IDENTITY:-Apple Development: ettingshausen@outlook.com (HXJVLST8RM)}"
derivedData="/tmp/rnc-dd"
configuration="${1:-Release}"

xcodebuild build \
    -project RunCatNeo.xcodeproj \
    -scheme RunCatNeo \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derivedData" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

app="$derivedData/Build/Products/$configuration/RunCatNeo.app"
codesign --force --deep --sign "$identity" \
    --entitlements RunCatNeo/RunCatNeo.entitlements \
    "$app"

codesign --verify "$app"

kill $(pgrep -f '/Applications/RunCatNeo.app/Contents/MacOS') 2>/dev/null || true
sleep 1
rm -rf /Applications/RunCatNeo.app
cp -R "$app" /Applications/RunCatNeo.app
xattr -cr /Applications/RunCatNeo.app
open /Applications/RunCatNeo.app

echo "Installed and launched: $(codesign -d --requirements - /Applications/RunCatNeo.app 2>&1 | tail -1)"
