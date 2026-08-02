# API

This directory contains everything Huck uses to talk to Hacker News.

## Layers

```
HackerNewsAPI  ← the facade: the ONLY type the rest of the app calls
   │
   ├── Services/AlgoliaAPIService    (historic data, whole comment threads, user search)
   └── Services/FirebaseAPIService   (realtime story lists and items)
             │
             └── WebService          (generic URL fetch + JSON decode)
```

### `HackerNewsAPI` — the facade
The single entry point for the app. Exposes clean `static` async methods
(`getStoryIds`, `getComments`, `getUser`, `getUserStories`, `getUserComments`,
`login`, `logout`). It picks the appropriate service, and it also owns the
reverse-engineered cookie-based auth against `news.ycombinator.com`.

**It always returns domain types, never a service's response object.**

### Services (`Services/`)
`AlgoliaAPIService` and `FirebaseAPIService` each wrap one upstream API. Each
service file also declares the `Codable` response structs it decodes, named by
source: `AlgoliaItemData`, `AlgoliaUserData`, `FirebaseStoryData`,
`FirebaseCommentData`. These structs are an implementation detail of the
service — they are not returned above the facade.

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

- Story fetching is cached: `StoryModel.fetchData()` reads through
  `StoryCache` (defined outside this directory), which fetches missing stories
  via `FirebaseAPIService`.
- Session state (the logged-in user derived from cookies) lives in
  `UserSession`, outside this directory.
