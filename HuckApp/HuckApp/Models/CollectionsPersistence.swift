//
//  CollectionsPersistence.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// A user-created collection: a named, ordered list of the story ids the user
/// has gathered. Order is preserved so a collection can show its stories in the
/// order they were added.
struct StoryCollection: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var storyIDs: [Int]

    init(id: UUID = UUID(), name: String, storyIDs: [Int] = []) {
        self.id = id
        self.name = name
        self.storyIDs = storyIDs
    }
}

/// The user's collections in the shape we persist to disk. A struct (rather than
/// a bare array) so future per-user collection metadata can be added without a
/// storage migration — an older file simply decodes the new fields as defaults.
struct PersistedCollections: Codable {
    var collections: [StoryCollection] = []
}

/// Loads and saves `PersistedCollections` as JSON in Application Support, one
/// file per username so switching accounts keeps collections separate — the same
/// per-user layout as `InteractionPersistence`.
enum CollectionsPersistence {
    /// The largest number of collections a user may create.
    static let maxCollections = 5

    private static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Collections", isDirectory: true)
    }

    private static func fileURL(username: String) -> URL {
        // Percent-encode so any username is a valid file name.
        let safe = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? username
        return directory.appendingPathComponent("\(safe).json")
    }

    /// The stored collections for a user, or empty state if nothing is saved yet.
    static func load(username: String) -> PersistedCollections {
        guard let data = try? Data(contentsOf: fileURL(username: username)),
              let decoded = try? JSONDecoder().decode(PersistedCollections.self, from: data) else {
            return PersistedCollections()
        }
        return decoded
    }

    /// Writes a user's collections atomically.
    static func save(_ collections: PersistedCollections, username: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(collections)
            try data.write(to: fileURL(username: username), options: [.atomic])
        } catch {
            print("Failed to persist collections: \(error)")
        }
    }
}
