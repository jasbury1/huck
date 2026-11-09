# Networking

This directory contains everything Huck uses to talk to Hacker News.

## Layers

```
HackerNewsService  ← the protocol the rest of the app calls, in domain types only
   │
HackerNewsAPI      ← its implementation: one instance owns everything below
   │
   ├── Cache/StoryCache              (actor; caches stories behind the facade, 1000 max)
   ├── Cache/StoryListCache          (actor; the main feeds' ranked id lists, short TTL)
   ├── Cache/CommentCache            (actor; caches whole comment threads, short TTL)
   ├── Cache/CommentScoreCache       (actor; the reader's own comment scores, scraped from /threads in bulk, short TTL)
   ├── Cache/NewUserCache, ThumbnailCache, TrendingReposCache
   ├── Services/AlgoliaAPIService    (historic data, whole comment threads, user search)
   ├── Services/FirebaseAPIService   (realtime story lists and items)
   │         └── FirebaseThreadWalker(streams a comment thread in reading order)
   ├── Services/NewsYCService        (reverse-engineered HTML scraping: voting, favorites,
   │                                  commenting)
   │
   └── Transport/HTTPTransport       (the one seam to the network; every service sends
             │                         through the instance's transport)
             ├── URLSessionTransport (live: the real network, counted in APIMetrics)
             ├── FixtureTransport    (debug: replays Fixtures.bundle, never the network)
             └── RecordingTransport  (debug: live, saving anonymous reads as fixtures)

`StoryCache` and `CommentCache` are both built on the generic `LRUCache` actor in
`Common/` (alongside other reusable building blocks like `MinHeap`).
```

### `HackerNewsService` and `HackerNewsAPI` — the facade
`HackerNewsService` is everything the app asks of Hacker News (`getStoryIds`,
`streamComments`, `getUser`, `getUserStories`, `getUserComments`, `login`,
`logout`, …). `HackerNewsAPI` implements it: an instance is built over one
`HTTPTransport`, creates its services and caches over that transport, picks the
appropriate service per call, and owns the reverse-engineered cookie-based auth
against `news.ycombinator.com`.

**It always returns domain types, never a service's response object.**

Which instance the app runs is chosen once at launch (`LaunchConfiguration`) and
handed down through the environment as `\.hackerNews`:
- views read it with `@Environment(\.hackerNews)`;
- app-wide stores (`UserSession`, `InteractionStore`) are given it when created;
- models a view drives (`StoryFeed`, `PaginatedFeed`, `StoryModel`,
  `CommentFetcher`, `PollModel`) take it as a `using:` argument on the calls that
  need it — they're often built in a view's `init`, before the environment exists.

`HackerNewsAPI.live` is the network-backed instance, and the environment's default.

### Services (`Services/`)
`AlgoliaAPIService` and `FirebaseAPIService` each wrap one upstream JSON API. Each
is a value holding the transport it sends through, split into request building
(static URL builders), parsing (static functions over a decoded response, or over
HTML for `NewsYCService`) and fetching (instance methods that combine the two).
The static halves are pure, so they're testable on their own. Each service file
also declares the `Codable` response structs it decodes, named by
source: `AlgoliaItemData`, `AlgoliaUserData`, `FirebaseStoryData`,
`FirebaseCommentData`. These structs are an implementation detail of the
service — they are not returned above the facade.

`NewsYCService` is the third category anticipated in `CLAUDE.md`: a
reverse-engineered handler for `news.ycombinator.com` itself, for actions the JSON
APIs don't offer (voting, favoriting, commenting and deleting comments, plus reading a user's `/upvoted`
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
- `StoryModel` (`@Observable`) — a story, plus `FeedKind` and `StoryType`

### Support
- `HTTPTransport` — `data(for:kind:endpoint:)`, plus `json(from:)`, which fetches
  and decodes off the main actor. `RequestKind` picks the session behaviour a
  request needs (shared cookies, thumbnail timeouts, no-redirect writes, login).
- `APIMetrics` — per-source, per-endpoint request counts for the Debug tab.
  `URLSessionTransport` sends through `URLSession.countedData(for:)` rather than
  `data(for:)`, which is where the counting happens.
- `AsyncSemaphore` (in `Common/`) — LIFO limiter for scroll-driven fetches
  (thumbnails, own-comment scores).
- `APIError` / `NetworkError` — error types.
- `PostAge` and `String+HTMLNormalization` (in `Formatting/`) — relative-time
  formatting (`Date.ageString()`) and `normalizeHtmlText()`, which converts HN's
  HTML to Markdown.
- `FormBody` — strict percent-encoding for the `x-www-form-urlencoded` bodies the
  `news.ycombinator.com` endpoints take (login, commenting).

## Conventions

- **Views and models call `HackerNewsService` only**, through the instance they
  were given. They never touch a service, a cache or a `*Data` Codable directly,
  and never construct `HackerNewsAPI` themselves — only `LaunchConfiguration`
  and tests do.
- **Codables stay next to their service** and carry a source prefix
  (`Algolia…` / `Firebase…`).
- **Conversion from service data to domain types happens at or below the
  facade** (e.g. `Comment(item:)`, `User(from:)`).

## Notes

- Story fetching is cached behind the facade. `StoryModel.fetchData(using:)` calls
  `getStory(id:)`, which maps Firebase's item to a domain `StoryDetails`, and startup warming goes through
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

## Testing without the network

`FixtureTransport` answers every request from `Huck/Fixtures.bundle`: about 1,400
real Algolia, Firebase and news.ycombinator.com responses, recorded from the live
site. Requests are matched by method and URL (query order ignored, time bounds on
`created_at_i` wildcarded); anything unrecorded gets a 404 and a log line under the
`Fixtures` category, and writes and logins are refused without being sent.

- **Unit tests** build `HackerNewsAPI(transport: FixtureTransport(store: .bundled!))`
  directly (see `HackerNewsAPIFixtureTests`), so the real services, parsing and
  caches run against real responses.
- **UI tests** launch the app with `-HuckFixtures` (`XCUIApplication.launchedWithFixtures()`).
- **Re-recording**: `make record-fixtures` runs the `FixtureRecording` UI scenario
  on a simulator with `-HuckRecordFixtures`, then replaces the bundle. Only
  anonymous `GET`s to the three Hacker News hosts are kept — never writes, logins,
  thumbnails, or anything fetched while signed in. When a UI test starts visiting
  somewhere new, add the trip to `FixtureRecording` and re-record.

All of this is debug-only: the fixture code is compiled out of Release builds, and
`Release.xcconfig` excludes `Fixtures.bundle`.
