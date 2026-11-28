//
//  BlockedUsersPersistence.swift
//  Huck
//
//  Created by James Asbury on 11/27/26.
//

import Foundation

/// The blocked usernames, in the shape we persist to disk.
struct PersistedBlockedUsers: Codable {
    var usernames: Set<String> = []
}

/// Loads and saves `PersistedBlockedUsers` as a single JSON file in Application
/// Support. One file for the device rather than one per account, as with
/// interactions: blocking is about what the reader sees, signed in or not.
enum BlockedUsersPersistence {
    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("BlockedUsers", isDirectory: true)
            .appendingPathComponent("store.json")
    }

    /// The stored usernames, or none if nothing is saved yet.
    static func load() -> PersistedBlockedUsers {
        JSONFile.load(PersistedBlockedUsers.self, from: fileURL, name: "blocked users") ?? PersistedBlockedUsers()
    }

    /// Writes the usernames atomically.
    static func save(_ blocked: PersistedBlockedUsers) {
        JSONFile.save(blocked, to: fileURL, name: "blocked users")
    }
}
