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
    /// finish. When it's empty or stale we hand off to `FirebaseThreadWalker`, which
    /// streams the realtime tree in reading order — top comments first, the list only
    /// ever growing downward so it never reflows.
    ///
    /// Each yielded value is a complete, correctly pre-ordered list. Successive values
    /// only ever *append* to the previous one, so consumers can simply assign it.
    ///
    /// Completed threads are cached briefly (see `CommentCache`), so re-opening a post
    /// serves the thread in one snapshot instead of hitting the APIs again.
    static func streamComments(for id: Int) -> AsyncStream<[Comment]> {
        AsyncStream { continuation in
            let task = Task {
                if let cached = await CommentCache.shared.thread(for: id) {
                    commentLog.info("Comments[\(id, privacy: .public)]: served \(cached.count, privacy: .public) comments from cache")
                    continuation.yield(cached)
                } else {
                    let thread = await produceComments(for: id) { continuation.yield($0) }
                    // Cache only a real, complete result: skip empties (an empty thread
                    // or a failed load, so it can be retried) and cancelled walks, whose
                    // thread is only partial.
                    if !thread.isEmpty, !Task.isCancelled {
                        await CommentCache.shared.store(thread, for: id)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs the source decision and drives the emissions behind `streamComments`,
    /// returning the final, complete thread.
    private static func produceComments(for id: Int, emit: ([Comment]) -> Void) async -> [Comment] {
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
            return algoliaThread
        case .firebaseAlgoliaEmpty:
            commentLog.info("Comments[\(id, privacy: .public)]: Algolia has no comments yet; streaming realtime Firebase tree")
        case let .firebaseStale(algoliaCount, descendants):
            commentLog.info("Comments[\(id, privacy: .public)]: Algolia stale (\(algoliaCount, privacy: .public) of \(descendants, privacy: .public) comments); streaming realtime Firebase tree")
        }

        // The Firebase walk needs the story's top-level `kids` to seed the frontier.
        guard let story, let rootKids = story.kids, !rootKids.isEmpty else {
            commentLog.warning("Comments[\(id, privacy: .public)]: Firebase story unavailable; serving \(algoliaThread.count, privacy: .public) Algolia comments instead")
            emit(algoliaThread)
            return algoliaThread
        }

        let finalThread = await FirebaseThreadWalker(rootKids: rootKids).walk(emit: emit)

        // Safety net: if the realtime walk produced less than the Algolia tree we
        // already had (e.g. a mid-walk network failure), fall back to Algolia so the
        // reader isn't left with less than we could show.
        if finalThread.count < algoliaThread.count {
            commentLog.warning("Comments[\(id, privacy: .public)]: Firebase walk yielded \(finalThread.count, privacy: .public) < Algolia's \(algoliaThread.count, privacy: .public); serving Algolia instead")
            emit(algoliaThread)
            return algoliaThread
        }
        commentLog.info("Comments[\(id, privacy: .public)]: Firebase walk complete — \(finalThread.count, privacy: .public) comments")
        return finalThread
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

    /// A user's liked (upvoted) stories, most-recent first, for their own
    /// profile's "Liked" tab. Hacker News exposes `/upvoted` only to its owner, so
    /// `username` must be the signed-in user for this to return anything. `page`
    /// is 0-based to match the other user feeds. `nil` means the page couldn't be
    /// fetched, as distinct from an empty page.
    static func getLikedStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool)? {
        // NewsYCService pages the /upvoted list 1-based.
        await NewsYCService.upvotedStoryIds(username: username, page: page + 1)
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
        guard hasAuthCookie else { throw APIError.notLoggedIn }
        // The vote requires the item's per-user `auth` token, which only lives in
        // the item page's HTML, so fetch it first, then cast the vote.
        guard let voteAuth = await NewsYCService.voteAuth(forItem: storyId) else {
            throw APIError.missingAuthToken
        }
        try await NewsYCService.castVote(id: storyId, how: how, auth: voteAuth.auth)
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
        guard hasAuthCookie else { throw APIError.notLoggedIn }
        // Like voting, favoriting needs the item's per-user `auth` token from its
        // page HTML.
        guard let faveAuth = await NewsYCService.faveAuth(forItem: storyId) else {
            throw APIError.missingAuthToken
        }
        try await NewsYCService.castFave(id: storyId, un: un, auth: faveAuth.auth)
    }

    /// A user's favorited stories, most-recent first, paginated. Favorites are
    /// public on Hacker News, so this works for any `username`. `page` is 0-based to
    /// match the other user feeds. `nil` means the page couldn't be fetched, as
    /// distinct from an empty page.
    static func getFavoriteStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool)? {
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

    /// Whether a credential exists to send at all. This layer asks the cookie jar
    /// directly rather than `UserSession`: the cookie *is* the credential, and
    /// keeping the check here means the API stays usable from any isolation
    /// context. Who is signed in — as opposed to whether anyone is — is the
    /// session's business, and reaches this layer as a `username` parameter.
    private static var hasAuthCookie: Bool {
        readCookie(forURL: baseUri).contains { $0.name == "user" }
    }

    static func logout(username: String) {
        let cookies = readCookie(forURL: baseUri)
            .filter { $0.name == "user" && $0.value.contains(username) }
        print("User cookies: \(cookies)")
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    /// Hacker News only evaluates credentials that arrive in a form POST body —
    /// a GET with `?acct=…&pw=…` is ignored and simply re-renders the login
    /// form, which reads as a rejected password. Percent-encoded to the
    /// unreserved set, because `URLComponents` would leave `+`, `&` and `=`
    /// intact and a password containing any of them would corrupt the body.
    private static func loginFormBody(username: String, password: String) -> Data {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func encoded(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
        }
        return Data("acct=\(encoded(username))&pw=\(encoded(password))&goto=news".utf8)
    }

    /// Hacker News serves its reCAPTCHA challenge instead of checking the
    /// password when the login POST doesn't look like it came from a browser —
    /// the app's own descriptive User-Agent is enough to trigger it. This is
    /// only sent on the login request; the scraping requests in `NewsYCService`
    /// keep identifying themselves as Huck.
    private static let loginUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func requestLoginCookie(username: String, password: String, cookieHandler: @escaping CookieHandler) async throws {
        let session = URLSession.nonRedirectingEphemeralSession()

        // TODO: Move this all to web service
        var request = URLRequest(url: URL(string: "login", relativeTo: baseUri)!)
        request.httpMethod = "POST"
        request.httpBody = loginFormBody(username: username, password: password)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(loginUserAgent, forHTTPHeaderField: "User-Agent")

        // The redirect must stay blocked: a successful login is a 302 carrying
        // the `user` cookie, and following it would drop the `Set-Cookie` header
        // we're here for (the session deliberately doesn't store cookies itself).
        let (data, response) = try await session.data(for: request, delegate: RedirectBlocker())
        guard let response = response as? HTTPURLResponse else {
            print("Bad response: \(response)")
            throw NetworkError.badResponse
        }
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
            if let name = entry.key as? String, let value = entry.value as? String {
                fields[name] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: baseUri)
        if let token = cookies.first(where: { $0.name == "user" }) {
            print("Success. Calling cookie handler")
            cookieHandler(.success(token))
        } else {
            // No cookie means either a rejected password ("Bad login") or the
            // captcha wall; they need different advice, so tell them apart.
            let body = String(data: data, encoding: .utf8) ?? ""
            let error: APIError = body.contains("Validation required")
                ? .loginValidationRequired
                : .loginFailed
            print("Failure. Calling cookie handler: \(error)")
            cookieHandler(.failure(error))
        }
    }
}
