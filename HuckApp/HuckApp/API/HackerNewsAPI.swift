//
//  HackerNewsAPI.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation
import OSLog

typealias CookieHandler = (Result<HTTPCookie, Error>) -> Void

extension URLSession {
    static func nonRedirectingEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let delegate = RedirectBlocker()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

class RedirectBlocker: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Prevent re-direction by calling handler with nil
        print("Redirect blocked")
        completionHandler(nil)
    }
}

/// The single entry point the rest of the app uses to talk to Hacker News.
///
/// `HackerNewsAPI` is an abstraction layer over the underlying API services
/// (Algolia, Firebase, and the reverse-engineered auth endpoints). Callers
/// never interact with those services directly, and every method here returns
/// domain types (`Comment`, `User`, `UserComment`, …) rather than
/// service-specific response objects.
class HackerNewsAPI {
    static let baseUri = URL(string: "https://news.ycombinator.com/")!

    /// How many of a feed's leading stories to warm thumbnails for — roughly one
    /// screen's worth. Shared by the launch warm-up and the feed's own prefetch
    /// so they stay in agreement.
    static let thumbnailPrefetchWindow = 15

    // MARK: - Stories

    static func getStoryIds(filter: StoryFilter) async -> [Int] {
        await FirebaseAPIService.getStoryIdsAsync(filter: filter)
    }

    /// Returns a single story, served from the cache when available.
    ///
    /// Note: this returns `FirebaseStoryData` (a service type) rather than a
    /// domain type. `StoryModel` is the story's mapping layer and is the only
    /// intended caller; fully hiding this behind a domain type is deferred to
    /// the API-injection work.
    static func getStory(id: Int) async -> FirebaseStoryData? {
        await StoryCache.shared.story(id: id)
    }

    /// Warms the cache for the given story ids ahead of display.
    static func prefetchStories(ids: [Int]) async {
        await StoryCache.shared.prefetch(ids: ids)
    }

    /// Warms thumbnails for the given story ids ahead of display. Resolves each
    /// story's page URL from the cache (a fast hit once `prefetchStories` has
    /// run) and hands the link URLs to the thumbnail cache. Text posts, which
    /// have no URL, are skipped.
    static func prefetchThumbnails(ids: [Int]) async {
        var urls: [URL] = []
        for id in ids {
            guard let story = await StoryCache.shared.story(id: id),
                  let urlString = story.url,
                  let url = URL(string: urlString) else { continue }
            urls.append(url)
        }
        await ThumbnailCache.shared.prefetch(urls: urls)
    }

    // MARK: - Comments

    /// How many more comments Firebase must report than Algolia returned before we
    /// treat Algolia's index as stale. A small tolerance absorbs the harmless skew
    /// from deleted/dead comments, which the two sources count differently.
    private static let commentStalenessTolerance = 2

    /// Upper bound on concurrent Firebase `item` requests during a thread walk, so a
    /// large thread never fans out into hundreds of simultaneous requests.
    private static let maxConcurrentCommentFetches = 16

