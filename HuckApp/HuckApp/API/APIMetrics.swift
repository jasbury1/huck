//
//  APIMetrics.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation
import Synchronization

/// The upstream a request went to, as tallied by `APIMetrics`. Nonisolated, so
/// requests can be classified on whatever thread they're made from.
nonisolated enum APISource: CaseIterable, Identifiable {
    case algolia
    case firebase
    case scraped
    /// Article pages and images fetched for story thumbnails. These go to
    /// arbitrary third-party hosts, so this is also where anything unrecognized
    /// lands.
    case thumbnails

    var id: Self { self }

    /// Classifies a request by its host.
    init(url: URL) {
        switch url.host() {
        case "hn.algolia.com": self = .algolia
        case "hacker-news.firebaseio.com": self = .firebase
        case "news.ycombinator.com": self = .scraped
        default: self = .thumbnails
        }
    }

    var title: String {
        switch self {
        case .algolia: "Algolia"
        case .firebase: "Official API"
        case .scraped: "Scraped (news.ycombinator.com)"
        case .thumbnails: "Thumbnails & Other"
        }
    }

    var systemImage: String {
        switch self {
        case .algolia: "magnifyingglass"
        case .firebase: "flame"
        case .scraped: "chevron.left.forwardslash.chevron.right"
        case .thumbnails: "photo"
        }
    }

    /// The endpoint a URL hit, used to break a source's count down — e.g. a
    /// Firebase `/v0/item/123.json` is "item", an Algolia `/api/v1/search` is
    /// "search", a scraped `/vote` is "vote". Thumbnail hosts have no shared
    /// shape, so their endpoint is supplied by the caller instead.
    func endpoint(for url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        let name: String? = switch self {
        case .firebase: components.dropFirst().first   // after "v0"
        case .algolia: components.dropFirst(2).first   // after "api/v1"
        case .scraped: components.first
        case .thumbnails: nil
        }
        guard let name else { return url.host() ?? "unknown" }
        return name.hasSuffix(".json") ? String(name.dropLast(5)) : name
    }
}

/// Counts every network request the app makes, by source and endpoint, for the
/// debug screen.
///
/// Counting happens in one place, `URLSession.countedData(for:)`, which every
/// request goes through, so services don't know this exists and a new
/// endpoint is counted without anyone remembering to. Counts are in-memory
/// only and are kept whether or not debug mode is on, so turning it on shows
/// the whole session so far.
///
/// Requests don't write here directly: they're tallied off the main actor by
/// `RequestTally` and arrive in batches (see `apply(_:)`), so a burst of
/// hundreds of requests costs the main thread a few updates, not hundreds.
@Observable
final class APIMetrics {
    static let shared = APIMetrics()

    /// Request counts per source, then per endpoint within it.
    private(set) var counts: [APISource: [String: Int]] = [:]

    /// When counting began: launch, or the last reset.
    private(set) var countingSince = Date.now

    private init() {}

    var total: Int {
        counts.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    func total(for source: APISource) -> Int {
        counts[source]?.values.reduce(0, +) ?? 0
    }

    /// A source's endpoints, busiest first.
    func endpoints(for source: APISource) -> [(name: String, count: Int)] {
        (counts[source] ?? [:])
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// Folds in a batch of counts tallied since the last one.
    fileprivate func apply(_ batch: [APISource: [String: Int]]) {
        for (source, endpoints) in batch {
            for (endpoint, count) in endpoints {
                counts[source, default: [:]][endpoint, default: 0] += count
            }
        }
    }

    func reset() {
        counts = [:]
        countingSince = .now
    }
}

extension URLSession {
    /// `data(for:delegate:)`, counted in `APIMetrics`. Every request the app
    /// makes should go through this rather than `data(for:)` directly.
    ///
    /// The request is counted when it's sent, so failures count too: they
    /// still reached the server, or tried to.
    ///
    /// - Parameter endpoint: Overrides the endpoint name derived from the URL,
    ///   for hosts without a known shape (thumbnail fetches).
    nonisolated func countedData(
        for request: URLRequest,
        delegate: (any URLSessionTaskDelegate)? = nil,
        endpoint: String? = nil
    ) async throws -> (Data, URLResponse) {
        if let url = request.url {
            RequestTally.shared.record(url, endpoint: endpoint)
        }
        return try await data(for: request, delegate: delegate)
    }
}

/// Where requests are counted as they're made, on any thread, before the
/// counts reach `APIMetrics` on the main actor.
///
/// Recording is a dictionary increment under a lock, with no hop and nothing
/// awaited, so counting never delays a request. The first request after a
/// quiet spell schedules a flush a moment later; everything counted until then
/// rides along in that one main-actor update.
private nonisolated final class RequestTally: Sendable {
    static let shared = RequestTally()

    /// How long counts gather before being published.
    private static let flushDelay: Duration = .milliseconds(250)

    private struct State {
        var pending: [APISource: [String: Int]] = [:]
        var isFlushScheduled = false
    }
    private let state = Mutex(State())

    func record(_ url: URL, endpoint: String?) {
        let source = APISource(url: url)
        let name = endpoint ?? source.endpoint(for: url)
        let needsFlush = state.withLock { state in
            state.pending[source, default: [:]][name, default: 0] += 1
            guard !state.isFlushScheduled else { return false }
            state.isFlushScheduled = true
            return true
        }
        guard needsFlush else { return }
        Task {
            try? await Task.sleep(for: Self.flushDelay)
            let batch = takePending()
            await APIMetrics.shared.apply(batch)
        }
    }

    /// Everything counted since the last flush, clearing it for the next.
    private func takePending() -> [APISource: [String: Int]] {
        state.withLock { state in
            defer {
                state.pending = [:]
                state.isFlushScheduled = false
            }
            return state.pending
        }
    }
}
