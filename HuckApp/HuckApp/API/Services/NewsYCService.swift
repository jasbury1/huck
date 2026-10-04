//
//  NewsYCService.swift
//  HuckApp
//
//  Created by James Asbury on 8/15/26.
//

import Foundation

// MARK: - Service

/// Reverse-engineered access to `news.ycombinator.com` itself, for the actions the
/// official JSON APIs (Algolia, Firebase) don't offer — currently voting.
///
/// Unlike the JSON services, this one scrapes HTML: HN embeds a per-user, per-item
/// `auth` token inside the vote links on its pages, and that token is required to
/// cast a vote. Requests are authenticated automatically because `URLSession.shared`
/// attaches the `user` cookie we store in `HTTPCookieStorage.shared`.
///
/// This service is an implementation detail of the API layer — callers reach it only
/// through `HackerNewsAPI`, never directly. All HTML parsing is localized here so a
/// markup change upstream is a one-file fix.
struct NewsYCService {
    private static let baseUri = "https://news.ycombinator.com"

    /// A polite, identifiable User-Agent for our scraping requests.
    private static let userAgent = "Huck (iOS; Hacker News client)"

    /// The direction of a vote. HN uses `how=up` to upvote and `how=un` to undo.
    enum VoteAction: String {
        case up
        case unvote = "un"
    }

    // MARK: - Voting

    /// Fetches an item's page and extracts the `auth` token needed to vote on it,
    /// along with whether the current user has already upvoted it. Returns `nil`
    /// if the token can't be found (e.g. not logged in, or markup changed).
    static func voteAuth(forItem id: Int) async -> (auth: String, alreadyUpvoted: Bool)? {
        guard let url = URL(string: "\(baseUri)/item?id=\(id)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // The story's own vote anchor is `id='up_<ID>'` (or `id='un_<ID>'` once
        // voted); its href carries `auth=<TOKEN>`. Scope the match to that anchor
        // so we don't pick up a comment's token.
        guard let auth = firstMatch(
            in: html,
            pattern: "id=['\"](?:up|un)_\(id)['\"][^>]*?auth=([0-9a-fA-F]+)"
        ) else {
            return nil
        }
        // When already upvoted, HN swaps the up arrow for an `un_<ID>` unvote link.
        let alreadyUpvoted = contains(in: html, pattern: "id=['\"]un_\(id)['\"]")
        return (auth, alreadyUpvoted)
    }

    /// The vote token and current vote for each of a poll's options, read from
    /// the poll's page in one request rather than one per option.
    ///
    /// Each option carries the same vote anchors a story does, so they're
    /// matched exactly as `voteAuth(forItem:)` matches a story's. An option
    /// missing from the result has no vote link at all — Hacker News removes
    /// them once a poll is archived. `nil` means the page couldn't be fetched.
    static func pollVotes(pollID: Int, optionIDs: [Int]) async -> [Int: (auth: String, alreadyUpvoted: Bool)]? {
        guard let url = URL(string: "\(baseUri)/item?id=\(pollID)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        var votes: [Int: (auth: String, alreadyUpvoted: Bool)] = [:]
        for id in optionIDs {
            guard let auth = firstMatch(
                in: html,
                pattern: "id=['\"](?:up|un)_\(id)['\"][^>]*?auth=([0-9a-fA-F]+)"
            ) else { continue }
            votes[id] = (auth, contains(in: html, pattern: "id=['\"]un_\(id)['\"]"))
        }
        return votes
    }

    /// Casts (or undoes) a vote on an item. Throws `APIError.voteFailed` on a
    /// non-success response.
    static func castVote(id: Int, how: VoteAction, auth: String) async throws {
        var components = URLComponents(string: "\(baseUri)/vote")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "how", value: how.rawValue),
            URLQueryItem(name: "auth", value: auth),
        ]
        guard let url = components.url else { throw APIError.voteFailed }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.countedData(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.voteFailed
        }
    }

    // MARK: - Favoriting

