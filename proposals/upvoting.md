# Upvoting Proposal

**Status:** Proposed — awaiting approval
**Date:** 2026-08-15
**Goal:** Let users upvote (and un-vote) stories from within Huck, reflect that state
in the UI, persist it, and keep it in sync with votes made outside the app.

## The constraint that shapes everything: how HN voting actually works

There is no official JSON write API, so this is the "custom reverse-engineered API"
case anticipated in `CLAUDE.md`. The mechanics:

- **Casting a vote** is a GET to
  `news.ycombinator.com/vote?id=<ID>&how=up&auth=<TOKEN>` (`how=un` to undo),
  authenticated by the `user` cookie we already store in `HTTPCookieStorage.shared`.
- **The `auth` token is the catch.** It is a per-user, per-item hash that HN only
  exposes inside the vote link in **page HTML**. It cannot be constructed — it must
  be scraped. Our app currently fetches everything as JSON, so we have no HTML on
  hand to harvest it from. A vote therefore requires first fetching the item's HTML
  to extract its `auth` token (and, conveniently, its current vote state).
- **Bulk upvote history** lives at `news.ycombinator.com/upvoted?id=<username>`
  (paginated HTML, logged-in only) — this is our drift source.

This introduces a small **HTML-scraping service** — the third API category the
project anticipated. Cookies attach automatically because `URLSession.shared` uses
`HTTPCookieStorage.shared`.

## Decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| **Persistence** | Per-username `Codable` struct saved as JSON in Application Support | Minimal, no schema/migrations, trivially extensible to saved/hidden. Can migrate to SwiftData later if it grows. |
| **Drift reconciliation** | Bounded + lazy per-item | Sync only the first 1–2 pages of `/upvoted` at launch/refresh (covers recent votes); correct anything else for free using the `alreadyUpvoted` flag parsed when fetching an item's `auth` token. Cheapest, respects the API. |
| **Un-voting** | Included | Toggle the orange arrow off. Nearly free once the token flow exists. |

## Component breakdown (mapped to the existing layers)

### 1. New scraping service — `Services/NewsYCService.swift`
Peer of `AlgoliaAPIService` / `FirebaseAPIService`; stays below the facade.
- `voteAuth(forItem id:) async -> (auth: String, alreadyUpvoted: Bool)?` — fetch
  `item?id=` HTML, parse the vote link.
- `castVote(id:how:auth:) async throws` — issue the vote GET.
- `upvotedStoryIds(username:page:) async -> (ids: [Int], hasMore: Bool)` — scrape
  `/upvoted`.
- Parsing uses native `Scanner`/regex against the known link patterns (no SwiftSoup
  dependency — keeps us native, and we only need a couple of tokens). Response
  structs stay in this file per the API-layer conventions.

### 2. Facade additions — `HackerNewsAPI`
Still the only type views/stores call.
- `upvoteStory(id:) async throws` / `unvoteStory(id:) async throws` — orchestrates
  "get token → cast vote", returns domain results.
- `fetchUpvotedStoryIds() async -> Set<Int>` — resolves the current user, pages
  `/upvoted` (bounded), returns ids.

### 3. Generalized interaction-state store — `Models/InteractionStore.swift`
The piece that makes future saved/hidden state clean.
- App-level `@Observable` class injected via `.environment`, holding
  `[Int: StoryInteraction]` where `StoryInteraction` is a small struct
  `{ isUpvoted, isSaved, isHidden }` (only `isUpvoted` implemented now; the rest are
  placeholders proving the shape generalizes).
- **Why separate from `StoryModel`:** the same story appears as *different*
  `StoryModel` instances across the feed, the comments view, and profiles (each view
  creates its own). Interaction state is cross-cutting and must be one source of
  truth keyed by id — so it cannot live on the per-view model. This store is where
  optimistic updates, network confirmation, and drift reconciliation all write, and
  what every arrow observes.
- Exposes `func toggleUpvote(_ story: StoryModel) async` — takes the `StoryModel` so
  it can apply the optimistic score ±1 and roll it back on failure, while flipping
  its own `isUpvoted` flag.

### 4. Persistence — `Models/InteractionPersistence.swift`
Loads/saves a per-username `Codable` struct as JSON in Application Support:
```swift
struct PersistedInteractions: Codable {
    var upvoted: Set<Int>
    var saved: Set<Int>
    var hidden: Set<Int>
}
```
Only `upvoted` is used now; `saved`/`hidden` ship as empty sets so adding them later
needs no migration.

### 5. Drift reconciliation
On app launch and on feed pull-to-refresh (logged-in only): call
`fetchUpvotedStoryIds()`, overwrite the store's upvoted set, persist. Plus a free
per-item correction: when we fetch an item's HTML for its `auth` token, its
`alreadyUpvoted` flag corrects that one story immediately.

### 6. UI wiring
- Arrow color: `StoryCellView` and `StoryTextView` read
  `store.interaction(for: id).isUpvoted` and tint the arrow `.orange` when true,
  `.gray` otherwise.
- The three existing stubs (cell arrow button, trailing-swipe "Upvote", text-view
  arrow) all funnel into `store.toggleUpvote(...)`.
- Not-logged-in → route to login instead of voting.
- Optimistic: flip color + score instantly, revert on thrown error.

## Data flow — the upvote tap

```
Arrow tap
  → store.toggleUpvote(story)
      → optimistic: isUpvoted = true, score += 1
      → HackerNewsAPI.upvoteStory(id)
          → NewsYCService.voteAuth(forItem:) (HTML fetch)
          → NewsYCService.castVote(id:how:auth:)
      → success: keep + persist
      → failure: revert isUpvoted and score
```

## Files touched

| File | Change |
|---|---|
| `Services/NewsYCService.swift` | **New** — HTML scraping: `voteAuth`, `castVote`, `upvotedStoryIds` |
| `Models/InteractionStore.swift` | **New** — `@Observable` store + `StoryInteraction` + `toggleUpvote` |
| `Models/InteractionPersistence.swift` | **New** — JSON load/save to Application Support |
| `API/HackerNewsAPI.swift` | Facade methods: `upvoteStory`, `unvoteStory`, `fetchUpvotedStoryIds` |
| `HuckAppApp.swift` / `ContentView.swift` | Create + inject the store; kick off launch drift sync |
| `Views/StoryViews/StoryCellView.swift` | Arrow color from store; funnel tap into `toggleUpvote` |
| `Views/StoryViews/StoryTextView.swift` | Arrow color from store; funnel tap into `toggleUpvote` |
| `Views/StoryViews/StoryFeedView.swift` | Swipe "Upvote" → `toggleUpvote`; refresh-triggered drift sync |

## Phasing

1. `NewsYCService` + facade methods — verify against a real logged-in account (the
   riskiest part; the `auth`-token HTML parsing needs confirming against live markup).
2. `InteractionStore` + persistence + environment injection (no drift yet).
3. Wire the arrows: color, tap, optimistic score ±1 with rollback, login gate.
   Includes toggle/un-vote.
4. Drift reconciliation on launch + refresh.

## Risks / notes

- **Phase 1 needs a live logged-in session** to confirm the exact `auth`-token and
  `/upvoted` markup. Parse defensively and test against a real account early.
- HTML markup can change without notice; scraping is inherently more brittle than the
  JSON APIs. Keep parsing localized to `NewsYCService` so a markup change is a
  one-file fix.
