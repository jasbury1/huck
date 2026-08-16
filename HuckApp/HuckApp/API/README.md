# API

This directory contains everything Huck uses to talk to Hacker News.

## Layers

```
HackerNewsAPI  ← the facade: the ONLY type the rest of the app calls
   │
   ├── Cache/StoryCache              (actor; caches stories behind the facade)
   ├── Services/AlgoliaAPIService    (historic data, whole comment threads, user search)
   ├── Services/FirebaseAPIService   (realtime story lists and items)
   │         │
   │         └── WebService          (generic URL fetch + JSON decode)
   └── Services/NewsYCService        (reverse-engineered HTML scraping: voting)
```

### `HackerNewsAPI` — the facade
The single entry point for the app. Exposes clean `static` async methods
(`getStoryIds`, `getComments`, `getUser`, `getUserStories`, `getUserComments`,
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
APIs don't offer (currently voting). It **scrapes HTML** rather than decoding JSON,
because HN embeds the per-user, per-item `auth` token that voting requires inside its
page markup. Requests are cookie-authenticated automatically via
`HTTPCookieStorage.shared`. All HTML parsing is localized to this file so an upstream
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
- Session state (the logged-in user derived from cookies) lives in
  `UserSession`, outside this directory.
