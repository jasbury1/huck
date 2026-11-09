//
//  HTTPTransport.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import Foundation

/// Which kind of session a request needs. Each kind has its own cookie and
/// redirect behaviour, and the transport picks the session to match.
nonisolated enum RequestKind: Sendable {
    /// Reads from the APIs and Hacker News' pages, with the shared cookie jar.
    case standard
    /// A thumbnail from an arbitrary article host: no cookies, short timeouts.
    case thumbnail
    /// A form POST that writes to Hacker News. Sends the shared cookies but
    /// doesn't follow redirects, because HN answers an accepted write with a
    /// 302 and a refused one with a 200 — following it would hide which.
    case write
    /// The login POST. Stores no cookies itself and doesn't follow redirects:
    /// success is a 302 whose `Set-Cookie` is the credential.
    case login
}

/// Sends HTTP requests for the API layer's services.
///
/// The one seam between the app and the network: the live transport goes out
/// to the internet, while tests and fixture builds swap in one that replays
/// recorded responses. Services build requests and parse what comes back; how
/// the bytes travel is this type's business alone.
nonisolated protocol HTTPTransport: Sendable {
    /// Sends `request` through the session suited to `kind`.
    ///
    /// - Parameter endpoint: Overrides the endpoint name the debug screen's
    ///   request counts derive from the URL, for hosts without a known shape.
    func data(
        for request: URLRequest,
        kind: RequestKind,
        endpoint: String?
    ) async throws -> (Data, HTTPURLResponse)
}

extension HTTPTransport {
    /// Sends an ordinary read.
    nonisolated func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request, kind: .standard, endpoint: nil)
    }

    /// Fetches and decodes JSON, or `nil` if the request fails, the status
    /// isn't 2xx, or the body doesn't decode. `@concurrent`, so the decoding
    /// runs on the global executor rather than the caller's: most callers are
    /// main-actor code, and the launch warm-up alone decodes hundreds of
    /// stories, which would otherwise all land on the main thread.
    @concurrent
    nonisolated func json<T: Decodable & Sendable>(from url: URL) async -> T? {
        do {
            let (data, response) = try await data(for: URLRequest(url: url))
            guard (200..<300).contains(response.statusCode) else {
                print("Status \(response.statusCode) from \(url)")
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Couldn't load \(T.self) from \(url): \(error)")
            return nil
        }
    }

    /// `json(from:)` for a URL string, `nil` if it isn't a valid URL.
    nonisolated func json<T: Decodable & Sendable>(fromURL string: String) async -> T? {
        guard let url = URL(string: string) else { return nil }
        return await json(from: url)
    }
}

/// The transport that goes out to the network, through `URLSession`, with
/// every request counted in `APIMetrics`.
nonisolated struct URLSessionTransport: HTTPTransport {
    func data(
        for request: URLRequest,
        kind: RequestKind,
        endpoint: String?
    ) async throws -> (Data, HTTPURLResponse) {
        let session = switch kind {
        case .standard: URLSession.shared
        case .thumbnail: Self.thumbnailSession
        case .write: Self.writeSession
        case .login: Self.loginSession
        }
        // The redirect-blocking sessions carry the blocker as their delegate,
        // and it's passed per task too, which is what async `data(for:)` uses.
        let delegate: RedirectBlocker? = switch kind {
        case .write, .login: RedirectBlocker()
        case .standard, .thumbnail: nil
        }
        let (data, response) = try await session.countedData(for: request, delegate: delegate, endpoint: endpoint)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        return (data, http)
    }

    /// Short timeouts, tuned for small assets: dead or slow hosts fail fast
    /// rather than leaving a cell spinning for tens of seconds.
    private static let thumbnailSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Keeps the `user` cookie, so HN knows who is writing, but doesn't follow
    /// redirects: here the redirect *is* the result.
    private static let writeSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    /// Stores no cookies itself — the login flow reads the credential from the
    /// response — and doesn't follow the redirect that carries it.
    private static let loginSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }()
}

/// Refuses every redirect, so the response that would have redirected is the
/// one returned.
final nonisolated class RedirectBlocker: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
