//
//  HackerNewsAPI.swift
//  Huck
//
//  Created by James Asbury on 12/26/25.
//

import Foundation
import OSLog
import UIKit

typealias CookieHandler = (Result<HTTPCookie, Error>) -> Void

/// Where an item is read in the app: a story's thread, scrolled to one of its
/// comments when the item is a comment.
struct ThreadLocation: Hashable, Sendable {
    let storyID: Int
    let commentID: Int?
}

/// What Hacker News did with a submission it accepted.
enum SubmissionOutcome: Sendable {
    /// A new post was created. Its id is `nil` if it couldn't be confirmed in
    /// time — the post exists, but there's nowhere certain to open.
    case posted(storyID: Int?)
    /// The link had already been posted, so HN counted the submission as an
    /// upvote on the existing story instead of creating a new one.
    case alreadySubmitted(storyID: Int)
}

/// The single entry point the rest of the app uses to talk to Hacker News.
///
/// `HackerNewsAPI` is an abstraction layer over the underlying API services
/// (Algolia, Firebase, and the reverse-engineered auth endpoints). Callers
/// never interact with those services directly, and every method here returns
/// domain types (`Comment`, `User`, `UserComment`, …) rather than
/// service-specific response objects.
///
/// An instance is the whole API layer: its services, built over one
/// `HTTPTransport`, and the caches in front of them. The live app runs one over
/// the network; fixture builds and tests run one over recorded responses.
final class HackerNewsAPI: HackerNewsService {
    /// The instance that talks to the real Hacker News.
    static let live = HackerNewsAPI(transport: URLSessionTransport())

    private let algolia: AlgoliaAPIService
    private let firebase: FirebaseAPIService
    private let newsYC: NewsYCService
    private let transport: any HTTPTransport

    private let storyCache: StoryCache
    private let storyLists: StoryListCache
    private let commentCache = CommentCache()
    private let commentScores: CommentScoreCache
    private let newUserCache: NewUserCache
    private let thumbnails: ThumbnailCache
    private let trendingRepos: TrendingReposCache

    init(transport: any HTTPTransport) {
        self.transport = transport
        algolia = AlgoliaAPIService(transport: transport)
        firebase = FirebaseAPIService(transport: transport)
        newsYC = NewsYCService(transport: transport)
        storyCache = StoryCache(firebase: firebase)
        storyLists = StoryListCache(firebase: firebase)
        commentScores = CommentScoreCache(newsYC: newsYC)
        newUserCache = NewUserCache(newsYC: newsYC)
        thumbnails = ThumbnailCache(transport: transport)
        trendingRepos = TrendingReposCache(algolia: algolia, storyLists: storyLists)
    }

    nonisolated static let baseUri = URL(string: "https://news.ycombinator.com/")!

    /// How many of a feed's leading stories to warm thumbnails for — roughly one
    /// screen's worth. Shared by the launch warm-up and the feed's own prefetch
    /// so they stay in agreement.
    static let thumbnailPrefetchWindow = 15

    // MARK: - Stories

    /// A feed's ranked story ids, served from `StoryListCache` while fresh.
    func getStoryIds(kind: FeedKind) async -> [Int] {
        await storyLists.ids(for: kind)
    }

    /// Like `getStoryIds(kind:)`, but always fetches the current ranking —
    /// for pull-to-refresh, where a cached list would defeat the point.
    func refreshStoryIds(kind: FeedKind) async -> [Int] {
        await storyLists.refresh(kind)
    }

    /// The story ids of the GitHub repos Hacker News is talking about, best
    /// first — see `TrendingRepos` for how they're ranked. Served from
    /// `TrendingReposCache` while fresh.
    func getTrendingRepoStoryIds() async -> [Int] {
        await trendingRepos.storyIDs()
    }

    /// The feeds warmed at launch, most likely to be opened first.
    private static let launchFeeds: [FeedKind] = [.topStories, .bestStories, .newStories, .showStories]

    /// How many stories the launch warm-up may cache in all, short of the
    /// cache's capacity so browsing afterwards has room before anything warmed
    /// is evicted.
    private static let launchWarmBudget = StoryCache.capacity * 9 / 10

