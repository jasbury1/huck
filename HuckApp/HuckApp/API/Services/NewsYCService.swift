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
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.voteFailed
        }
    }

    // MARK: - Upvote history

    /// Scrapes one page of the user's `/upvoted` history, returning the story ids
    /// on that page and whether a further page exists.
    static func upvotedStoryIds(username: String, page: Int = 1) async -> (ids: [Int], hasMore: Bool) {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let url = URL(string: "\(baseUri)/upvoted?id=\(encoded)&p=\(page)"),
              let html = try? await fetchHTML(from: url) else {
            return ([], false)
        }
        // Each story row is `<tr class='athing' id='<ID>'>`.
        let ids = allMatches(in: html, pattern: "class=['\"]athing[^>]*?id=['\"](\\d+)['\"]")
            .compactMap { Int($0) }
        // A `morelink` anchor at the bottom means there's another page.
        let hasMore = contains(in: html, pattern: "class=['\"]morelink['\"]")
        return (ids, hasMore)
    }

    // MARK: - HTML fetching

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw NetworkError.badStatus
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw NetworkError.failedToDecodeResponse
        }
        return html
    }

    // MARK: - Regex helpers

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
