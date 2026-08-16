//
//  InteractionPersistence.swift
//  HuckApp
//
//  Created by James Asbury on 8/16/26.
//

import Foundation

/// The user's per-story interaction state, in the shape we persist to disk.
///
/// Only `upvoted` is used today; `favorited` and `hidden` are here so those features
/// can be added later without a storage migration — an older file simply decodes
/// them as empty sets. (A separate `saved` concept is planned for the future.)
struct PersistedInteractions: Codable {
    var upvoted: Set<Int> = []
    var favorited: Set<Int> = []
    var hidden: Set<Int> = []
}

/// Loads and saves `PersistedInteractions` as JSON in Application Support, one file
/// per username so switching accounts keeps state separate.
enum InteractionPersistence {
    private static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Interactions", isDirectory: true)
    }

    private static func fileURL(username: String) -> URL {
        // Percent-encode so any username is a valid file name.
        let safe = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? username
        return directory.appendingPathComponent("\(safe).json")
    }

    /// The stored interactions for a user, or empty state if nothing is saved yet.
    static func load(username: String) -> PersistedInteractions {
        guard let data = try? Data(contentsOf: fileURL(username: username)),
              let decoded = try? JSONDecoder().decode(PersistedInteractions.self, from: data) else {
            return PersistedInteractions()
        }
        return decoded
    }

    /// Writes the interactions for a user atomically.
    static func save(_ interactions: PersistedInteractions, username: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(interactions)
            try data.write(to: fileURL(username: username), options: [.atomic])
        } catch {
            print("Failed to persist interactions: \(error)")
        }
    }
}
