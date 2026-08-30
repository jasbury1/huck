//
//  AddToCollectionView.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// The picker presented from a story's "More" menu: lists the user's collections
/// with a checkmark on any that already contain the story, and tapping one
/// toggles the story's membership. A trailing "New Collection" control (shown
/// while under the cap) creates a collection and adds the story to it.
struct AddToCollectionView: View {
    let story: StoryModel

    @Environment(CollectionsStore.self) private var collectionsStore
    @Environment(\.dismiss) private var dismiss

    @State private var isNamingNewCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(collectionsStore.collections) { collection in
                        Button {
                            toggle(collection)
                        } label: {
                            HStack {
                                Label(collection.name, systemImage: "folder")
                                Spacer()
                                if collectionsStore.collection(collection.id, contains: story.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    if collectionsStore.collections.isEmpty {
                        Text("You haven't created any collections yet.")
                    }
                }

                if collectionsStore.canCreateCollection {
                    Button {
                        isNamingNewCollection = true
                    } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Collection", isPresented: $isNamingNewCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") {
                    if let created = collectionsStore.createCollection(named: newCollectionName) {
                        collectionsStore.addStory(story.id, to: created.id)
                    }
                    newCollectionName = ""
                }
            } message: {
                Text("Choose a name for your collection.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Adds the story to the collection, or removes it if it's already there.
    private func toggle(_ collection: StoryCollection) {
        if collectionsStore.collection(collection.id, contains: story.id) {
            collectionsStore.removeStory(story.id, from: collection.id)
        } else {
            collectionsStore.addStory(story.id, to: collection.id)
        }
    }
}
