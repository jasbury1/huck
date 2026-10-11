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
    /// When the collection was made. Collections are listed in creation order,
    /// which lets each one sync independently without a separate order record.
    let createdAt: Date
    /// When the collection last changed — the tiebreak when two devices hold
    /// different versions of it, the newer one winning.
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, storyIDs: [Int] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.storyIDs = storyIDs
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }
}

/// The device's collections in the shape we persist to disk. A struct (rather
/// than a bare array) so sync bookkeeping can live alongside the collections.
struct PersistedCollections: Codable {
    var collections: [StoryCollection] = []
    /// Ids of the collections this device has seen in iCloud. A collection in
    /// this set that later goes missing from iCloud was deleted on another
    /// device; one not in it is new here and still needs uploading.
    var syncedIDs: Set<UUID> = []
}

/// Loads and saves `PersistedCollections` as a single JSON file in Application
/// Support. Collections belong to the device, not to a Hacker News account, so
/// there's one file regardless of who is signed in. This local copy is the
/// source of truth; `CollectionsCloudSync` mirrors it to iCloud.
enum CollectionsPersistence {
    /// The largest number of collections a user may create.
    static let maxCollections = 5

    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent("collections.json")
    }

    /// The stored collections, or empty state if nothing is saved yet.
    static func load() -> PersistedCollections {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedCollections.self, from: data) else {
            return PersistedCollections()
        }
        return decoded
    }

    /// Writes the collections atomically.
    static func save(_ collections: PersistedCollections) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(collections)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to persist collections: \(error)")
        }
    }
}