    /// Warms the main feeds at launch so opening any of them is immediate:
    /// their id lists, then every feed's first screen (details and thumbnails),
    /// then as much of the rest as the budget allows.
    ///
    /// Top Stories goes first throughout — it's the feed most likely to be
    /// opened, and opened soonest. Its first screen's details are fetched
    /// before anyone else's, and its thumbnails are loaded to completion before
    /// the other feeds' are even queued: the thumbnail queue serves the newest
    /// request first, so queuing them together would put Top's at the back.
    /// That thumbnail chain runs alongside the story warming rather than ahead
    /// of it, so a slow image host can't hold up the rest.
    ///
    /// The deeper pass takes the feeds a rank at a time — every feed's 16th
    /// story, then every feed's 17th, and so on — rather than one feed after
    /// another, so if the budget runs out, or the app is closed partway, each
    /// feed is covered to the same depth instead of one completely and the last
    /// not at all. Stories in more than one feed are fetched once.
    func warmLaunchFeeds() async {
        // The lists themselves: four requests, all at once.
        let lists = await withTaskGroup(of: (Int, [Int]).self) { group in
            for (index, kind) in Self.launchFeeds.enumerated() {
                group.addTask { await (index, self.getStoryIds(kind: kind)) }
            }
            var lists = Array(repeating: [Int](), count: Self.launchFeeds.count)
            for await (index, ids) in group { lists[index] = ids }
            return lists
        }

        let firstScreens = Self.interleavedByRank(lists.map { Array($0.prefix(Self.thumbnailPrefetchWindow)) })
        let topFirstScreen = Array(lists[0].prefix(Self.thumbnailPrefetchWindow))
        let otherFirstScreens = firstScreens.filter { !topFirstScreen.contains($0) }

        await prefetchStories(ids: topFirstScreen)
        async let thumbnails: Void = {
            await loadThumbnails(ids: topFirstScreen)
            await prefetchThumbnails(ids: otherFirstScreens)
        }()

        await prefetchStories(ids: otherFirstScreens)
        await prefetchStories(ids: Array(Self.interleavedByRank(lists).prefix(Self.launchWarmBudget)))

        // The first screens were cached first, which makes them the first to
        // go when the cache fills. Reading them again — all hits, no requests —
        // marks them most recently used, so they're the last instead.
        await prefetchStories(ids: firstScreens)
        await thumbnails
    }

