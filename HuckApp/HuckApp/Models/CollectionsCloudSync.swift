//
//  CollectionsCloudSync.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import Foundation

/// Mirrors collections to the iCloud key-value store so they follow the user
/// across their devices. The local file (`CollectionsPersistence`) stays the
/// source of truth — this is only the transport — so collections keep working
/// with iCloud signed out, and nothing essential depends on iCloud.
///
/// Each collection is stored under its own key rather than all of them under
/// one. The key-value store resolves conflicts per key, last writer wins, so
/// two devices editing *different* collections never overwrite each other, and
/// deleting a collection is just removing its key. The data is tiny — a few
/// collections of story ids — far inside the store's 1 MB quota.
enum CollectionsCloudSync {
    /// What happened when iCloud changed underneath us.
    enum Change {
        /// Another device changed one or more collections, or the first
        /// download from iCloud arrived.
        case updated
        /// The device switched iCloud accounts, so the store now holds a
        /// different account's collections.
        case accountChanged
    }

    /// Whether this build syncs at all (`BuildConfiguration.isCloudSyncEnabled`).
    /// While off, every method here is a no-op and collections stay on the
    /// device.
    static var isEnabled: Bool { BuildConfiguration.isCloudSyncEnabled }

    private static let keyPrefix = "collection."
    private static var store: NSUbiquitousKeyValueStore { .default }

    /// Whether sync is on and the device is signed in to iCloud. When it isn't,
    /// nothing syncs — so a missing collection in the store says nothing about
    /// whether another device deleted it.
    static var isAvailable: Bool {
        isEnabled && FileManager.default.ubiquityIdentityToken != nil
    }

    /// Every collection currently in iCloud.
    static func collections() -> [StoryCollection] {
        guard isEnabled else { return [] }
        let decoder = JSONDecoder()
        return store.dictionaryRepresentation.compactMap { key, value in
            guard key.hasPrefix(keyPrefix), let data = value as? Data else { return nil }
            return try? decoder.decode(StoryCollection.self, from: data)
        }
    }

    /// Uploads a collection, replacing any earlier version of it.
    static func save(_ collection: StoryCollection) {
        guard isEnabled, let data = try? JSONEncoder().encode(collection) else { return }
        store.set(data, forKey: key(for: collection.id))
    }

    /// Removes a collection from iCloud, which deletes it on the user's other
    /// devices.
    static func remove(_ id: StoryCollection.ID) {
        guard isEnabled else { return }
        store.removeObject(forKey: key(for: id))
    }

    /// Asks the store to exchange changes with iCloud soon. Call at launch, as
    /// Apple recommends, so changes made elsewhere arrive promptly.
    static func synchronize() {
        guard isEnabled else { return }
        store.synchronize()
    }

    /// Changes iCloud delivers from other devices, for as long as the caller
    /// iterates. Quota violations are logged rather than surfaced: they can't
    /// realistically happen at this data size, and the local copy is intact.
    static func changes() -> some AsyncSequence<Change, Never> {
        // No `object` filter: the store isn't `Sendable`, and the default
        // store is the only one in the app, so every notification is its.
        NotificationCenter.default
            .notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .compactMap { notification -> Change? in
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                switch reason {
                case NSUbiquitousKeyValueStoreAccountChange:
                    return .accountChanged
                case NSUbiquitousKeyValueStoreQuotaViolationChange:
                    print("iCloud key-value quota exceeded while syncing collections")
                    return nil
                default:
                    return .updated
                }
            }
    }

    private static func key(for id: StoryCollection.ID) -> String {
        keyPrefix + id.uuidString
    }
}
