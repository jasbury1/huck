//
//  LinkedItemView.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// An item reached by a link to Hacker News, shown in its thread.
///
/// A link names only an id, which may be a story or a comment anywhere in a
/// thread. The push happens straight away and the item is resolved here, so
/// the tap responds immediately; a comment then opens as the thread it's
/// part of, scrolled to it.
struct LinkedItemView: View {
    let itemID: Int
    @Binding var path: NavigationPath

    private enum Resolution {
        case loading
        case found(ThreadLocation)
        case missing
    }

    @State private var resolution = Resolution.loading

    var body: some View {
        Group {
            switch resolution {
            case .loading:
                ProgressView()
            case let .found(location):
                StoryTextView(storyId: location.storyID, path: $path, scrollTo: location.commentID)
            case .missing:
                ContentUnavailableView(
                    "Couldn't Open Link",
                    systemImage: "link",
                    description: Text("This post may have been deleted, or the connection was lost.")
                )
            }
        }
        .task(id: itemID) {
            guard case .loading = resolution else { return }
            if let location = await HackerNewsAPI.threadLocation(ofItem: itemID) {
                resolution = .found(location)
            } else if !Task.isCancelled {
                resolution = .missing
            }
        }
    }
}
