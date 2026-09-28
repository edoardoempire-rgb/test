#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required" >&2; exit 1; }
if [ "${SKIP_AIRLIFT_BUILD:-0}" != "1" ]; then
  "$ROOT/build-airlift.sh"
fi
xcodegen generate --spec project.real.yml
xcodebuild -project SkinBridge.xcodeproj -scheme SkinBridge -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
APP=$(find build/DerivedData/Build/Products -name 'SkinBridge.app' -type d | head -n 1)
test -n "$APP"
rm -rf build/Payload build/SkinBridge.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/SkinBridge.app
rm -rf build/Payload/SkinBridge.app/_CodeSignature build/Payload/SkinBridge.app/embedded.mobileprovision
(cd build && zip -qr SkinBridge.ipa Payload)
echo "$ROOT/build/SkinBridge.ipa"
