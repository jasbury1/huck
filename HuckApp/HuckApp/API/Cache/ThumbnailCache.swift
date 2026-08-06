//
//  ThumbnailCache.swift
//  HuckApp
//
//  Created by James Asbury on 8/2/26.
//

import UIKit
import ImageIO

/// A thread-safe, in-memory cache of story thumbnail images, keyed by page URL.
///
/// Story cells need a small preview image for the linked page. Rather than using
/// `LPMetadataProvider` — which spins up a headless WebKit process per URL and
/// downloads the whole page plus its subresources — we fetch the page's
/// Open Graph image directly with a plain `URLSession`, falling back to the
/// site's favicon. This is dramatically cheaper and keeps the console free of
/// WebContent-process and cancellation noise.
///
/// Being an `actor` isolates its mutable state so the many story cells fetching
/// at once can never race on the underlying storage. It mirrors `StoryCache`:
///  - **Request coalescing:** concurrent requests for the same URL share a
///    single network fetch (tracked in `inFlight`).
///  - **Bounded concurrency:** at most `maxConcurrentFetches` network fetches
///    run at once (via `gate`). This matters because a paged `TabView`
///    (e.g. the profile screen) realises its whole list at once, so every cell
///    would otherwise fire a fetch simultaneously and flood the network.
///  - **Off-main downsampling:** fetched images are decoded and shrunk to the
///    thumbnail's pixel size *here*, off the main thread, so SwiftUI never
///    decodes a full-size image at draw time (which was freezing the UI).
///  - **Detached fetches:** the work runs in an unstructured `Task`, so a cell
///    scrolling off-screen (which cancels its `.task`) does not cancel or waste
///    the fetch — it completes and is cached for the next appearance.
///  - **LRU eviction:** the cache is bounded to `capacity` entries; the least
///    recently used image is dropped when it overflows.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Completed thumbnail images (already downsampled and decoded).
    private var entries: [URL: UIImage] = [:]
    /// Recency order for `entries`; most-recently-used URL is last.
    private var lru: [URL] = []
    /// In-progress fetches, so concurrent requests for one URL are coalesced.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// Maximum number of completed entries to retain.
    private let capacity = 200

    private init() {}

    /// Returns a thumbnail for the given page, fetching it if necessary.
    /// Concurrent calls for the same URL share one network request.
    func thumbnail(for pageURL: URL) async -> UIImage? {
        // Cache hit.
        if let image = entries[pageURL] {
            touch(pageURL)
            return image
        }
        // A fetch for this URL is already running — await its result.
        if let existing = inFlight[pageURL] {
            return await existing.value
        }
        // Cache miss: start a fetch and record it *before* suspending, so that
        // any request arriving during the await coalesces onto this same task.
        let task = Task { await Self.fetchThumbnail(for: pageURL) }
        inFlight[pageURL] = task
        let image = await task.value
        inFlight[pageURL] = nil

        if let image {
            insert(image, for: pageURL)
        }
        return image
    }

    /// Warms the cache for the given page URLs ahead of display without blocking
    /// the caller. Each URL flows through the same coalescing and gated path as
    /// `thumbnail(for:)`, so this never exceeds the concurrency cap nor duplicates
    /// a fetch already cached or in flight. Because the gate is LIFO, this
    /// prefetch work yields to any thumbnail a visible cell requests afterward.
    func prefetch(urls: [URL]) {
        for url in urls where entries[url] == nil && inFlight[url] == nil {
            Task { _ = await self.thumbnail(for: url) }
        }
    }

    // MARK: - Fetching

    /// A shared session with short timeouts, tuned for fetching small assets.
    /// Timeouts are intentionally low so dead or slow hosts fail fast rather
    /// than leaving a cell spinning for tens of seconds.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Caps how many fetches touch the network at once, so realising a whole
    /// list of cells simultaneously doesn't launch dozens of parallel requests.
    private static let gate = AsyncSemaphore(value: 6)

    /// Target thumbnail size in pixels (70pt cell at ~2x). Images are downsampled
    /// to this so we never hold or decode a full-resolution asset.
    private static let thumbnailMaxPixelSize = 140

    /// A desktop-ish User-Agent; some sites omit Open Graph tags otherwise.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static func fetchThumbnail(for pageURL: URL) async -> UIImage? {
        await gate.wait()
        let image = await loadThumbnail(for: pageURL)
        await gate.signal()
        return image
    }

    private static func loadThumbnail(for pageURL: URL) async -> UIImage? {
        // 1. Prefer the page's Open Graph / Twitter card image.
        if let imageURL = await openGraphImageURL(for: pageURL),
           let image = await downloadImage(from: imageURL) {
            return image
        }
        // 2. Fall back to the site's favicon.
        if let faviconURL = faviconURL(for: pageURL),
           let image = await downloadImage(from: faviconURL) {
            return image
        }
        return nil
    }

    /// Downloads the page HTML and extracts the `og:image` (or Twitter card)
    /// URL, resolved against the page URL.
    private static func openGraphImageURL(for pageURL: URL) async -> URL? {
        var request = URLRequest(url: pageURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        // The tags we need live in <head>; decode a bounded prefix so we don't
        // stringify multi-megabyte pages.
        let prefix = data.prefix(256_000)
        guard let html = String(data: prefix, encoding: .utf8)
                ?? String(data: prefix, encoding: .isoLatin1) else {
            return nil
        }

        guard let content = metaContent(
            in: html,
            for: ["og:image", "og:image:url", "og:image:secure_url",
                  "twitter:image", "twitter:image:src"]
        ) else {
            return nil
        }

        // Content is a URL that may be relative or protocol-relative, and may
        // carry HTML-escaped ampersands.
        let unescaped = content.replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: unescaped, relativeTo: pageURL)?.absoluteURL
    }

    private static func faviconURL(for pageURL: URL) -> URL? {
        guard let host = pageURL.host else { return nil }
        // Google's favicon service returns a reasonably sized, reliable icon
        // with its own fallbacks — ideal for a small feed thumbnail.
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")
    }

    private static func downloadImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        // Downsample + decode here, off the main thread.
        return downsampledImage(from: data)
    }

    /// Decodes `data` into a thumbnail-sized, fully-decoded `UIImage` using
    /// ImageIO. Downsampling keeps memory tiny and, crucially,
    /// `kCGImageSourceShouldCacheImmediately` forces the decode to happen now
    /// (on this background executor) rather than lazily on the main thread when
    /// SwiftUI draws the image.
    private static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - HTML parsing

    /// Returns the `content` value of the first `<meta>` tag whose `property`
    /// or `name` attribute matches one of `keys` (case-insensitive).
    private static func metaContent(in html: String, for keys: [String]) -> String? {
        let wanted = Set(keys.map { $0.lowercased() })
        let metaPattern = "<meta\\b[^>]*>"
        guard let metaRegex = try? NSRegularExpression(
            pattern: metaPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        for match in metaRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                  wanted.contains(key.lowercased()) else { continue }

            if let content = attribute("content", in: tag), !content.isEmpty {
                return content
            }
        }
        return nil
    }

    /// Extracts a single-, double-, or unquoted HTML attribute value from a tag.
    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range) else { return nil }

        for group in 1...3 {
            if let valueRange = Range(match.range(at: group), in: tag) {
                return String(tag[valueRange])
            }
        }
        return nil
    }

    // MARK: - Storage helpers

    private func insert(_ image: UIImage, for url: URL) {
        entries[url] = image
        touch(url)
        evictIfNeeded()
    }

    /// Marks `url` as most-recently-used.
    private func touch(_ url: URL) {
        if let index = lru.firstIndex(of: url) {
            lru.remove(at: index)
        }
        lru.append(url)
    }

    /// Drops least-recently-used entries until we are within `capacity`.
    private func evictIfNeeded() {
        while entries.count > capacity, let oldest = lru.first {
            lru.removeFirst()
            entries[oldest] = nil
        }
    }
}

/// A minimal LIFO async semaphore used to bound concurrent thumbnail fetches.
/// Callers `wait()` before starting work and `signal()` when done.
///
/// Waiters are resumed most-recent-first. When the user scrolls fast, every
/// passed cell queues a fetch; serving newest-first means the rows now on screen
/// (whose requests arrived last) get the network ahead of the stale backlog of
/// cells already scrolled past — and prefetch-ahead work naturally yields to a
/// row scrolling into view. The trade-off is that the oldest waiters can be
/// starved while requests keep arriving, which is acceptable here: those are
/// off-screen fetches, and once scrolling stops the whole backlog drains.
private actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        available = value
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeLast().resume()
        }
    }
}
