//
//  FixtureTransport.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

#if DEBUG
import CryptoKit
import Foundation
import OSLog

/// A set of recorded responses on disk, keyed by the request that fetched each
/// one. Written by `RecordingTransport`, read by `FixtureTransport`.
///
/// The layout is a directory holding `manifest.jsonl` — one `Entry` per line,
/// appended as responses are recorded, later lines winning — beside a body
/// file per response. Line-per-entry keeps recording an append rather than a
/// rewrite, and keeps a re-recorded fixture's diff to the lines that changed.
nonisolated struct FixtureStore: Sendable {
    /// One recorded response.
    struct Entry: Codable, Sendable {
        /// The request it answers; see `FixtureStore.key(for:)`.
        let key: String
        let status: Int
        let contentType: String?
        /// The body's file, relative to the store's directory.
        let file: String
    }

    static let manifestName = "manifest.jsonl"

    let directory: URL
    private let entries: [String: Entry]

    /// Loads the store at `directory`, or `nil` if it has no manifest.
    init?(directory: URL) {
        guard let manifest = try? String(contentsOf: directory.appending(path: Self.manifestName), encoding: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        var entries: [String: Entry] = [:]
        for line in manifest.split(separator: "\n") {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line.utf8)) else { continue }
            entries[entry.key] = entry
        }
        self.directory = directory
        self.entries = entries
    }

    /// The fixtures bundled into debug builds, if this build has them.
    static var bundled: FixtureStore? {
        Bundle.main.url(forResource: "Fixtures", withExtension: "bundle").flatMap(FixtureStore.init(directory:))
    }

    var count: Int { entries.count }

    /// Every recorded request's key — for tests that need to know what the
    /// current recording happens to contain, such as which threads.
    var keys: [String] { Array(entries.keys) }

    /// The recorded response to `request`, or `nil` if none was recorded.
    func response(to request: URLRequest) -> (Data, HTTPURLResponse)? {
        guard let url = request.url,
              let key = Self.key(for: request),
              let entry = entries[key],
              let body = try? Data(contentsOf: directory.appending(path: entry.file)),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: entry.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: entry.contentType.map { ["Content-Type": $0] }
              ) else {
            return nil
        }
        return (body, response)
    }

    // MARK: Keys

    /// What identifies a request: its method and URL, with the query sorted so
    /// parameter order doesn't matter, and with any search bound on
    /// `created_at_i` wildcarded. Those bounds are computed from the current
    /// time ("stories from the last week"), so left in they'd never match a
    /// recording made at another moment.
    static func key(for request: URLRequest) -> String? {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        let query = (components.queryItems ?? [])
            .map { "\($0.name)=\(normalized($0.value ?? ""))" }
            .sorted()
            .joined(separator: "&")
        components.query = nil
        components.fragment = nil
        let method = request.httpMethod ?? "GET"
        return "\(method) \(components.string ?? url.absoluteString)" + (query.isEmpty ? "" : "?\(query)")
    }

    private static func normalized(_ value: String) -> String {
        value.replacing(/(created_at_i[<>=]+)\d+/) { "\($0.output.1)*" }
    }

    /// A stable file name for a key's body.
    static func fileName(for key: String, contentType: String?) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
            .prefix(10)
            .map { String(format: "%02x", $0) }
            .joined()
        let ext = switch contentType {
        case let type? where type.contains("json"): "json"
        case let type? where type.contains("html"): "html"
        default: "bin"
        }
        return "\(digest).\(ext)"
    }
}

/// A transport that never touches the network: it answers every request from
/// a `FixtureStore`, for UI tests and offline development.
///
/// Anything not recorded is answered with a 404 and logged under the
/// `Fixtures` category, so a gap in the recording shows up as an empty list
/// and a log line rather than a hang. Writes and logins are refused the way
/// Hacker News refuses them, so the app reports a failure and nothing is sent.
nonisolated struct FixtureTransport: HTTPTransport {
    let store: FixtureStore

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Huck", category: "Fixtures")

    func data(
        for request: URLRequest,
        kind: RequestKind,
        endpoint: String?
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw NetworkError.badUrl }
        switch kind {
        case .write, .login:
            // HN re-renders the form with a 200 when it refuses a write, and
            // a refused login carries no cookie.
            return (Data(), Self.response(url: url, status: 200))
        case .standard, .thumbnail:
            if let recorded = store.response(to: request) {
                return recorded
            }
            // Thumbnails come from arbitrary article hosts and aren't
            // recorded; their absence isn't a gap worth reporting.
            if kind == .standard {
                Self.log.error("No fixture for \(Self.describe(request), privacy: .public)")
            }
            return (Data(), Self.response(url: url, status: 404))
        }
    }

    private static func response(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private static func describe(_ request: URLRequest) -> String {
        FixtureStore.key(for: request) ?? request.url?.absoluteString ?? "request"
    }
}
#endif
