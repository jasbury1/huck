//
//  CollectionsStore.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// The single source of truth for the device's collections — named, ordered
/// lists of story ids. Collections never touch Hacker News, so they don't
/// depend on being signed in: they belong to the device, are saved locally, and
/// sync across the user's devices through iCloud (`CollectionsCloudSync`).
/// Injected app-wide via the environment and observed by the home feed's "Your
/// Collections" section and the story options menu.
@MainActor
@Observable
final class CollectionsStore {
    /// The collections, in creation order — the store's single observed
    /// property, so reads in a view body refresh when it mutates.
    private(set) var collections: [StoryCollection] = []

    /// Ids of the collections this device has seen in iCloud; see
    /// `PersistedCollections.syncedIDs`.
    private var syncedIDs: Set<UUID> = []

    init() {
        let stored = CollectionsPersistence.load()
        collections = stored.collections.sorted { $0.createdAt < $1.createdAt }
        syncedIDs = stored.syncedIDs
        CollectionsCloudSync.synchronize()
        reconcileWithCloud()
    }

    /// Applies changes iCloud delivers from the user's other devices, for as
    /// long as the calling task runs. Start it once, at the app's root.
    func observeCloudChanges() async {
        guard CollectionsCloudSync.isEnabled else { return }
        for await change in CollectionsCloudSync.changes() {
            if change == .accountChanged {
                // A different iCloud account's collections replaced the old
                // ones, so nothing this device synced before applies. Forget it,
                // so local collections are merged into the new account rather
                // than mistaken for deletions.
                syncedIDs = []
            }
            reconcileWithCloud()
        }
    }

    /// Whether the user is under the collection cap and may create another.
    var canCreateCollection: Bool {
        collections.count < CollectionsPersistence.maxCollections
    }

    /// Creates a collection with a trimmed `name`, appends it, and persists.
    /// Returns the new collection, or `nil` if the cap is reached or the name is
    /// blank.
    @discardableResult
    func createCollection(named name: String) -> StoryCollection? {
        guard canCreateCollection else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collection = StoryCollection(name: trimmed)
        collections.append(collection)
        upload(collection)
        persist()
        return collection
    }

    /// Adds a story to a collection, then persists. No-op if the story is already
    /// in it or the collection no longer exists.
    func addStory(_ storyID: Int, to collectionID: StoryCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }),
              !collections[index].storyIDs.contains(storyID) else { return }
        collections[index].storyIDs.append(storyID)
        didModify(at: index)
    }

    /// Removes a story from a collection, then persists.
    func removeStory(_ storyID: Int, from collectionID: StoryCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].storyIDs.removeAll { $0 == storyID }
        didModify(at: index)
    }

    /// Whether a collection already contains a story — drives the checkmarks in
    /// the "Add to Collection" picker.
    func collection(_ collectionID: StoryCollection.ID, contains storyID: Int) -> Bool {
        collections.first { $0.id == collectionID }?.storyIDs.contains(storyID) ?? false
    }

    /// Deletes a collection entirely — here and, through iCloud, on the user's
    /// other devices — then persists.
    func deleteCollection(_ collectionID: StoryCollection.ID) {
        collections.removeAll { $0.id == collectionID }
        CollectionsCloudSync.remove(collectionID)
        syncedIDs.remove(collectionID)
        persist()
    }

    // MARK: - Sync

    /// Stamps a just-edited collection, uploads it, and persists.
    private func didModify(at index: Int) {
        collections[index].modifiedAt = .now
        upload(collections[index])
        persist()
    }

    /// Sends a collection to iCloud and, if iCloud is really syncing, records it
    /// as synced so its later absence there reads as a deletion.
    private func upload(_ collection: StoryCollection) {
        CollectionsCloudSync.save(collection)
        if CollectionsCloudSync.isAvailable {
            syncedIDs.insert(collection.id)
        }
    }

    /// Merges iCloud's collections with the local ones:
    /// - in both: the more recently modified version wins on both sides;
    /// - only in iCloud: new from another device, so it's added here;
    /// - only here, and synced before: deleted on another device, so it goes;
    /// - only here, never synced: new on this device, so it's uploaded.
    ///
    /// Run at launch and on every change from iCloud. Signed out of iCloud, the
    /// store is just a local echo, so nothing is treated as a remote deletion.
    private func reconcileWithCloud() {
        let isAvailable = CollectionsCloudSync.isAvailable
        var remote = Dictionary(
            CollectionsCloudSync.collections().map { ($0.id, $0) },
            uniquingKeysWith: { $0.modifiedAt >= $1.modifiedAt ? $0 : $1 }
        )

        var merged: [StoryCollection] = []
        for local in collections {
            if let cloud = remote.removeValue(forKey: local.id) {
                if cloud.modifiedAt > local.modifiedAt {
                    merged.append(cloud)
                } else {
                    if local.modifiedAt > cloud.modifiedAt { CollectionsCloudSync.save(local) }
                    merged.append(local)
                }
            } else if isAvailable && syncedIDs.contains(local.id) {
                continue
            } else {
                CollectionsCloudSync.save(local)
                merged.append(local)
            }
        }
        merged.append(contentsOf: remote.values)
        merged.sort { $0.createdAt < $1.createdAt }

        if isAvailable {
            syncedIDs = Set(merged.map(\.id))
        }
        // Only publish a real change, so views observing `collections` (and
        // the feeds reloading off them) don't churn on no-op syncs.
        if merged != collections {
            collections = merged
        }
        persist()
    }

    private func persist() {
        CollectionsPersistence.save(PersistedCollections(collections: collections, syncedIDs: syncedIDs))
    }
}