    /// Fetches an item's page and extracts the `auth` token needed to favorite it,
    /// along with whether the current user has already favorited it. Returns `nil`
    /// if the token can't be found (e.g. not logged in, or markup changed).
    static func faveAuth(forItem id: Int) async -> (auth: String, alreadyFavorited: Bool)? {
        guard let url = URL(string: "\(baseUri)/item?id=\(id)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // The item's favorite link is `fave?id=<ID>&auth=<TOKEN>` (and gains `un=t`
        // once favorited). Scope to this id so we don't pick up a comment's link.
        guard let auth = firstMatch(
            in: html,
            pattern: "fave\\?id=\(id)[^'\"]*?auth=([0-9a-fA-F]+)"
        ) else {
            return nil
        }
        let alreadyFavorited = contains(in: html, pattern: "fave\\?id=\(id)[^'\"]*?un=t")
        return (auth, alreadyFavorited)
    }

    /// Favorites (or un-favorites, when `un` is true) an item. Throws
    /// `APIError.favoriteFailed` on a non-success response.
    static func castFave(id: Int, un: Bool, auth: String) async throws {
        var components = URLComponents(string: "\(baseUri)/fave")!
        var items = [URLQueryItem(name: "id", value: String(id))]
        if un { items.append(URLQueryItem(name: "un", value: "t")) }
        items.append(URLQueryItem(name: "auth", value: auth))
        components.queryItems = items
        guard let url = components.url else { throw APIError.favoriteFailed }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.countedData(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.favoriteFailed
        }
    }

    // MARK: - Commenting

    /// The hidden fields Hacker News' comment form carries, in document order,
    /// or `nil` if the form couldn't be found.
    ///
    /// Posting is a two-step exchange for the same reason voting is: the form
    /// carries a per-user, per-parent `hmac` that HN checks as a CSRF token, and
    /// it exists only in the page's HTML. We forward *whatever* hidden inputs the
    /// form declares rather than naming them one by one, so a field renamed or
    /// added upstream keeps working without a code change here.
    ///
    /// `parentId` is the item being answered — a story for a new top-level
    /// comment, a comment for a reply — and `storyId` only decides where HN sends
    /// the browser afterwards, matching what the web form does.
    static func commentForm(parentId: Int, storyId: Int) async -> [(name: String, value: String)]? {
        // `/reply` is tried first for both cases: it serves the same form for any
        // commentable item and weighs a few hundred bytes, where a popular story's
        // `/item` page is the entire rendered thread. The item page is kept as a
        // fallback in case HN ever stops serving `/reply` for stories themselves.
        let candidates = [
            replyURL(parentId: parentId, storyId: storyId),
            URL(string: "\(baseUri)/item?id=\(parentId)"),
        ]
        for case let url? in candidates {
            guard let html = try? await fetchHTML(from: url) else { continue }
            let fields = hiddenFields(inFormWithAction: "comment", of: html)
            // Confirm the form we found actually targets the item we mean to
            // answer. A logged-out page (HN serves a login wall instead) or an
            // unexpected form won't carry a matching `parent`, and posting it
            // would put the comment somewhere the user didn't ask for.
            guard fields.contains(where: { $0.name == "parent" && $0.value == String(parentId) }) else {
                continue
            }
            return fields
        }
        return nil
    }

    /// Posts a comment, sending the scraped form fields back alongside the text.
    /// Throws `APIError.commentFailed` if Hacker News doesn't accept it.
    static func postComment(fields: [(name: String, value: String)], text: String) async throws {
        guard let url = URL(string: "\(baseUri)/comment") else { throw APIError.commentFailed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = FormBody.encoded(fields + [(name: "text", value: text)])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await postingSession.countedData(for: request)
        // HN redirects on success and re-renders the form (200) on refusal, so
        // the status code is the whole answer — see `postingSession`.
        guard let http = response as? HTTPURLResponse, http.statusCode == 302 else {
            throw APIError.commentFailed
        }
    }

    // MARK: - Comment scores

    /// The points on one of the reader's own comments, or `nil` if the page
    /// doesn't show them. The fallback for a comment too old for
    /// `threadScores(username:next:)` to reach.
    ///
    /// Hacker News publishes a comment's score to no one but its author, and
    /// only in the page markup — neither JSON API carries it (Algolia's
    /// `points` is always null for comments). The comment's own `/item` page is
    /// read rather than its story's, which for a busy thread is the whole
    /// conversation.
    static func commentScore(id: Int) async -> Int? {
        guard let url = URL(string: "\(baseUri)/item?id=\(id)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // `<span class="score" id="score_<ID>">12 points</span>`, scoped to this
        // id so a reply's score on the same page can't be picked up instead.
        return firstMatch(
            in: html,
            pattern: "id=['\"]score_\(id)['\"][^>]*>\\s*(\\d+)\\s+points?"
        ).flatMap(Int.init)
    }

    /// One page of the reader's `/threads` — their comments, newest first,
    /// each with the replies beneath it — as the scores it shows, or `nil` if
    /// the page couldn't be fetched.
    ///
    /// This is how scores are read in bulk: Hacker News marks the score on
    /// every one of the reader's own comments on the page, so one request
    /// covers a page of them rather than one each. `oldestID` is the lowest
    /// comment id on the page (ids rise over time, so everything newer than it
    /// has been seen), and `next` is the cursor for the page after it.
    static func threadScores(
        username: String,
        next: Int? = nil
    ) async -> (scores: [Int: Int], oldestID: Int?, next: Int?)? {
        var components = URLComponents(string: "\(baseUri)/threads")
        components?.queryItems = [URLQueryItem(name: "id", value: username)]
            + (next.map { [URLQueryItem(name: "next", value: String($0))] } ?? [])
        guard let url = components?.url,
              let html = try? await fetchHTML(from: url) else {
            return nil
        }

        var scores: [Int: Int] = [:]
        if let regex = try? NSRegularExpression(
            pattern: "id=['\"]score_(\\d+)['\"][^>]*>\\s*(\\d+)\\s+points?",
            options: [.caseInsensitive]
        ) {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let idRange = Range(match.range(at: 1), in: html),
                      let scoreRange = Range(match.range(at: 2), in: html),
                      let id = Int(html[idRange]),
                      let score = Int(html[scoreRange]) else { continue }
                scores[id] = score
            }
        }
        // Every comment row, the reader's and the replies alike, bounds what
        // the page covers.
        let oldestID = allMatches(
            in: html,
            pattern: "<tr[^>]*class=['\"]athing[^'\"]*['\"][^>]*id=['\"](\\d+)['\"]"
        ).compactMap(Int.init).min()
        // The More link carries the cursor: `threads?id=<user>&next=<id>`. The
        // tag is found first, so attribute order doesn't matter.
        let nextCursor = allTags(in: html, pattern: "<a[^>]*morelink[^>]*>")
            .first
            .flatMap { firstMatch(in: $0, pattern: "next=(\\d+)") }
            .flatMap(Int.init)
        return (scores, oldestID, nextCursor)
    }

    // MARK: - Deleting

    /// The hidden fields of Hacker News' delete confirmation form for one of
    /// the reader's comments, or `nil` if HN didn't offer one.
    ///
    /// The same two-step exchange as posting: `/delete-confirm` carries a
    /// per-user, per-item `hmac` that `/xdelete` checks. HN serves the form only
    /// while the comment can still be deleted — to its author, within the edit
    /// window — so a missing form is the answer "not any more", not a glitch.
    static func deleteForm(commentId: Int, storyId: Int) async -> [(name: String, value: String)]? {
        var components = URLComponents(string: "\(baseUri)/delete-confirm")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(commentId)),
            URLQueryItem(name: "goto", value: "item?id=\(storyId)"),
        ]
        guard let url = components?.url,
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // HN has written the action both with and without a leading slash.
        let fields = ["/xdelete", "xdelete"]
            .lazy
            .map { hiddenFields(inFormWithAction: $0, of: html) }
            .first { !$0.isEmpty } ?? []
        // As with replies, confirm the form names the comment we mean, so a
        // stray form can never delete the wrong one.
        guard fields.contains(where: { $0.name == "id" && $0.value == String(commentId) }) else {
            return nil
        }
        return fields
    }

