//
//  JSONFile.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import Foundation
import OSLog

/// Reads and writes a `Codable` value as one JSON file, logging anything
/// unexpected. The app's persistence types each own a file's location and shape;
/// this owns how it gets to and from disk.
nonisolated enum JSONFile {
    /// The value stored at `url`, or `nil` if there isn't a usable one.
    ///
    /// A missing file is the ordinary first-launch case and isn't logged. A file
    /// that exists but can't be read or decoded is: the caller falls back to
    /// empty state, and its next save overwrites what was there, so this is
    /// the only trace that data was lost.
    ///
    /// - Parameter name: What the file holds, for the log.
    static func load<Value: Decodable>(_ type: Value.Type, from url: URL, name: String) -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Logger.persistence.error("Couldn't read \(name, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            // We wrote this file, so a mismatch means a model changed without
            // keeping the old shape decodable.
            Logger.persistence.fault("Discarding \(name, privacy: .public) that didn't decode: \(error, privacy: .public)")
            return nil
        }
    }

    /// Writes `value` to `url` atomically, creating its directory if needed.
    static func save(_ value: some Encodable, to url: URL, name: String) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            Logger.persistence.error("Couldn't save \(name, privacy: .public): \(error, privacy: .public)")
        }
    }
}
