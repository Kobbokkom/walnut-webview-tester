#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: WALNUT_SIGN_IDENTITY='Developer ID Application: …' $0 OUTPUT_DIRECTORY" >&2
    exit 1
fi

: "${WALNUT_SIGN_IDENTITY:?Set WALNUT_SIGN_IDENTITY to a Developer ID Application identity, or - for a local test.}"
if [[ $WALNUT_SIGN_IDENTITY == - && -n ${WALNUT_NOTARY_PROFILE:-} ]]; then
    echo 'Notarization requires a Developer ID Application signature.' >&2
    exit 1
fi

package=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$1"
output=$(cd "$1" && pwd)
scratch=$(mktemp -d -t walnut-agent-package)
trap 'rm -rf "$scratch"' EXIT

staging="$scratch/package"
app="$staging/Walnut Agent.app"
binary="$app/Contents/MacOS/walnut-agent"
mkdir -p "$app/Contents/MacOS" "$staging/skill"
binaries=()
for arch in arm64 x86_64; do
    build=(--package-path "$package" --scratch-path "$scratch/$arch" -c release --triple "$arch-apple-macosx")
    swift build "${build[@]}"
    binaries+=("$(swift build "${build[@]}" --show-bin-path)/walnut-agent")
done
xcrun lipo -create "${binaries[@]}" -output "$binary"
xcrun lipo "$binary" -verify_arch arm64 x86_64
chmod 755 "$binary"
install -m 644 "$package/../.agents/skills/walnut/SKILL.md" "$staging/skill/SKILL.md"

version=$("$binary" --version)
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'The executable did not report a valid release version.' >&2
    exit 1
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Walnut Agent</string>
    <key>CFBundleExecutable</key><string>walnut-agent</string>
    <key>CFBundleIdentifier</key><string>com.kobbokkom.walnut-agent</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Walnut Agent</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSBackgroundOnly</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

if [[ $WALNUT_SIGN_IDENTITY == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --sign "$WALNUT_SIGN_IDENTITY" --options runtime --timestamp "$app"
fi
codesign --verify --strict --all-architectures "$app"

if [[ -n ${WALNUT_NOTARY_PROFILE:-} ]]; then
    ditto -c -k --sequesterRsrc "$staging" "$scratch/notary.zip"
    xcrun notarytool submit "$scratch/notary.zip" --keychain-profile "$WALNUT_NOTARY_PROFILE" \
        --wait --output-format json > "$scratch/notary.json"
    if [[ $(plutil -extract status raw -o - "$scratch/notary.json") != Accepted ]]; then
        cat "$scratch/notary.json" >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
fi

asset="walnut-agent-$version-macos-universal.zip"
ditto -c -k --sequesterRsrc "$staging" "$scratch/$asset"
cp "$scratch/$asset" "$output/$asset"
(cd "$output" && shasum -a 256 "$asset" > "$asset.sha256")
printf '%s\n' "$output/$asset" "$output/$asset.sha256"
