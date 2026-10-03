//
//  CollectionDeletion.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// Asks the reader to confirm deleting one of their collections, then deletes
/// it — the same exchange from the home screen's swipe action and from the
/// collection's own options menu.
private struct CollectionDeletionModifier: ViewModifier {
    @Binding var target: StoryCollection?
    let onDeleted: () -> Void

    @Environment(CollectionsStore.self) private var collectionsStore

    func body(content: Content) -> some View {
        content
            .alert("Delete “\(target?.name ?? "Collection")”?", item: $target) { collection in
                Button("Delete", role: .destructive) {
                    onDeleted()
                    withAnimation {
                        collectionsStore.deleteCollection(collection.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone.")
            }
    }
}

extension View {
    /// Confirms and performs deletion of a collection whenever `target` is set.
    /// `onDeleted` runs just before the collection is removed — the moment for
    /// a view showing it to get out of the way.
    func confirmsCollectionDeletion(
        of target: Binding<StoryCollection?>,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(CollectionDeletionModifier(target: target, onDeleted: onDeleted))
    }
}
