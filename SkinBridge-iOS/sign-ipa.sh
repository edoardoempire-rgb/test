#!/bin/bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: sign-ipa.sh INPUT_IPA CERTIFICATE_P12 MOBILEPROVISION KEYCHAIN OUTPUT_IPA" >&2
  exit 64
fi

INPUT_IPA="$1"
CERTIFICATE_P12="$2"
MOBILEPROVISION="$3"
SIGNING_KEYCHAIN="$4"
OUTPUT_IPA="$5"

test -f "$INPUT_IPA"
test -f "$CERTIFICATE_P12"
test -f "$MOBILEPROVISION"

OUTPUT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$OUTPUT_IPA")" && pwd)"
OUTPUT_IPA="$OUTPUT_DIRECTORY/$(basename -- "$OUTPUT_IPA")"
SIGNING_WORK_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$SIGNING_WORK_DIRECTORY"' EXIT

ditto -x -k "$INPUT_IPA" "$SIGNING_WORK_DIRECTORY"
APP_PATH="$(find "$SIGNING_WORK_DIRECTORY/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
test -n "$APP_PATH"

cp "$MOBILEPROVISION" "$APP_PATH/embedded.mobileprovision"
security cms -D -i "$MOBILEPROVISION" > "$SIGNING_WORK_DIRECTORY/profile.plist"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$SIGNING_WORK_DIRECTORY/profile.plist" > "$SIGNING_WORK_DIRECTORY/entitlements.plist"

APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$SIGNING_WORK_DIRECTORY/profile.plist")"
PROFILE_BUNDLE_ID="${PROFILE_APP_ID#*.}"
if [ "$PROFILE_BUNDLE_ID" != "*" ] && [ "$PROFILE_BUNDLE_ID" != "$APP_BUNDLE_ID" ]; then
  echo "Provisioning profile is for $PROFILE_BUNDLE_ID, but the app is $APP_BUNDLE_ID" >&2
  exit 65
fi

SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | sed -n '1s/.*"\(.*\)"/\1/p')"
test -n "$SIGNING_IDENTITY"

codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$SIGNING_WORK_DIRECTORY/entitlements.plist" --timestamp=none "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

rm -f "$OUTPUT_IPA"
(cd "$SIGNING_WORK_DIRECTORY" && ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA")
echo "$OUTPUT_IPA"
