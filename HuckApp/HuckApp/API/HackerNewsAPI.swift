//
//  HackerNewsAPI.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

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

    static func getComments(for id: Int) async -> [Comment] {
        var commentThread = [Comment]()
        guard let rootItem = await AlgoliaAPIService.getItemById(id: id) else {
            return commentThread
        }
        if let children = rootItem.children {
            for child in children {
                getChildComments(nestLevel: 0, itemData: child, comments: &commentThread)
            }
        }
        return commentThread
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
