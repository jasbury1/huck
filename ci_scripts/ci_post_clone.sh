#!/bin/sh
#
# Xcode Cloud runs this after cloning, before resolving packages or building.
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
#
# Xcode Cloud manages build numbers itself for the archives it uploads, so
# nothing here touches CURRENT_PROJECT_VERSION.

set -eu

# Lint only on pull-request builds; archives for TestFlight shouldn't be held
# up by a style nit already caught by GitHub CI.
if [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
    brew install swiftformat swiftlint
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    make lint
fi
