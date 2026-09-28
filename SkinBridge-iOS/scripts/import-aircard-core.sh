#!/bin/sh
set -eu
SOURCE="${1:?usage: import-aircard-core.sh /path/to/AirCard-iOS}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test -f "$SOURCE/LICENSE"
test -d "$SOURCE/AirliftFFI.xcframework"
mkdir -p "$ROOT/Vendor" "$ROOT/Upstream"
cp -R "$SOURCE/AirliftFFI.xcframework" "$ROOT/Vendor/AirliftFFI.xcframework"
cp "$SOURCE/LICENSE" "$ROOT/Vendor/AirCard-iOS-LICENSE"
cp "$SOURCE/ios-app/PairingController.swift" "$ROOT/Upstream/PairingController.swift"
cp "$SOURCE/ios-app/Utilities.swift" "$ROOT/Upstream/Utilities.swift"
cp "$SOURCE/ios-app/NetworkStatus.swift" "$ROOT/Upstream/NetworkStatus.swift"
echo "Imported minimal AirCard-iOS boundary. Generate with: xcodegen generate --spec project.real.yml"
