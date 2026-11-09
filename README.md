# Huck

A Hacker News client for iPhone and iPad, built with SwiftUI.

Huck reads stories and comments through the Algolia and official Firebase Hacker News APIs. For what those APIs don't offer (signing in, voting, favoriting, commenting, submitting), it talks to `news.ycombinator.com` directly.

Named after my family's dog, Huck.

## Requirements

- Xcode 27.2 (pinned in [`.xcode-version`](.xcode-version))
- iOS 27.1 or later
- [Homebrew](https://brew.sh), for the lint and format tools

## Getting started

```sh
git clone https://github.com/jasbury1/huck.git
cd huck
make bootstrap      # installs SwiftFormat, SwiftLint, xcbeautify; creates Config/Local.xcconfig
open Huck.xcodeproj
```

Then run the **Huck** scheme. `make help` lists the command-line equivalents.

## Configuration

Build settings live in [`Config/`](Config/), not in the project file:

| File | Applies to |
|---|---|
| `Base.xcconfig` | Every target: signing team, deployment target, Swift settings |
| `App.xcconfig` | The app: bundle ID, version, Info.plist keys, feature switches |
| `Debug.xcconfig` / `Release.xcconfig` | The app, per configuration |
| `HuckTests.xcconfig` / `HuckUITests.xcconfig` | The test targets |
| `Local.xcconfig` | You alone (git ignores it). Overrides everything above. |

Feature switches such as iCloud sync and a hard posting kill switch are explained in `App.xcconfig`, and copied (commented out) in `Local.xcconfig.example`. Swift reads them only through `BuildConfiguration`.

## Project layout

```
Huck/
├── App/            Entry point, root view, sign-in session, build configuration
├── Features/       One folder per feature: Feed, Story, Thread, Compose,
│                   Account, Search, Collections, Settings, Debug
├── Components/     Reusable views shared across features
├── Networking/     The HackerNewsAPI facade, its services and caches, domain models
├── Stores/         App-wide state that persists: interactions, recently viewed
├── Formatting/     Turning HN's HTML, dates, and counts into display text
├── Common/         Generic building blocks: LRUCache, MinHeap, AsyncSemaphore
├── Resources/      Assets, app icon, string catalog, privacy manifest
└── Preview Content/  Assets for SwiftUI previews only
HuckTests/          Unit tests (Swift Testing), mirroring Huck/
HuckUITests/        UI tests (XCTest)
Config/             xcconfig files and entitlements
docs/               Architecture notes, decision records, proposals
```

Each feature folder holds that feature's views and the models only it uses. Code shared by two or more features moves to `Components/`, `Stores/`, or `Formatting/`.

## Architecture

- **The rest of the app talks to Hacker News only through `HackerNewsAPI`.** It picks Algolia (history, whole threads, search), Firebase (live rankings), or `news.ycombinator.com` (anything that writes), and caches behind its facade. See [`Huck/Networking/README.md`](Huck/Networking/README.md).
- **Swift 6 language mode, main actor by default.** Types that do background work opt out with `nonisolated` or are `actor`s.
- **Observation (`@Observable`) throughout**, with one owner per piece of state. See [decision 0001](docs/decisions/0001-story-state-ownership.md).

More in [`docs/`](docs/).

## Testing and linting

```sh
make test       # unit tests
make test-ui    # UI tests (offline, over recorded fixtures)
make lint       # SwiftFormat + SwiftLint checks, as CI runs them
make format     # fix what can be fixed automatically
```

## CI and releases

- **GitHub Actions** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) lints and runs the unit and UI tests on every pull request and on every push to `main`. The UI tests replay recorded responses, so CI never touches Hacker News; re-record them with `make record-fixtures`.
- **Xcode Cloud** builds archives for TestFlight and the App Store. Its workflows are configured in App Store Connect; the repository's hook scripts are in [`ci_scripts/`](ci_scripts/). Xcode Cloud sets the build number, so bump only `MARKETING_VERSION` in `App.xcconfig` for a release.

## License

Huck is free software, licensed under the [GNU General Public License v3.0](LICENSE).
