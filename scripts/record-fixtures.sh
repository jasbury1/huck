#!/usr/bin/env bash
#
# Re-records the fixtures UI tests replay, from the live Hacker News.
#
# Runs the FixtureRecording scenario (HuckUITests/FixtureRecording.swift) on a
# simulator with recording on, then replaces Huck/Fixtures.bundle with what it
# saved. Only anonymous, read-only responses are recorded — see
# RecordingTransport — so sign out in the simulator first if you'd like its
# news.ycombinator.com pages included.
#
#   scripts/record-fixtures.sh                # on the default simulator
#   DEVICE="iPhone 18 Pro" scripts/record-fixtures.sh

set -euo pipefail
cd "$(dirname "$0")/.."

device="${DEVICE:-iPhone 17}"
prefix="$(awk -F' *= *' '/^HUCK_BUNDLE_ID_PREFIX/ { print $2 }' Config/Base.xcconfig)"
bundle_id="${BUNDLE_ID:-$prefix.Huck}"
bundle="Huck/Fixtures.bundle"

echo "==> Recording on $device"
xcrun simctl boot "$device" 2>/dev/null || true
set -o pipefail
# xcodebuild passes TEST_RUNNER_-prefixed variables, unprefixed, to the tests.
TEST_RUNNER_HUCK_RECORD_FIXTURES=1 xcodebuild test \
    -project Huck.xcodeproj -scheme Huck \
    -destination "platform=iOS Simulator,name=$device" \
    -derivedDataPath build/DerivedData \
    -only-testing:HuckUITests/FixtureRecording \
    CODE_SIGNING_ALLOWED=NO \
    | { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }

recording="$(xcrun simctl get_app_container "$device" "$bundle_id" data)/Documents/FixtureRecording"
if [[ ! -s "$recording/manifest.jsonl" ]]; then
    echo "error: nothing was recorded at $recording" >&2
    exit 1
fi

echo "==> Replacing $bundle"
rm -rf "$bundle"
mkdir -p "$bundle"
cp -R "$recording/." "$bundle/"
echo "==> $(wc -l < "$bundle/manifest.jsonl" | tr -d ' ') responses, $(du -sh "$bundle" | cut -f1)"
