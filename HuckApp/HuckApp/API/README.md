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
   └── Services/NewsYCService        (reverse-engineered HTML scraping: voting, favorites,
                                      commenting)

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
APIs don't offer (voting, favoriting and commenting, plus reading a user's `/upvoted`
and `/favorites` lists). It **scrapes HTML** rather than decoding JSON, because HN
embeds the tokens these actions require inside its page markup: a per-user, per-item
`auth` token for voting/favoriting, and a per-user, per-parent `hmac` in the comment
form. Requests are cookie-authenticated automatically via `HTTPCookieStorage.shared`
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
- `FormBody` — strict percent-encoding for the `x-www-form-urlencoded` bodies the
  `news.ycombinator.com` endpoints take (login, commenting).

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
- Posting a comment (`HackerNewsAPI.postComment(parentId:storyId:text:)`) is a
  two-step exchange, like voting. HN's comment form carries a per-user, per-parent
  `hmac` it checks as a CSRF token, so the service first GETs the form — `/reply`,
  which is a few hundred bytes, in preference to the story's whole `/item` page —
  and scrapes *every* hidden input it declares rather than naming them one by one,
  then POSTs them back to `/comment` with the text. A top-level comment and a reply
  are the same request against a different `parent` (the story, or the comment being
  answered). Success is signalled by a 302 and refusal by a 200 that re-renders the
  form, so the POST goes through a non-redirecting session in order to tell them
  apart. A successful post invalidates *both* the story's `CommentCache` thread and
  its `StoryCache` entry — the latter because the stale `descendants` count is what
  `planCommentFetch` consults to decide whether Algolia's tree is complete.
- **Recovering a posted comment's id** (`findPostedCommentId(username:parentID:)`)
  is **lazy, and usually never happens at all**. Neither the comment form nor its
  redirect reports the id HN assigned (the redirect only echoes back the `goto` we
  sent), and recovering one costs two reads against a mirror that trails the site.
  But the id is needed for exactly one thing: replying to a comment the reader
  posted in the same sitting. So `postComment` doesn't look it up, and
  `CommentFetcher` keeps only what a later lookup would need; the lookup fires from
  `CommentFetcher.resolveItemID(for:)` at the moment a reply is sent, and the result
  is kept on the comment. Deferring it also makes it *more* reliable — by the time
  someone has read their comment and decided to answer it, the mirror lag that
  would have defeated an immediate lookup has passed, so the first attempt lands.
  The lookup reads the author's `submitted` list (newest-first, so their latest
  comment is at the front), then *confirms* it by fetching the item and checking
  `by` and `parent`. That check is essential: a miss doesn't return nothing, it
  returns the author's **previous** comment, and without it we'd hand back a real
  id belonging to a different comment and a reply aimed at it would land in an
  unrelated thread. Two short retries cover an immediate ask; failing that, the
  reply surfaces `APIError.unknownReplyTarget` with the draft intact.
- Session state (the logged-in user derived from cookies) lives in `UserSession`,
  outside this directory, and this layer does not read it. *Whether* a credential
  exists is answered from the cookie jar directly (`hasAuthCookie`), so the API
  stays callable from any isolation context; *who* is signed in arrives as a
  `username` parameter from the caller.
