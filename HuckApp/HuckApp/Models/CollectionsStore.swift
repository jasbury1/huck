//
//  CollectionsStore.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// The single source of truth for the current user's collections — named,
/// ordered lists of story ids. Mirrors `InteractionStore`: one file per user,
/// reloaded on login, injected app-wide via the environment and observed by the
/// home feed's "Your Collections" section and the story options menu.
@MainActor
@Observable
final class CollectionsStore {
    /// The current user's collections, in creation order — the store's single
    /// observed property, so reads in a view body refresh when it mutates.
    private(set) var collections: [StoryCollection] = []

    /// The user the loaded collections belong to; `nil` when logged out.
    private var username: String?

    init() {
        loadForCurrentUser()
    }

    /// (Re)loads collections for whoever is logged in. Call after a login/logout
    /// so the store reflects the active account.
    func loadForCurrentUser() {
        username = UserSession.shared?.username
        collections = username.map { CollectionsPersistence.load(username: $0).collections } ?? []
    }

    /// Whether the user is under the collection cap and may create another.
    var canCreateCollection: Bool {
        collections.count < CollectionsPersistence.maxCollections
    }

    /// Creates a collection with a trimmed `name`, appends it, and persists.
    /// Returns the new collection, or `nil` if no user is signed in, the cap is
    /// reached, or the name is blank.
    @discardableResult
    func createCollection(named name: String) -> StoryCollection? {
        guard username != nil, canCreateCollection else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collection = StoryCollection(name: trimmed)
        collections.append(collection)
        persist()
        return collection
    }

    /// Adds a story to a collection, then persists. No-op if the story is already
    /// in it or the collection no longer exists.
    func addStory(_ storyID: Int, to collectionID: StoryCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }),
              !collections[index].storyIDs.contains(storyID) else { return }
        collections[index].storyIDs.append(storyID)
        persist()
    }

    /// Removes a story from a collection, then persists.
    func removeStory(_ storyID: Int, from collectionID: StoryCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].storyIDs.removeAll { $0 == storyID }
        persist()
    }

    /// Whether a collection already contains a story — drives the checkmarks in
    /// the "Add to Collection" picker.
    func collection(_ collectionID: StoryCollection.ID, contains storyID: Int) -> Bool {
        collections.first { $0.id == collectionID }?.storyIDs.contains(storyID) ?? false
    }

    /// Deletes a collection entirely, then persists.
    func deleteCollection(_ collectionID: StoryCollection.ID) {
        collections.removeAll { $0.id == collectionID }
        persist()
    }

    private func persist() {
        guard let username else { return }
        CollectionsPersistence.save(PersistedCollections(collections: collections), username: username)
    }
}
