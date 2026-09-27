//
//  InteractionPersistence.swift
//  HuckApp
//
//  Created by James Asbury on 8/16/26.
//

import Foundation

/// The user's interaction state, in the shape we persist to disk.
///
/// `hidden` is here so that feature can be added later without a storage
/// migration — an older file simply decodes it as an empty set. (A separate
/// `saved` concept is planned for the future.)
struct PersistedInteractions: Codable {
    /// Upvoted *stories*.
    var upvoted: Set<Int> = []

    /// Upvoted *comments*, kept apart from `upvoted` rather than pooled with it
    /// even though Hacker News item ids share one namespace.
    ///
    /// They have to be: `/upvoted` lists only stories, and when a walk of it
    /// completes it is treated as the whole truth for what it covers, replacing
    /// the set. Pooled, every comment vote would be erased the first time the
    /// story list was read to its end.
    var upvotedComments: Set<Int> = []

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
