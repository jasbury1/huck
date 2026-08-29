# API

This directory contains everything Huck uses to talk to Hacker News.

## Layers

```
HackerNewsAPI  ← the facade: the ONLY type the rest of the app calls
   │
   ├── Cache/StoryCache              (actor; caches stories behind the facade)
   ├── Cache/CommentCache            (actor; caches whole comment threads, short TTL)
   ├── Services/AlgoliaAPIService    (historic data, whole comment threads, user search)
   ├── Services/FirebaseAPIService   (realtime story lists and items)
   │         │
   │         ├── WebService          (generic URL fetch + JSON decode)
   │         └── FirebaseThreadWalker(streams a comment thread in reading order)
   └── Services/NewsYCService        (reverse-engineered HTML scraping: voting, favorites)

`StoryCache` and `CommentCache` are both built on the generic `LRUCache` actor in
`Common/` (alongside other reusable building blocks like `MinHeap`).
```

### `HackerNewsAPI` — the facade
The single entry point for the app. Exposes clean `static` async methods
(`getStoryIds`, `streamComments`, `getUser`, `getUserStories`, `getUserComments`,
`login`, `logout`). It picks the appropriate service, and it also owns the
reverse-engineered cookie-based auth against `news.ycombinator.com`.

**It always returns domain types, never a service's response object.**

### Services (`Services/`)
`AlgoliaAPIService` and `FirebaseAPIService` each wrap one upstream JSON API. Each
service file also declares the `Codable` response structs it decodes, named by
source: `AlgoliaItemData`, `AlgoliaUserData`, `FirebaseStoryData`,
`FirebaseCommentData`. These structs are an implementation detail of the
service — they are not returned above the facade.

`NewsYCService` is the third category anticipated in `CLAUDE.md`: a
reverse-engineered handler for `news.ycombinator.com` itself, for actions the JSON
APIs don't offer (voting and favoriting, plus reading a user's `/upvoted` and
`/favorites` lists). It **scrapes HTML** rather than decoding JSON, because HN embeds
the per-user, per-item `auth` token that voting/favoriting requires inside its page
markup. Requests are cookie-authenticated automatically via `HTTPCookieStorage.shared`
(note a user's `/favorites` is public, so it works for any username; `/upvoted` is
private to its owner). All HTML parsing is localized to this file so an upstream
markup change is a one-file fix. Like the others, it stays below the facade.

### Domain types (`Models/`)
The types the app actually works with, decoupled from any single API:
- `Comment` (`@Observable`) — a comment in a thread, with `nestingLevel`
- `User` (`@Observable`) — a user profile
- `UserComment` — a comment shown on a user's profile
- `StoryModel` (`@Observable`) — a story, plus `StoryFilter` and `StoryType`

### Support
- `WebService` — low-level generic `downloadData<T: Codable>(fromURL:)`.
- `APIError` / `NetworkError` — error types.
- `PostAge` — relative-time formatting (`Date.ageString()`).
- `StringExtensions` — `normalizeHtmlText()`, converts HN's HTML to Markdown.

## Conventions

- **Views and models call `HackerNewsAPI` only.** They never touch a service
  or a `*Data` Codable directly.
- **Codables stay next to their service** and carry a source prefix
  (`Algolia…` / `Firebase…`).
- **Conversion from service data to domain types happens at or below the
  facade** (e.g. `Comment(item:)`, `User(from:)`).

## Notes

- Story fetching is cached behind the facade. `StoryModel.fetchData()` calls
  `HackerNewsAPI.getStory(id:)`, and startup warming goes through
  `HackerNewsAPI.prefetchStories(ids:)`. Both are backed by `Cache/StoryCache`,
  an `actor` that fetches missing stories via `FirebaseAPIService`. The cache
  coalesces concurrent requests for the same id into one fetch, prefetches in
  parallel with bounded concurrency, and bounds its size with LRU eviction.
  Nothing outside the API layer touches `StoryCache` directly.
- Comment sourcing is decided in `HackerNewsAPI.streamComments(for:)`, which yields
  progressively-growing snapshots of the thread. It fetches Algolia's whole-tree
  response and the realtime Firebase story together, then `planCommentFetch` compares
  Algolia's node count against the story's Firebase `descendants` (the whole-thread
  comment total). A complete Algolia tree is emitted once; when it's empty or stale
  (missing more than a small tolerance), the facade hands the story's `kids` to
  `FirebaseThreadWalker`. The walker streams the realtime tree with two separate
  policies: it *fetches* in pre-order priority (top of the page first, bounded
  concurrency) and it *reveals* only the contiguous fully-loaded prefix — so every
  snapshot strictly appends to the last and the list never reflows. Successive
  snapshots therefore only grow at the tail, which the view fades in. Which path is
  taken, and why, is logged under the `CommentFetch` category.
- Completed comment threads are cached in `CommentCache` (keyed by story id), so
  re-opening a post serves the thread in a single snapshot rather than re-hitting the
  APIs. Entries carry a short time-to-live because threads gain replies over time;
  once stale, the next open re-fetches. Only complete, non-empty threads are cached —
  a cancelled walk or an empty/failed load is left out so it can be retried.
- Session state (the logged-in user derived from cookies) lives in
  `UserSession`, outside this directory.
