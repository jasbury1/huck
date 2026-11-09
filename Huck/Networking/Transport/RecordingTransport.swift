//
//  RecordingTransport.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

#if DEBUG
import Foundation
import OSLog

/// The live transport, with every response it may keep saved to a
/// `FixtureStore` on disk as it arrives — how the fixtures are made.
///
/// Only anonymous reads of the three Hacker News sources are kept: `GET`s to
/// Algolia, Firebase and news.ycombinator.com that succeeded. Nothing is kept
/// from a write, a login, a thumbnail host, or any page fetched while signed
/// in, because a signed-in page carries the reader's name and per-user tokens.
/// Requests still go out either way; recording only decides what's saved.
nonisolated struct RecordingTransport: HTTPTransport {
    let recorder: FixtureRecorder
    private let live = URLSessionTransport()

    private static let recordedHosts: Set = ["hn.algolia.com", "hacker-news.firebaseio.com", "news.ycombinator.com"]

    func data(
        for request: URLRequest,
        kind: RequestKind,
        endpoint: String?
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await live.data(for: request, kind: kind, endpoint: endpoint)
        if kind == .standard,
           (request.httpMethod ?? "GET") == "GET",
           (200..<300).contains(response.statusCode),
           let host = request.url?.host(), Self.recordedHosts.contains(host),
           !Self.isSignedIn {
            await recorder.record(data, response: response, for: request)
        }
        return (data, response)
    }

    private static var isSignedIn: Bool {
        let cookies = HTTPCookieStorage.shared.cookies(for: HackerNewsAPI.baseUri) ?? []
        return cookies.contains { $0.name == "user" }
    }
}

/// Writes recorded responses into a fixture directory, one body file and one
/// manifest line each.
actor FixtureRecorder {
    let directory: URL
    private var manifest: FileHandle?

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Huck", category: "Fixtures")

    /// Where a recording session writes: the app's Documents, from which
    /// `scripts/pull-fixtures.sh` copies it into the bundled fixtures.
    static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "FixtureRecording")
    }

    init(directory: URL) {
        self.directory = directory
    }

    func record(_ body: Data, response: HTTPURLResponse, for request: URLRequest) {
        guard let key = FixtureStore.key(for: request) else { return }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        let file = FixtureStore.fileName(for: key, contentType: contentType)
        let entry = FixtureStore.Entry(key: key, status: response.statusCode, contentType: contentType, file: file)
        do {
            // The manifest first: opening it creates the directory.
            let manifest = try manifestHandle()
            try body.write(to: directory.appending(path: file))
            var line = try JSONEncoder().encode(entry)
            line.append(UInt8(ascii: "\n"))
            try manifest.write(contentsOf: line)
        } catch {
            Self.log.error("Couldn't record \(key, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func manifestHandle() throws -> FileHandle {
        if let manifest { return manifest }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: FixtureStore.manifestName)
        if !FileManager.default.fileExists(atPath: url.path()) {
            FileManager.default.createFile(atPath: url.path(), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        manifest = handle
        let path = directory.path()
        Self.log.info("Recording fixtures to \(path, privacy: .public)")
        return handle
    }
}
#endif