    /// Merges lists rank by rank — every list's first item, then every list's
    /// second — dropping ids already taken from an earlier list.
    private static func interleavedByRank(_ lists: [[Int]]) -> [Int] {
        var seen = Set<Int>()
        var merged: [Int] = []
        for rank in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where rank < list.count && seen.insert(list[rank]).inserted {
                merged.append(list[rank])
            }
        }
        return merged
    }

    /// Returns a single story, served from the cache when available.
    func getStory(id: Int) async -> StoryDetails? {
        await storyCache.story(id: id).map(StoryDetails.init(firebase:))
    }

    /// Warms the cache for the given story ids ahead of display.
    func prefetchStories(ids: [Int]) async {
        await storyCache.prefetch(ids: ids)
    }

    /// The titles of the given stories, keyed by id. Missing stories are
    /// fetched first through the cache's bounded prefetch, so a feed the
    /// launch warm-up has already covered costs no requests at all.
    func storyTitles(ids: [Int]) async -> [Int: String] {
        await storyCache.prefetch(ids: ids)
        var titles: [Int: String] = [:]
        for id in ids {
            if let story = await storyCache.story(id: id) {
                titles[id] = story.title
            }
        }
        return titles
    }

    /// Warms thumbnails for the given story ids ahead of display. Resolves each
    /// story's page URL from the cache (a fast hit once `prefetchStories` has
    /// run) and hands the link URLs to the thumbnail cache. Text posts, which
    /// have no URL, are skipped.
    func prefetchThumbnails(ids: [Int]) async {
        await thumbnails.prefetch(urls: thumbnailURLs(for: ids))
    }

    /// A linked page's thumbnail — its Open Graph image, else its favicon —
    /// downsampled for a cell, or `nil` if neither could be loaded.
    func thumbnail(for pageURL: URL) async -> UIImage? {
        await thumbnails.thumbnail(for: pageURL)
    }

    /// Like `prefetchThumbnails(ids:)`, but returns only once every thumbnail
    /// has loaded (or failed), for when what follows should wait on them.
    private func loadThumbnails(ids: [Int]) async {
        let urls = await thumbnailURLs(for: ids)
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { [thumbnails] in _ = await thumbnails.thumbnail(for: url) }
            }
        }
    }

    /// The linked pages of the given stories, in order. Text posts, which have
    /// no URL, are skipped.
    private func thumbnailURLs(for ids: [Int]) async -> [URL] {
        var urls: [URL] = []
        for id in ids {
            guard let story = await storyCache.story(id: id),
                  let urlString = story.url,
                  let url = URL(string: urlString) else { continue }
            urls.append(url)
        }
        return urls
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
        subsystem: Bundle.main.bundleIdentifier ?? "Huck",
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
    /// Drops the cached thread and story for `id`, so the next reads fetch them
    /// fresh. Both go together: the cached story's `descendants` is what
    /// `Self.planCommentFetch` checks Algolia's tree against, so a stale story left
    /// in place would have a fresh fetch confidently serve a stale tree.
    ///
    /// For when the thread is known to have changed — the reader commented, or
    /// deleted a comment — or the reader has asked for it, by pulling to refresh.
    func invalidateThread(for id: Int) async {
        await commentCache.invalidate(id)
        await storyCache.invalidate(id)
    }

    func streamComments(for id: Int) -> AsyncStream<[Comment]> {
        AsyncStream { continuation in
            let task = Task {
                if let cached = await commentCache.thread(for: id) {
                    Self.commentLog.info("Comments[\(id, privacy: .public)]: served \(cached.count, privacy: .public) comments from cache")
                    continuation.yield(cached)
                } else {
                    let thread = await produceComments(for: id) { continuation.yield($0) }
                    // Cache only a real, complete result: skip empties (an empty thread
                    // or a failed load, so it can be retried) and cancelled walks, whose
                    // thread is only partial.
                    if !thread.isEmpty, !Task.isCancelled {
                        await commentCache.store(thread, for: id)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs the source decision and drives the emissions behind `streamComments`,
    /// returning the final, complete thread.
    private func produceComments(for id: Int, emit: ([Comment]) -> Void) async -> [Comment] {
        // The story is usually already warm in the cache from the feed, so reading it
        // for its `descendants` count costs nothing; run it alongside the Algolia fetch.
        async let storyRequest = storyCache.story(id: id)
        async let algoliaRequest = algolia.getItemById(id: id)
        let story = await storyRequest
        let algoliaItem = await algoliaRequest

        var algoliaThread = [Comment]()
        if let children = algoliaItem?.children {
            for child in children {
                Self.getChildComments(nestLevel: 0, itemData: child, comments: &algoliaThread)
            }
        }

        switch Self.planCommentFetch(algoliaCount: algoliaThread.count, descendants: story?.descendants) {
        case let .algolia(count, descendants):
            let reported = descendants.map(String.init) ?? "unknown"
            Self.commentLog.info("Comments[\(id, privacy: .public)]: serving \(count, privacy: .public) comments from Algolia (Firebase descendants: \(reported, privacy: .public)); index fresh")
            emit(algoliaThread)
            return algoliaThread
        case .firebaseAlgoliaEmpty:
            Self.commentLog.info("Comments[\(id, privacy: .public)]: Algolia has no comments yet; streaming realtime Firebase tree")
        case let .firebaseStale(algoliaCount, descendants):
            Self.commentLog.info("Comments[\(id, privacy: .public)]: Algolia stale (\(algoliaCount, privacy: .public) of \(descendants, privacy: .public) comments); streaming realtime Firebase tree")
        }

        // The Firebase walk needs the story's top-level `kids` to seed the frontier.
        guard let story, let rootKids = story.kids, !rootKids.isEmpty else {
            Self.commentLog.warning("Comments[\(id, privacy: .public)]: Firebase story unavailable; serving \(algoliaThread.count, privacy: .public) Algolia comments instead")
            emit(algoliaThread)
            return algoliaThread
        }

        let finalThread = await FirebaseThreadWalker(rootKids: rootKids, firebase: firebase).walk(emit: emit)

        // Safety net: if the realtime walk produced less than the Algolia tree we
        // already had (e.g. a mid-walk network failure), fall back to Algolia so the
        // reader isn't left with less than we could show.
        if finalThread.count < algoliaThread.count {
            Self.commentLog.warning("Comments[\(id, privacy: .public)]: Firebase walk yielded \(finalThread.count, privacy: .public) < Algolia's \(algoliaThread.count, privacy: .public); serving Algolia instead")
            emit(algoliaThread)
            return algoliaThread
        }
        Self.commentLog.info("Comments[\(id, privacy: .public)]: Firebase walk complete — \(finalThread.count, privacy: .public) comments")
        return finalThread
    }

    /// Where an item is read: the thread it belongs to, and the comment within
    /// it if it's a comment. `nil` if the item doesn't exist or couldn't be
    /// fetched.
    ///
    /// For when all that's known is an id, as with a link to Hacker News. The
    /// Firebase lookup comes first because it's the lightest read and settles a
    /// story at once. A comment's story then comes from Algolia, which records
    /// it however deep the comment sits; only if Algolia hasn't indexed it yet
    /// do we climb its parents one Firebase request at a time.
    func threadLocation(ofItem id: Int) async -> ThreadLocation? {
        guard let item = await firebase.getItemHeaderAsync(id: id) else { return nil }
        // An option is read as part of its poll.
        if item.type == "pollopt", let poll = item.poll {
            return ThreadLocation(storyID: poll, commentID: nil)
        }
        guard item.type == "comment" else {
            return ThreadLocation(storyID: id, commentID: nil)
        }
        if let storyID = await algolia.getItemById(id: id)?.storyId {
            return ThreadLocation(storyID: storyID, commentID: id)
        }
        var parent = item.parent
        while let ancestorID = parent, !Task.isCancelled {
            guard let ancestor = await firebase.getItemHeaderAsync(id: ancestorID) else { return nil }
            if ancestor.type != "comment" {
                return ThreadLocation(storyID: ancestorID, commentID: id)
            }
            parent = ancestor.parent
        }
        return nil
    }

    private static func getChildComments(nestLevel: Int, itemData: AlgoliaItemData, comments: inout [Comment]) {
        let comment = Comment(item: itemData)
        comment.nestingLevel = nestLevel
        comments.append(comment)
        if let children = itemData.children {
            for child in children {
                Self.getChildComments(nestLevel: nestLevel + 1, itemData: child, comments: &comments)
            }
        }
    }

    /// The commenters on a story whose accounts Hacker News marks as new, so
    /// their names can be shown the way HN shows them. One read of the story's
    /// page covers the whole thread, and it's cached briefly — see
    /// `NewUserCache`. Empty if the page couldn't be read.
    ///
    /// Empty, with no request made, when logged out: HN marks new accounts
    /// only on pages served to a signed-in reader, so a logged-out read would
    /// cost a whole thread's page and find nothing.
    func newUsers(inThread id: Int) async -> Set<String> {
        guard Self.hasAuthCookie else { return [] }
        return await newUserCache.usernames(inThread: id)
    }

    // MARK: - Search

    /// Searches for stories, polls, or Show/Ask HN posts, returning their ids.
    ///
    /// `tags` and `numericFilters` are Algolia's own vocabulary, built by
    /// `SearchQuery` — the category tag, an optional `author_`, and numeric
    /// bounds on `num_comments`/`created_at_i`. Passing them through rather than
    /// re-deriving them here keeps one translation of a search in the app.
    func searchStoryIds(
        query: String,
        tags: [String],
        numericFilters: [String],
        page: Int
    ) async -> (ids: [Int], hasMore: Bool) {
        await algolia.searchStoryIds(
            query: query, tags: tags, numericFilters: numericFilters, page: page
        )
    }

    /// Searches comments, returning them ready to display.
    func searchComments(
        query: String,
        tags: [String],
        numericFilters: [String],
        page: Int
    ) async -> (comments: [UserComment], hasMore: Bool) {
        await algolia.searchComments(
            query: query, tags: tags, numericFilters: numericFilters, page: page
        )
    }

    // MARK: - Users

    func getUser(for username: String) async -> User? {
        guard let userdata = await algolia.getUserData(username) else {
            return nil
        }
        return User(from: userdata)
    }

    /// Finds a user by name, tolerating the capitalisation someone typed.
    ///
    /// Algolia indexes no people: `/users/:username` is an exact match, and
    /// there's no user index to search loosely. So on a miss this retries the
    /// name lowercased — which is precisely what iOS's automatic
    /// capitalisation costs, and Hacker News names are overwhelmingly
    /// lowercase. Only the miss pays for a second request; `getUser(for:)`
    /// stays exact for callers that already hold a real username.
    func findUser(named username: String) async -> User? {
        if let user = await getUser(for: username) {
            return user
        }
        let lowercased = username.lowercased()
        guard lowercased != username else { return nil }
        return await getUser(for: lowercased)
    }

    func getUserStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool) {
        await algolia.getUserStoryIds(username: username, page: page)
    }

    func getUserComments(username: String, page: Int) async -> (comments: [UserComment], hasMore: Bool) {
        await algolia.getUserComments(username: username, page: page)
    }

    /// A user's liked (upvoted) stories, most-recent first, for their own
    /// profile's "Liked" tab. Hacker News exposes `/upvoted` only to its owner, so
    /// `username` must be the signed-in user for this to return anything. `page`
    /// is 0-based to match the other user feeds. `nil` means the page couldn't be
    /// fetched, as distinct from an empty page.
    func getLikedStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool)? {
        // NewsYCService pages the /upvoted list 1-based.
        await newsYC.upvotedStoryIds(username: username, page: page + 1)
    }

    // MARK: - Voting

    /// Upvotes a story on behalf of the logged-in user.
    func upvoteStory(id: Int) async throws {
        try await vote(itemId: id, how: .up)
    }

    /// Removes the logged-in user's upvote from a story.
    func unvoteStory(id: Int) async throws {
        try await vote(itemId: id, how: .unvote)
    }

    /// Upvotes a comment on behalf of the logged-in user.
    ///
    /// The same request as upvoting a story: Hacker News votes on *items*, and a
    /// comment is an item. These exist as their own names only because the
    /// callers are different, and because comment votes are tracked separately —
    /// see `InteractionStore`.
    func upvoteComment(id: Int) async throws {
        try await vote(itemId: id, how: .up)
    }

    /// Removes the logged-in user's upvote from a comment.
    func unvoteComment(id: Int) async throws {
        try await vote(itemId: id, how: .unvote)
    }

    private func vote(itemId: Int, how: NewsYCService.VoteAction) async throws {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        // The vote requires the item's per-user `auth` token, which only lives in
        // the item page's HTML, so fetch it first, then cast the vote.
        guard let voteAuth = await newsYC.voteAuth(forItem: itemId) else {
            throw APIError.missingAuthToken
        }
        try await newsYC.castVote(id: itemId, how: how, auth: voteAuth.auth)
    }

    /// The points on one of the logged-in user's own comments. Hacker News
    /// shows a comment's score only to its author, so this is `nil` for anyone
    /// else's comment, when logged out, or if the page couldn't be read.
    /// `username` is the logged-in user, whose `/threads` the scores are read
    /// from in bulk — see `CommentScoreCache`.
    func ownCommentScore(id: Int, username: String) async -> Int? {
        guard Self.hasAuthCookie else { return nil }
        return await commentScores.score(for: id, username: username)
    }

    /// A user's upvoted comments, most-recent first, for their own profile's
    /// Likes. Hacker News shows `/upvoted` only to its owner, so `username` must
    /// be the signed-in user. `page` is 0-based to match the other user feeds.
    /// `nil` means the page couldn't be fetched, as distinct from an empty page.
    func getLikedComments(username: String, page: Int) async -> (comments: [UserComment], hasMore: Bool)? {
        // NewsYCService pages the /upvoted list 1-based.
        await newsYC.upvotedComments(username: username, page: page + 1)
    }

    // MARK: - Polls

    /// A poll's options, in the poll's order, fetched together. An option that
    /// fails to load is left out rather than failing the poll.
    func getPollOptions(ids: [Int]) async -> [PollOption] {
        let loaded = await withTaskGroup(of: FirebasePollOptionData?.self) { group in
            for id in ids {
                group.addTask { [firebase] in await firebase.getPollOptionAsync(id: id) }
            }
            var loaded: [Int: FirebasePollOptionData] = [:]
            for await option in group {
                if let option { loaded[option.id] = option }
            }
            return loaded
        }
        return ids.compactMap { id in
            loaded[id].map {
                PollOption(id: id, text: $0.text?.normalizeHtmlText() ?? "", votes: $0.score ?? 0)
            }
        }
    }

    /// The signed-in reader's votes in a poll, and the tokens to change them.
    /// `nil` when logged out or if the poll's page couldn't be read.
    func pollBallot(pollID: Int, optionIDs: [Int]) async -> PollBallot? {
        guard Self.hasAuthCookie,
              let votes = await newsYC.pollVotes(pollID: pollID, optionIDs: optionIDs) else {
            return nil
        }
        return PollBallot(
            voted: Set(votes.filter(\.value.alreadyUpvoted).keys),
            tokens: votes.mapValues(\.auth)
        )
    }

    /// Votes for, or withdraws a vote from, one of a poll's options. The token
    /// comes from the reader's `PollBallot`, so this costs a single request.
    func setPollVote(optionID: Int, voted: Bool, ballot: PollBallot) async throws {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        guard let auth = ballot.tokens[optionID] else { throw APIError.missingAuthToken }
        try await newsYC.castVote(id: optionID, how: voted ? .up : .unvote, auth: auth)
    }

    // MARK: - Favorites

    /// Favorites a story on behalf of the logged-in user.
    func favoriteStory(id: Int) async throws {
        try await fave(storyId: id, un: false)
    }

    /// Removes the logged-in user's favorite from a story.
    func unfavoriteStory(id: Int) async throws {
        try await fave(storyId: id, un: true)
    }

    private func fave(storyId: Int, un: Bool) async throws {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        // Like voting, favoriting needs the item's per-user `auth` token from its
        // page HTML.
        guard let faveAuth = await newsYC.faveAuth(forItem: storyId) else {
            throw APIError.missingAuthToken
        }
        try await newsYC.castFave(id: storyId, un: un, auth: faveAuth.auth)
    }

    /// A user's favorited stories, most-recent first, paginated. Favorites are
    /// public on Hacker News, so this works for any `username`. `page` is 0-based to
    /// match the other user feeds. `nil` means the page couldn't be fetched, as
    /// distinct from an empty page.
    func getFavoriteStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool)? {
        // NewsYCService pages the /favorites list 1-based.
        await newsYC.favoriteStoryIds(username: username, page: page + 1)
    }

    // MARK: - Commenting

    /// Posts a comment as the logged-in user and returns once Hacker News has
    /// accepted it.
    ///
    /// `parentId` is the item being answered: the story itself for a new
    /// top-level comment, or a comment for a reply — Hacker News makes no
    /// distinction between the two, so neither do we. `storyId` identifies the
    /// thread the comment lands in, which is what HN's form redirects back to
    /// and what we invalidate afterwards.
    ///
    /// Recovering the id Hacker News assigned is a separate, slower step — see
    /// `findPostedCommentId(username:parentId:)`.
    func postComment(parentId: Int, storyId: Int, text: String) async throws {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        // Like voting, posting needs a token that only exists in the form's
        // HTML, so scrape the form first and then send it back with the text.
        guard let form = await newsYC.commentForm(parentId: parentId, storyId: storyId) else {
            throw APIError.missingAuthToken
        }
        try await newsYC.postComment(fields: form, text: text)

        // The thread now has a comment neither cache knows about.
        await invalidateThread(for: storyId)
    }

    // MARK: - Submitting

    /// Submits a new post as the logged-in user. Pass an empty `url` for a
    /// text post; `text` may be empty for either kind.
    ///
    /// A link that's already on Hacker News isn't posted again — HN upvotes the
    /// existing story instead, reported as `.alreadySubmitted`.
    ///
    /// `username` is the poster, whose submissions are where the new post's id
    /// is recovered from.
    func submitStory(
        title: String,
        url: String,
        text: String,
        username: String
    ) async throws -> SubmissionOutcome {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        guard let form = await newsYC.submitForm() else {
            throw APIError.missingAuthToken
        }
        let submittedAt = Date.now
        switch try await newsYC.submitStory(fields: form, title: title, url: url, text: text) {
        case .posted:
            return await .posted(storyID: findSubmittedStoryId(username: username, after: submittedAt))
        case let .repost(id):
            return .alreadySubmitted(storyID: id)
        }
    }

    /// How long to wait before each attempt at recovering a new post's id.
    /// Firebase usually has it straight away; the retries cover the moments
    /// when it lags.
    private static let submittedStoryIdDelays: [Duration] = [
        .zero, .seconds(1), .seconds(2),
    ]

    /// The id of the story the user just submitted, or `nil` if it couldn't be
    /// confirmed.
    ///
    /// As with comments, HN's redirect doesn't report the new id, so it's read
    /// from the front of the author's Firebase submissions. Confirming it is a
    /// story — a comment won't decode as one — posted no earlier than this
    /// submission keeps a lagging mirror from handing back the author's
    /// previous post. The title isn't compared because HN sometimes edits it.
    private func findSubmittedStoryId(username: String, after date: Date) async -> Int? {
        // A minute's grace for any difference between our clock and HN's.
        let earliest = Int(date.timeIntervalSince1970) - 60
        var ruledOut: Int?

        for delay in Self.submittedStoryIdDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
            guard let newest = await firebase.getUserAsync(username: username)?.submitted?.first,
                  newest != ruledOut else {
                continue
            }
            guard let story = await firebase.getStoryAsync(id: newest),
                  story.by == username, story.time >= earliest else {
                ruledOut = newest
                continue
            }
            return newest
        }
        return nil
    }

    /// How long after posting Hacker News lets a comment's author delete it.
    private static let commentDeleteWindow: TimeInterval = 2 * 60 * 60

    /// Whether a comment posted at `timestamp` is still young enough to delete.
    /// Used to offer Delete only while it can work; HN has the final say (it
    /// also refuses once a comment has replies).
    static func isWithinDeleteWindow(_ timestamp: Date) -> Bool {
        timestamp.timeIntervalSinceNow > -commentDeleteWindow
    }

    /// Deletes one of the logged-in user's comments.
    ///
    /// Throws `APIError.deleteUnavailable` when HN no longer offers deletion —
    /// past the edit window, or once it has replies.
    func deleteComment(id: Int, storyId: Int) async throws {
        guard Self.hasAuthCookie else { throw APIError.notLoggedIn }
        guard let form = await newsYC.deleteForm(commentId: id, storyId: storyId) else {
            throw APIError.deleteUnavailable
        }
        try await newsYC.deleteComment(fields: form)

        // As after posting: both caches now describe a thread that no longer
        // exists.
        await invalidateThread(for: storyId)
    }

    /// How long to wait before each attempt at recovering a posted comment's id.
    ///
    /// The first attempt is immediate. Callers ask for an id only when they need
    /// one — which in practice is a while after the comment was written — so the
    /// mirror has usually caught up and the first ask succeeds. The two short
    /// retries are there for the case where it's asked for straight away.
    private static let postedCommentIdDelays: [Duration] = [
        .zero, .seconds(1), .seconds(2),
    ]

    /// The id Hacker News assigned to a comment the user posted, or `nil` if it
    /// couldn't be confirmed.
    ///
    /// Neither the comment form nor its redirect reports the new id — the
    /// redirect only echoes back the `goto` we sent it. So we ask Firebase for
    /// the author's submissions, which come newest-first, putting their most
    /// recent comment at the front.
    ///
    /// Confirming it is what makes that guess safe rather than merely likely.
    /// A miss doesn't return nothing — it returns the author's *previous*
    /// comment, whose `parent` won't match the one we posted to. Without the
    /// check we'd hand back a real id belonging to a different comment, and a
    /// reply aimed at it would land in an unrelated thread.
    ///
    /// `parentID` is the item the comment was posted under, which is what makes
    /// that confirmation possible. Honours cancellation between attempts.
    func findPostedCommentId(username: String, parentID: Int) async -> Int? {
        // The newest submission we've already ruled out. Seeing the same id
        // again means the mirror simply hasn't caught up, so we can skip the
        // second request that would re-confirm what we already know — which is
        // what keeps a run of failed attempts down to one request each.
        var ruledOut: Int?

        for delay in Self.postedCommentIdDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
            guard let newest = await firebase.getUserAsync(username: username)?.submitted?.first,
                  newest != ruledOut else {
                continue
            }
            guard let comment = await firebase.getCommentAsync(id: newest),
                  comment.by == username, comment.parent == parentID else {
                ruledOut = newest
                continue
            }
            return newest
        }
        return nil
    }

    // MARK: - Authentication

    func login(username: String, password: String) async throws {
        var loginError: Error?
        try await requestLoginCookie(username: username, password: password) { result in
            switch result {
            case let .success(token):
                print("Storing cookie.")
                HTTPCookieStorage.shared.setCookies(
                    [token],
                    for: Self.baseUri,
                    mainDocumentURL: nil
                )
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

    func logout(username: String) {
        let cookies = readCookie(forURL: Self.baseUri)
            .filter { $0.name == "user" && $0.value.contains(username) }
        print("User cookies: \(cookies)")
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    /// Hacker News only evaluates credentials that arrive in a form POST body —
    /// a GET with `?acct=…&pw=…` is ignored and simply re-renders the login
    /// form, which reads as a rejected password. `FormBody` handles the strict
    /// percent-encoding a password demands.
    private static func loginFormBody(username: String, password: String) -> Data {
        FormBody.encoded([
            (name: "acct", value: username),
            (name: "pw", value: password),
            (name: "goto", value: "news"),
        ])
    }

    /// Hacker News serves its reCAPTCHA challenge instead of checking the
    /// password when the login POST doesn't look like it came from a browser —
    /// the app's own descriptive User-Agent is enough to trigger it. This is
    /// only sent on the login request; the scraping requests in `NewsYCService`
    /// keep identifying themselves as Huck.
    private static let loginUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private func requestLoginCookie(username: String, password: String, cookieHandler: @escaping CookieHandler) async throws {
        var request = URLRequest(url: URL(string: "login", relativeTo: Self.baseUri)!)
        request.httpMethod = "POST"
        request.httpBody = Self.loginFormBody(username: username, password: password)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.loginUserAgent, forHTTPHeaderField: "User-Agent")

        // The redirect must stay blocked: a successful login is a 302 carrying
        // the `user` cookie, and following it would drop the `Set-Cookie` header
        // we're here for (the session deliberately doesn't store cookies itself).
        let (data, response) = try await transport.data(for: request, kind: .login, endpoint: nil)
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
            if let name = entry.key as? String, let value = entry.value as? String {
                fields[name] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: Self.baseUri)
        if let token = cookies.first(where: { $0.name == "user" }) {
            print("Success. Calling cookie handler")
            cookieHandler(.success(token))
        } else {
            // No cookie means a rejected password ("Bad login"), the captcha
            // wall, or Hacker News not serving us at all (an outage, or its rate
            // limiter). Each needs different advice, so tell them apart — above
            // all, never blame the password for a server error.
            let body = String(data: data, encoding: .utf8) ?? ""
            let error: APIError = if body.contains("Validation required") {
                .loginValidationRequired
            } else if !(200..<400).contains(response.statusCode)
                        || body.contains("not able to serve your requests") {
                .loginUnavailable
            } else {
                .loginFailed
            }
            print("Failure. Calling cookie handler: \(error)")
            cookieHandler(.failure(error))
        }
    }
}

private extension StoryDetails {
    /// Maps Firebase's story item, at the facade, so no service type reaches
    /// the app.
    init(firebase story: FirebaseStoryData) {
        self.init(
            title: story.title,
            by: story.by,
            score: story.score,
            timestamp: Date(timeIntervalSince1970: TimeInterval(story.time)),
            url: story.url.flatMap(URL.init(string:)),
            text: story.url == nil ? story.text?.normalizeHtmlText() ?? "" : "",
            pollOptionIDs: story.parts ?? [],
            // `descendants` is the whole-thread total; `kids` only the
            // top-level replies, the fallback when it's absent.
            commentCount: story.descendants ?? story.kids?.count ?? 0
        )
    }
}