    /// Deletes a comment by sending the scraped confirmation form back with its
    /// "Yes" button. Throws `APIError.deleteFailed` if HN doesn't accept it.
    static func deleteComment(fields: [(name: String, value: String)]) async throws {
        guard let url = URL(string: "\(baseUri)/xdelete") else { throw APIError.deleteFailed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // `d` is the submit button the reader would have pressed; it isn't a
        // hidden field, so it's added here.
        request.httpBody = FormBody.encoded(fields + [(name: "d", value: "Yes")])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await postingSession.countedData(for: request)
        // Like the comment form, an accepted POST is answered with a redirect.
        guard let http = response as? HTTPURLResponse, http.statusCode == 302 else {
            throw APIError.deleteFailed
        }
    }

    /// The reply form's URL. `goto` is where HN sends the browser after a
    /// successful post; we never follow it, but it's part of the form HN expects
    /// back, so it's set to the thread the comment belongs to.
    private static func replyURL(parentId: Int, storyId: Int) -> URL? {
        var components = URLComponents(string: "\(baseUri)/reply")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(parentId)),
            URLQueryItem(name: "goto", value: "item?id=\(storyId)"),
        ]
        return components?.url
    }

    /// A session that keeps our `user` cookie — so HN knows who is writing — but
    /// does not follow redirects, because here the redirect *is* the result: HN
    /// answers an accepted form POST with a 302 and a refused one with a 200 that
    /// re-renders the form. Following the redirect would collapse both into a 200
    /// and leave us unable to tell a posted comment from a dropped one.
    private static let postingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    // MARK: - Story-list history

    /// Scrapes one page of the user's `/upvoted` history (private to its owner),
    /// returning the story ids on that page and whether a further page exists,
    /// or `nil` if the page couldn't be fetched.
    static func upvotedStoryIds(username: String, page: Int = 1) async -> (ids: [Int], hasMore: Bool)? {
        await storyListPage(path: "upvoted", username: username, page: page)
    }

    /// Scrapes one page of the user's public `/favorites`, returning the story ids
    /// on that page and whether a further page exists, or `nil` if the page
    /// couldn't be fetched.
    static func favoriteStoryIds(username: String, page: Int = 1) async -> (ids: [Int], hasMore: Bool)? {
        await storyListPage(path: "favorites", username: username, page: page)
    }

    /// Fetches and parses a standard HN story-list page (`/upvoted`, `/favorites`,
    /// …), which all share the same row markup. Returns `nil` when the fetch
    /// fails, which callers must distinguish from an empty final page: a caller
    /// that treats a failure as "the list ends here" would conclude the user has
    /// no further favorites and wrongly discard them.
    private static func storyListPage(path: String, username: String, page: Int) async -> (ids: [Int], hasMore: Bool)? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let url = URL(string: "\(baseUri)/\(path)?id=\(encoded)&p=\(page)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // Each story row is `<tr class='athing' id='<ID>'>`.
        let ids = allMatches(in: html, pattern: "class=['\"]athing[^>]*?id=['\"](\\d+)['\"]")
            .compactMap { Int($0) }
        // A `morelink` anchor at the bottom means there's another page.
        let hasMore = contains(in: html, pattern: "class=['\"]morelink['\"]")
        return (ids, hasMore)
    }

    // MARK: - Comment-list history

    /// Scrapes one page of the user's upvoted comments — `/upvoted?comments=t`,
    /// which Hacker News shows only to its owner. `nil` if the page couldn't be
    /// fetched, which callers must tell apart from an empty final page.
    ///
    /// The page carries everything a comment row needs to render: the text, the
    /// author, the age, and the story it sits in. So one request per page does
    /// the whole job, where ids alone would mean a fetch per comment — and then
    /// a walk up its parents just to name the story it belongs to.
    static func upvotedComments(username: String, page: Int = 1) async -> (comments: [UserComment], hasMore: Bool)? {
        await commentListPage(path: "upvoted", username: username, page: page)
    }

    private static func commentListPage(
        path: String,
        username: String,
        page: Int
    ) async -> (comments: [UserComment], hasMore: Bool)? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let url = URL(string: "\(baseUri)/\(path)?id=\(encoded)&comments=t&p=\(page)"),
              let html = try? await fetchHTML(from: url) else {
            return nil
        }
        // A `morelink` anchor at the bottom means there's another page.
        let hasMore = contains(in: html, pattern: "class=['\"]morelink['\"]")
        return (comments(in: html), hasMore)
    }

    /// Every comment on a Hacker News comment-list page, in page order.
    ///
    /// Each comment is an `<tr class="athing …" id="…">` row, so the rows are
    /// located first and each one's markup taken as the span up to the next —
    /// which keeps a field pattern from ever reaching into a neighbouring
    /// comment and attributing one reader's words to another.
    ///
    /// The class is matched loosely because Hacker News doesn't spell it the
    /// same way on every page: `/upvoted?comments=t` uses a bare `athing`,
    /// while `/threads` adds `comtr`.
    private static func comments(in html: String) -> [UserComment] {
        guard let rowRegex = try? NSRegularExpression(
            pattern: "<tr[^>]*class=['\"]athing[^'\"]*['\"][^>]*id=['\"](\\d+)['\"]",
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let matches = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.enumerated().compactMap { index, match in
            guard let matchRange = Range(match.range, in: html),
                  let idRange = Range(match.range(at: 1), in: html),
                  let id = Int(html[idRange]) else {
                return nil
            }
            let nextRowStart = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: html)?.lowerBound
                : nil
            let row = String(html[matchRange.upperBound..<(nextRowStart ?? html.endIndex)])
            return comment(id: id, row: row)
        }
    }

    /// One comment from its row's markup, or `nil` if it has no text — a
    /// flagged or deleted comment, which there's nothing to show for.
    private static func comment(id: Int, row: String) -> UserComment? {
        // `[\s\S]` rather than `.` because a comment's text spans lines.
        guard let text = firstMatch(
            in: row,
            pattern: "class=['\"]commtext[^'\"]*['\"]>([\\s\\S]*?)</div>"
        ) else {
            return nil
        }
        // The `onstory` span names the story. Its link text is truncated with an
        // ellipsis, so the headline comes from the anchor's `title` instead.
        let storyId = firstMatch(
            in: row,
            pattern: "class=['\"]onstory['\"]>[\\s\\S]*?<a href=['\"]item\\?id=(\\d+)['\"]"
        ).flatMap(Int.init)
        let storyTitle = firstMatch(
            in: row,
            pattern: "class=['\"]onstory['\"]>[\\s\\S]*?<a[^>]*title=['\"]([^'\"]*)['\"]"
        ).map(htmlUnescaped)

        return UserComment(
            id: id,
            author: firstMatch(in: row, pattern: "class=['\"]hnuser['\"][^>]*>([^<]*)</a>") ?? "",
            text: htmlUnescaped(text).normalizeHtmlText(),
            storyTitle: storyTitle,
            storyId: storyId,
            timestamp: commentDate(in: row) ?? .now
        )
    }

    /// When a comment was posted, from the `age` span's `title`.
    ///
    /// That attribute is either an ISO timestamp or an ISO timestamp followed by
    /// the same moment in Unix seconds, depending on the page's vintage. The
    /// number is preferred where present, being unambiguous about its zone; the
    /// ISO form is read as UTC, which is what Hacker News serves.
    private static func commentDate(in row: String) -> Date? {
        guard let title = firstMatch(in: row, pattern: "class=['\"]age['\"][^>]*title=['\"]([^'\"]*)['\"]") else {
            return nil
        }
        let parts = title.split(separator: " ")
        if parts.count > 1, let seconds = TimeInterval(parts[1]) {
            return Date(timeIntervalSince1970: seconds)
        }
        return isoDateFormatter.date(from: String(parts[0]))
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - HTML fetching

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.countedData(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw NetworkError.badStatus
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw NetworkError.failedToDecodeResponse
        }
        return html
    }

    // MARK: - Form parsing

    /// Every hidden input of the first form with the given `action`, as
    /// name/value pairs in document order.
    private static func hiddenFields(inFormWithAction action: String, of html: String) -> [(name: String, value: String)] {
        guard let form = form(withAction: action, in: html) else { return [] }
        return allTags(in: form, pattern: "<input[^>]*>").compactMap { tag in
            guard attribute("type", in: tag)?.lowercased() == "hidden",
                  let name = attribute("name", in: tag),
                  let value = attribute("value", in: tag) else {
                return nil
            }
            return (name, htmlUnescaped(value))
        }
    }

    /// The markup of the first `<form>` whose `action` matches, from just after
    /// its opening tag to its closing one. Opening tags are matched first and
    /// their `action` read afterwards, rather than pattern-matching the
    /// attribute inline, so `action="comment"` can't be confused for a form
    /// whose action merely starts with it.
    private static func form(withAction action: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<form[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html),
                  attribute("action", in: String(html[tagRange]))?.lowercased() == action.lowercased() else {
                continue
            }
            let rest = html[tagRange.upperBound...]
            // An unterminated form runs to the end of the document; the inputs
            // we're after come first either way.
            guard let end = rest.range(of: "</form>", options: .caseInsensitive) else {
                return String(rest)
            }
            return String(rest[..<end.lowerBound])
        }
        return nil
    }

    /// The value of an attribute within a single HTML tag. Hacker News quotes
    /// every attribute it emits, so only quoted values are recognised.
    private static func attribute(_ name: String, in tag: String) -> String? {
        firstMatch(in: tag, pattern: "\\b\(name)=[\"']([^\"']*)[\"']")
    }

    /// Decodes the entities Hacker News escapes attribute values with.
    private static func htmlUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            // `&amp;` last, so that an escaped "&amp;lt;" survives as "&lt;"
            // rather than being decoded twice into "<".
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Regex helpers

    /// Every whole match of the pattern, for patterns with nothing to capture.
    private static func allTags(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matched = Range(match.range, in: text) else { return nil }
            return String(text[matched])
        }
    }

    /// The first capture group of the first match, or `nil`.
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captured])
    }

    /// The first capture group of every match.
    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captured])
        }
    }

    /// Whether the pattern matches anywhere in the text.
    private static func contains(in text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
