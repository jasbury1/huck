# API Layer Refactor Proposal

**Status:** Proposed — awaiting approval
**Date:** 2026-08-01
**Goal:** Establish a robust, extensible, clean API architecture before adding new features.

## Assessment: what's actually messy

| Problem | Evidence |
|---|---|
| **Abstraction is leaky/unenforced** | Views call service functions *directly*, bypassing any facade: `StoryFeedView`, `StoryTextView`, `ContentView` call `getStoryIdsAsync`; `UserView` calls `AlgoliaAPIService.getUserStoryIds/getUserComments` directly |
| **Global free functions everywhere** | `login`, `logout`, `getComments`, `getUser`, `getChildComments` (in `HackerNewsAPI.swift`), `getStoryIdsAsync`, `getStoryAsync`, `getCommentAsync` (in `FirebaseAPIService.swift`), `fetchStory` (in `StoryCache.swift`) all float at file scope |
| **Service-specific Codable leaks to UI** | `UserCommentResult` is defined in `AlgoliaAPIService` and used as `@State` directly in `UserView`. This is exactly the leak we want to stop |
| **Duplication** | `fetchStory` (StoryCache) and `getStoryAsync` (Firebase) and `FirebaseAPIService.topStoriesRequest` are three ways to hit the same endpoint |
| **Two error types** | `NetworkError` and `APIError` overlap with no clear split |
| **Dead/placeholder code** | `FirebaseAPIService` struct body is unused (`// TODO: Finish using this class`); `getCommentAsync`/`CommentData` appear unused |
| **Concurrency hazard** | `StoryCache` is a `class` singleton mutating a `[Int:StoryData]` dictionary from async contexts — its own TODO admits it isn't thread-safe |
| **Awkward login flow** | `login(...)` is `async` but *also* takes a `cookieHandler` completion closure — mixing two concurrency styles for one operation |

## The three original proposals — verdict

**1. Move Codable types next to their service + rename by source — Agree.**
`ItemData` → `AlgoliaItemData`, `UserData` → `AlgoliaUserData`, `StoryData` → `FirebaseStoryData`, `CommentData` → `FirebaseCommentData`. Keep them as `private`/`fileprivate` (or at least internal) *inside* the service file so they physically can't leak. Note `UserCommentResult` is a service-return struct pretending to be a domain type — it should become a proper domain model or be mapped to one.

**2. `HackerNewsAPI` as the single facade — Strongly agree, but go further.**
Right now `HackerNewsAPI` is a `class` doing *only* login/logout, while the comment/user/story fetches are loose globals beside it. The facade should own **all** of it, and — critically — the services should become `internal`/`private` to the module so views *cannot* call them directly (fixing the leaks in `UserView` etc.). This is the biggest lever.

**3. Facade returns only domain classes, never service Codables — Agree, this is the core principle.**
We already do this for `User`/`Comment`. Extend it so `getUserComments` returns a domain type, story feeds return `StoryModel`, etc. No `AlgoliaItemData`/`FirebaseStoryData`/`UserCommentResult` should appear above the API layer.

## Additional recommendations

- **Make the facade an `actor` (or `@MainActor` + `actor` cache).** It naturally fixes the `StoryCache` thread-safety TODO. `StoryCache` should become an `actor` and live *behind* the facade — `StoryModel.fetchData()` currently reaches into `StoryCache` directly, another leak.
- **Introduce a protocol (`HackerNewsService`) for the facade.** The existing TODO wants a mock/dummy handler for previews and tests — a protocol makes that clean and satisfies dependency inversion. Inject it via SwiftUI `@Environment`.
- **Collapse the two error enums** into one `APIError` with a `.network(...)` case; keep it `LocalizedError`.
- **Normalize service naming**: drop the `Async` suffix (all are async), verb-consistent (`fetchStoryIds`, `fetchStory`, `fetchItem`).
- **Modernize `login`**: make it pure `async throws -> HTTPCookie` and drop the `cookieHandler` closure. Move the raw HTTP into `WebService`, as the existing `// TODO: Move this all to web service` already notes.
- **`WebService`**: make it a stateless `enum`/`struct` with a shared `JSONDecoder` rather than a `class` instantiated per call.

## Proposed target structure

```
API/
  HackerNewsAPI.swift        // the facade: actor, conforms to HackerNewsService protocol
  HackerNewsService.swift    // protocol (enables mock/preview impl)
  WebService.swift           // low-level transport + JSON decode
  APIError.swift             // single error type
  Services/
    AlgoliaAPIService.swift  // + AlgoliaItemData, AlgoliaUserData, Algolia*Response (all private)
    FirebaseAPIService.swift // + FirebaseStoryData, FirebaseCommentData (all private)
    AuthService.swift        // login/logout/cookies (split out of the facade file)
  Models/                    // domain layer — the ONLY types views see
    StoryModel.swift  Comment.swift  User.swift  UserComment.swift  PostAge.swift
  Cache/
    StoryCache.swift         // actor, lives behind the facade
```

## Migration plan (each phase compiles independently)

1. Rename + relocate the Codable types into their service files as private; fix references.
2. Consolidate errors; convert `WebService` to stateless.
3. Introduce `HackerNewsService` protocol + fold all globals into the `HackerNewsAPI` facade (actor). Map `UserCommentResult` → a domain `UserComment`.
4. Repoint all views/models to go through the facade only; make services non-public. Move `StoryCache` behind the facade and make it an `actor`.
5. Modernize `login` to pure async; inject the facade via `@Environment`.

## Open decisions

- **Scope of first pass:** full refactor (all 5 phases) vs. structural only (1–3) vs. just the leaks (1 & 4). *Recommendation: full refactor.*
- **View injection:** `@Environment` + protocol (recommended, enables mocks/previews) vs. shared singleton.
