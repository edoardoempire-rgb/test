#!/bin/bash
set -euo pipefail

if [ "$#" -eq 5 ]; then
  INPUT_IPA="$1"
  CERTIFICATE_P12="$2"
  APP_MOBILEPROVISION="$3"
  TUNNEL_MOBILEPROVISION="$3"
  SIGNING_KEYCHAIN="$4"
  OUTPUT_IPA="$5"
elif [ "$#" -eq 6 ]; then
  INPUT_IPA="$1"
  CERTIFICATE_P12="$2"
  APP_MOBILEPROVISION="$3"
  TUNNEL_MOBILEPROVISION="$4"
  SIGNING_KEYCHAIN="$5"
  OUTPUT_IPA="$6"
else
  echo "usage: sign-ipa.sh INPUT_IPA CERTIFICATE_P12 APP_MOBILEPROVISION [TUNNEL_MOBILEPROVISION] KEYCHAIN OUTPUT_IPA" >&2
  exit 64
fi

test -f "$INPUT_IPA"
test -f "$CERTIFICATE_P12"
test -f "$APP_MOBILEPROVISION"
test -f "$TUNNEL_MOBILEPROVISION"

OUTPUT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$OUTPUT_IPA")" && pwd)"
OUTPUT_IPA="$OUTPUT_DIRECTORY/$(basename -- "$OUTPUT_IPA")"
SIGNING_WORK_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$SIGNING_WORK_DIRECTORY"' EXIT

ditto -x -k "$INPUT_IPA" "$SIGNING_WORK_DIRECTORY"
APP_PATH="$(find "$SIGNING_WORK_DIRECTORY/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
test -n "$APP_PATH"

SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | sed -n '1s/.*"\(.*\)"/\1/p')"
test -n "$SIGNING_IDENTITY"

sign_bundle() {
  BUNDLE_PATH="$1"
  PROFILE_PATH="$2"
  LABEL="$3"
  PROFILE_PLIST="$SIGNING_WORK_DIRECTORY/$LABEL-profile.plist"
  ENTITLEMENTS_PLIST="$SIGNING_WORK_DIRECTORY/$LABEL-entitlements.plist"

  cp "$PROFILE_PATH" "$BUNDLE_PATH/embedded.mobileprovision"
  security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$PROFILE_PLIST" > "$ENTITLEMENTS_PLIST"

  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE_PATH/Info.plist")"
  PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST")"
  PROFILE_PATTERN="${PROFILE_APP_ID#*.}"
  case "$BUNDLE_ID" in
    $PROFILE_PATTERN) ;;
    *)
      echo "Provisioning profile pattern $PROFILE_PATTERN does not authorize $BUNDLE_ID" >&2
      exit 65
      ;;
  esac

  codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_PLIST" --timestamp=none "$BUNDLE_PATH"
}

TUNNEL_PATH="$(find "$APP_PATH/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | head -n 1 || true)"
if [ -n "$TUNNEL_PATH" ]; then
  sign_bundle "$TUNNEL_PATH" "$TUNNEL_MOBILEPROVISION" "tunnel"
fi
sign_bundle "$APP_PATH" "$APP_MOBILEPROVISION" "app"

codesign --verify --deep --strict "$APP_PATH"
rm -f "$OUTPUT_IPA"
(cd "$SIGNING_WORK_DIRECTORY" && ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA")
echo "$OUTPUT_IPA"
