#!/usr/bin/env bash
#
# One-time setup after cloning: installs the command-line tools the Makefile
# and CI use, and creates an untracked Local.xcconfig for personal overrides.

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required: https://brew.sh" >&2
    exit 1
fi

echo "==> Installing tools"
brew bundle --file=Brewfile

if [[ ! -f Config/Local.xcconfig ]]; then
    echo "==> Creating Config/Local.xcconfig (git ignores it)"
    cp Config/Local.xcconfig.example Config/Local.xcconfig
fi

required_xcode="$(cat .xcode-version)"
current_xcode="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if [[ "$current_xcode" != "$required_xcode" ]]; then
    echo "warning: this project expects Xcode $required_xcode; xcodebuild is Xcode $current_xcode" >&2
fi

echo "==> Done. Open Huck.xcodeproj, or run \`make help\`."