    /// Structured logging for the comment-source decision. Filter Console/Xcode by
    /// this category to see, per story, whether Algolia was served or a Firebase walk
    /// was taken and why.
    private static let commentLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HuckApp",
        category: "CommentFetch"
    )

    /// Which source to build a story's comment thread from, plus the counts behind the
    /// choice. Kept as a pure decision, separate from the fetching it drives, so the
    /// policy lives in one readable, testable place.
    private enum CommentFetchPlan {
        /// Algolia's indexed tree is complete enough to serve directly.
        case algolia(count: Int, descendants: Int?)
        /// Algolia has nothing for this story yet (unindexed, or indexed with no
        /// comments).
        case firebaseAlgoliaEmpty
        /// Algolia is missing enough comments that we walk the realtime tree instead.
        case firebaseStale(algoliaCount: Int, descendants: Int)
    }

    /// Decides how to source comments by comparing what Algolia returned against
    /// Firebase's whole-thread `descendants` total. `descendants` counts every nesting
    /// level, so it catches comments missing deep in the tree, not just new top-level
    /// replies. With no Firebase count to compare against, we trust Algolia.
    private static func planCommentFetch(algoliaCount: Int, descendants: Int?) -> CommentFetchPlan {
        if algoliaCount == 0 {
            return .firebaseAlgoliaEmpty
        }
        if let descendants, descendants - algoliaCount > commentStalenessTolerance {
            return .firebaseStale(algoliaCount: algoliaCount, descendants: descendants)
        }
        return .algolia(count: algoliaCount, descendants: descendants)
    }

    /// A stream of progressively-growing snapshots of a story's comment thread.
    ///
    /// Algolia returns the whole tree in one request and is the fast path, but its
    /// crawler lags HN by up to ~a minute, so a live story can come back missing its
    /// newest comments. We fetch the Algolia tree and the realtime Firebase story
    /// metadata together and compare against the story's `descendants` (its
    /// whole-thread comment total). When Algolia looks complete we emit it once and
    /// finish. When it's empty or stale we walk the realtime Firebase tree, emitting a
    /// fuller snapshot after each depth level so top-level comments appear within
    /// roughly one round trip while deeper replies fill in beneath them.
    ///
    /// Each yielded value is a complete, correctly pre-ordered list meant to *replace*
    /// the previous one; consumers just assign it.
    static func streamComments(for id: Int) -> AsyncStream<[Comment]> {
        AsyncStream { continuation in
            let task = Task {
                await produceComments(for: id) { snapshot in
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs the source decision and drives the emissions behind `streamComments`.
    private static func produceComments(for id: Int, emit: ([Comment]) -> Void) async {
        // The story is usually already warm in the cache from the feed, so reading it
        // for its `descendants` count costs nothing; run it alongside the Algolia fetch.
        async let storyRequest = StoryCache.shared.story(id: id)
        async let algoliaRequest = AlgoliaAPIService.getItemById(id: id)
        let story = await storyRequest
        let algoliaItem = await algoliaRequest

        var algoliaThread = [Comment]()
        if let children = algoliaItem?.children {
            for child in children {
                getChildComments(nestLevel: 0, itemData: child, comments: &algoliaThread)
            }
        }

        switch planCommentFetch(algoliaCount: algoliaThread.count, descendants: story?.descendants) {
        case let .algolia(count, descendants):
            let reported = descendants.map(String.init) ?? "unknown"
            commentLog.info("Comments[\(id, privacy: .public)]: serving \(count, privacy: .public) comments from Algolia (Firebase descendants: \(reported, privacy: .public)); index fresh")
            emit(algoliaThread)
            return
        case .firebaseAlgoliaEmpty:
            commentLog.info("Comments[\(id, privacy: .public)]: Algolia has no comments yet; streaming realtime Firebase tree")
        case let .firebaseStale(algoliaCount, descendants):
            commentLog.info("Comments[\(id, privacy: .public)]: Algolia stale (\(algoliaCount, privacy: .public) of \(descendants, privacy: .public) comments); streaming realtime Firebase tree")
            // Show Algolia's partial tree immediately for instant content; the Firebase
            // walk streams a fuller thread over it, wave by wave.
            emit(algoliaThread)
        }

        // Both Firebase fallbacks need the story's top-level `kids` to seed the walk.
        guard let story else {
            commentLog.warning("Comments[\(id, privacy: .public)]: Firebase story unavailable; serving \(algoliaThread.count, privacy: .public) Algolia comments instead")
            emit(algoliaThread)
            return
        }
        await streamFirebaseWalk(for: id, story: story, fallback: algoliaThread, emit: emit)
    }

    private static func getChildComments(nestLevel: Int, itemData: AlgoliaItemData, comments: inout [Comment]) {
        let comment = Comment(item: itemData)
        comment.nestingLevel = nestLevel
        comments.append(comment)
        if let children = itemData.children {
            for child in children {
                getChildComments(nestLevel: nestLevel + 1, itemData: child, comments: &comments)
            }
        }
    }

    /// Streams the comment thread from the realtime Firebase API.
    ///
    /// Firebase serves one item per request and only reveals a comment's children once
    /// it has been fetched, so the thread is loaded breadth-first: each depth level is
    /// fetched fully in parallel, and its children form the next level. This bounds the
    /// sequential round trips to the tree's *depth* rather than its size. After every
    /// level we re-flatten everything fetched so far into a correct pre-order snapshot
    /// and emit it, so comments appear progressively — top-level first, replies slotting
    /// in beneath their parents as deeper levels arrive.
    private static func streamFirebaseWalk(for id: Int, story: FirebaseStoryData, fallback: [Comment], emit: ([Comment]) -> Void) async {
        guard let rootKids = story.kids, !rootKids.isEmpty else {
            emit(fallback)
            return
        }

        var items = [Int: FirebaseCommentData]()
        var frontier = rootKids
        var depth = 0
        var latestCount = 0
        while !frontier.isEmpty {
            let level = await fetchComments(ids: frontier)
            items.merge(level) { _, new in new }

            // Emit a correctly pre-ordered snapshot of everything fetched so far.
            var snapshot = [Comment]()
            flattenFirebaseComments(ids: rootKids, nestLevel: 0, items: items, into: &snapshot)
            latestCount = snapshot.count
            emit(snapshot)

            // The next level is every live comment's children, kept in reading order.
            var next = [Int]()
            for commentId in frontier {
                guard let item = level[commentId],
                      item.deleted != true, item.dead != true,
                      let kids = item.kids else { continue }
                next.append(contentsOf: kids)
            }
            frontier = next
            depth += 1
        }

        // Guard against a degenerate walk (e.g. kids that all fail to load) leaving the
        // reader with less than the Algolia tree we already had.
        if latestCount < fallback.count {
            commentLog.warning("Comments[\(id, privacy: .public)]: Firebase walk yielded \(latestCount, privacy: .public) < Algolia's \(fallback.count, privacy: .public); serving Algolia instead")
            emit(fallback)
            return
        }
        commentLog.info("Comments[\(id, privacy: .public)]: Firebase walk complete — \(latestCount, privacy: .public) comments across \(depth, privacy: .public) levels")
    }

    /// Fetches the given comment ids concurrently with a bounded degree of parallelism,
    /// returning those that loaded keyed by id. Failed or missing ids are simply absent.
    private static func fetchComments(ids: [Int]) async -> [Int: FirebaseCommentData] {
        var results = [Int: FirebaseCommentData]()
        var iterator = ids.makeIterator()
        await withTaskGroup(of: FirebaseCommentData?.self) { group in
            // Seed the group up to the concurrency limit.
            var scheduled = 0
            while scheduled < maxConcurrentCommentFetches, let commentId = iterator.next() {
                group.addTask { await FirebaseAPIService.getCommentAsync(id: commentId) }
                scheduled += 1
            }
            // As each request finishes, backfill with the next pending id.
            while let result = await group.next() {
                if let result { results[result.id] = result }
                if let commentId = iterator.next() {
                    group.addTask { await FirebaseAPIService.getCommentAsync(id: commentId) }
                }
            }
        }
        return results
    }

    /// Walks the fetched Firebase items in pre-order (depth-first), assigning each a
    /// nesting level and dropping deleted/dead comments, to produce the flat shape the
    /// comment list renders.
    private static func flattenFirebaseComments(ids: [Int], nestLevel: Int, items: [Int: FirebaseCommentData], into comments: inout [Comment]) {
        for id in ids {
            guard let item = items[id], item.deleted != true, item.dead != true else { continue }
            comments.append(Comment(firebase: item, nestingLevel: nestLevel))
            if let kids = item.kids, !kids.isEmpty {
                flattenFirebaseComments(ids: kids, nestLevel: nestLevel + 1, items: items, into: &comments)
            }
        }
    }

    // MARK: - Users

    static func getUser(for username: String) async -> User? {
        guard let userdata = await AlgoliaAPIService.getUserData(username) else {
            return nil
        }
        return User(from: userdata)
    }

    static func getUserStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        await AlgoliaAPIService.getUserStoryIds(username: username, page: page)
    }

    static func getUserComments(username: String, page: Int = 0) async -> (comments: [UserComment], hasMore: Bool) {
        await AlgoliaAPIService.getUserComments(username: username, page: page)
    }

    /// The logged-in user's liked (upvoted) stories, most-recent first, for their
    /// own profile's "Liked" tab. HN only exposes this list for the authenticated
    /// user, so it always reads the current session's username and returns nothing
    /// when logged out. `page` is 0-based to match the other user feeds.
    static func getLikedStories(page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        guard let username = UserSession.shared?.username else { return ([], false) }
        // NewsYCService pages the /upvoted list 1-based.
        return await NewsYCService.upvotedStoryIds(username: username, page: page + 1)
    }

    // MARK: - Voting

    /// Upvotes a story on behalf of the logged-in user.
    static func upvoteStory(id: Int) async throws {
        try await vote(storyId: id, how: .up)
    }

    /// Removes the logged-in user's upvote from a story.
    static func unvoteStory(id: Int) async throws {
        try await vote(storyId: id, how: .unvote)
    }

    private static func vote(storyId: Int, how: NewsYCService.VoteAction) async throws {
        guard UserSession.shared != nil else { throw APIError.notLoggedIn }
        // The vote requires the item's per-user `auth` token, which only lives in
        // the item page's HTML, so fetch it first, then cast the vote.
        guard let voteAuth = await NewsYCService.voteAuth(forItem: storyId) else {
            throw APIError.missingAuthToken
        }
        try await NewsYCService.castVote(id: storyId, how: how, auth: voteAuth.auth)
    }

    /// The set of story ids the logged-in user has upvoted, read from the first
    /// `maxPages` of their `/upvoted` history. Bounded by design (see the upvoting
    /// proposal): recent votes are covered here, and individual older stories are
    /// corrected lazily when their vote `auth` token is fetched.
    static func fetchUpvotedStoryIds(maxPages: Int = 2) async -> Set<Int> {
        guard let username = UserSession.shared?.username else { return [] }
        var ids = Set<Int>()
        var page = 1
        while page <= maxPages {
            let result = await NewsYCService.upvotedStoryIds(username: username, page: page)
            ids.formUnion(result.ids)
            if !result.hasMore { break }
            page += 1
        }
        return ids
    }

    // MARK: - Favorites

    /// Favorites a story on behalf of the logged-in user.
    static func favoriteStory(id: Int) async throws {
        try await fave(storyId: id, un: false)
    }

    /// Removes the logged-in user's favorite from a story.
    static func unfavoriteStory(id: Int) async throws {
        try await fave(storyId: id, un: true)
    }

    private static func fave(storyId: Int, un: Bool) async throws {
        guard UserSession.shared != nil else { throw APIError.notLoggedIn }
        // Like voting, favoriting needs the item's per-user `auth` token from its
        // page HTML.
        guard let faveAuth = await NewsYCService.faveAuth(forItem: storyId) else {
            throw APIError.missingAuthToken
        }
        try await NewsYCService.castFave(id: storyId, un: un, auth: faveAuth.auth)
    }

    /// A user's favorited stories, most-recent first, paginated. Favorites are
    /// public on Hacker News, so this works for any `username`. `page` is 0-based to
    /// match the other user feeds.
    static func getFavoriteStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        // NewsYCService pages the /favorites list 1-based.
        await NewsYCService.favoriteStoryIds(username: username, page: page + 1)
    }

    // MARK: - Authentication

    // TODO: Eventually these will be able to pull dummy data with a mock API handler.
    static func login(username: String, password: String) async throws {
        var loginError: Error?
        try await requestLoginCookie(username: username, password: password) { result in
            switch result {
            case .success(let token):
                print("Storing cookie.")
                HTTPCookieStorage.shared.setCookies([token],
                                                    for: baseUri,
                                                    mainDocumentURL: nil)
            case let .failure(error):
                print("Will not store cookie. Failed to log in.")
                loginError = error
            }
        }
        if let loginError {
            throw loginError
        }
    }

    static func logout(username: String) {
        let cookies = readCookie(forURL: baseUri)
            .filter { $0.name == "user" && $0.value.contains(username) }
        print("User cookies: \(cookies)")
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private static func loginUri(username: String, password: String) -> URL {
        var components = URLComponents()
        components.path += "login"
        components.queryItems = [
            URLQueryItem(name: "acct", value: username), URLQueryItem(name: "pw", value: password),
        ]
        return components.url(relativeTo: baseUri)!
    }

    private static func requestLoginCookie(username: String, password: String, cookieHandler: @escaping CookieHandler) async throws {
        let session = URLSession.nonRedirectingEphemeralSession()
        let uri = loginUri(username: username, password: password)
        let request = URLRequest(url: uri)

        // Do not use request.httpMethod = "POST". It skips the redirect delegate
        // TODO: Move this all to web service
        let (_, response) = try await session.data(for: request, delegate: RedirectBlocker())
        guard let response = response as? HTTPURLResponse else {
            print("Bad response: \(response)")
            throw NetworkError.badResponse
        }
        let headerFields = response.allHeaderFields as! [String: String]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: baseUri)
        if let token = cookies.first(where: { $0.name == "user" }) {
            print("Success. Calling cookie handler")
            cookieHandler(.success(token))
        } else {
            print("Failure. Calling cookie handler")
            cookieHandler(.failure(APIError.loginFailed))
        }
    }
}
