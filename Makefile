# Huck — common development commands. Run `make help` for the list.
#
# CI calls these same targets, so a green `make lint test` locally means a
# green build on GitHub.

PROJECT     := Huck.xcodeproj
SCHEME      := Huck
DESTINATION ?= platform=iOS Simulator,name=iPhone 17
DERIVED     := build/DerivedData

XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
               -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

# Pipe through xcbeautify when it's installed, for readable output.
FORMAT_LOG  := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify" || echo "")

.DEFAULT_GOAL := help
.PHONY: help bootstrap build test test-ui record-fixtures lint format clean

help: ## Show this list
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Install tools and set up local config (run once after cloning)
	@scripts/bootstrap.sh

build: ## Build the app for the simulator
	set -o pipefail && $(XCODEBUILD) build CODE_SIGNING_ALLOWED=NO $(FORMAT_LOG)

test: ## Run the unit tests
	set -o pipefail && $(XCODEBUILD) test -only-testing:HuckTests CODE_SIGNING_ALLOWED=NO $(FORMAT_LOG)

test-ui: ## Run the UI tests (offline, over the recorded fixtures)
	set -o pipefail && $(XCODEBUILD) test -only-testing:HuckUITests CODE_SIGNING_ALLOWED=NO $(FORMAT_LOG)

record-fixtures: ## Re-record the UI tests' fixtures from live Hacker News
	@scripts/record-fixtures.sh

lint: ## Check formatting and lint (what CI runs)
	swiftformat --lint .
	swiftlint lint --quiet

format: ## Reformat the code and apply lint autocorrections
	swiftformat .
	swiftlint lint --fix --quiet

clean: ## Remove build output
	rm -rf build
