//
//  ThreadSplitNavigation.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import SwiftUI

/// Opens a story's thread. Injected by `ThreadSplitNavigation`, which shows
/// threads opened from its leading column in the detail column beside it. The
/// default pushes onto the caller's own stack, so outside a split view — or
/// inside the detail column itself — a thread opens just as any other push.
struct OpenThreadAction {
    fileprivate let handler: (ItemNavigation, Binding<NavigationPath>) -> Void

    func callAsFunction(_ thread: ItemNavigation, from path: Binding<NavigationPath>) {
        handler(thread, path)
    }
}

extension EnvironmentValues {
    @Entry var openThread = OpenThreadAction { thread, path in
        path.wrappedValue.append(thread)
    }

    /// Whether this view is the root of a split view's leading column, where a
    /// `List` takes the sidebar style rather than inset grouped — so the view
    /// can adjust anything styled for the cards. Set only on the column's root:
    /// pages pushed above it don't inherit it.
    @Entry var isSidebarColumnRoot = false
}

/// A tab's navigation, adapting to the width it's given.
///
/// Compact, it's a single stack, as on any iPhone. Regular — an unfolded iPhone
/// Duo, iPad, or a wide window — `root` and everything pushed from it move to
/// the leading column, and threads opened there show in a detail column
/// alongside, so the list stays in view while reading. The detail column has
/// its own stack, so profiles and links followed from a thread push there.
///
/// `root` brings its own `navigationDestination`s; the detail column handles
/// `ItemNavigation` itself.
struct ThreadSplitNavigation<Root: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var root: () -> Root

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The thread at the root of the detail column, if one's been opened.
    @State private var selectedThread: ItemNavigation?
    /// Pages pushed within the detail column, above `selectedThread`.
    @State private var detailPath = NavigationPath()

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack(path: $path) {
                    root()
                }
                .inAppBrowser(path: $path)
            } else {
                splitView
            }
        }
        // Folding down to one column keeps the thread being read: it's pushed
        // onto the single stack. Anything pushed above it within the detail
        // column doesn't carry over, as the two paths can't be joined.
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            guard sizeClass == .compact, let thread = selectedThread else { return }
            path.append(thread)
            selectedThread = nil
            detailPath = NavigationPath()
        }
    }

    // Pages pushed within a split view's columns take their environment from
    // the split view, not from modifiers around the column's stack. So the
    // leading column's actions are set outside the split view, and the detail
    // column's are applied to each of its pages directly, overriding them.
    private var splitView: some View {
        NavigationSplitView {
            NavigationStack(path: $path) {
                root()
                    .environment(\.isSidebarColumnRoot, true)
            }
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    if let selectedThread {
                        StoryDetailsView(from: selectedThread, path: $detailPath)
                            // A fresh view per thread, so one thread's loaded
                            // state and scroll position don't carry into the next.
                            .id(selectedThread)
                    } else {
                        ContentUnavailableView(
                            "No Story Selected",
                            systemImage: "text.bubble",
                            description: Text("Choose a story's comments to read them here.")
                        )
                    }
                }
                .detailColumnActions(path: $detailPath)
                .navigationDestination(for: ItemNavigation.self) { navigation in
                    StoryDetailsView(from: navigation, path: $detailPath)
                        .detailColumnActions(path: $detailPath)
                }
            }
            // The system draws no divider between the columns here, and both
            // are white once a story list is pushed in the leading one, so
            // mark the edge the way a split view's hairline would.
            .overlay(alignment: .leading) {
                // In an `HStack`, so the divider runs vertically.
                HStack {
                    Divider()
                }
                .ignoresSafeArea()
            }
        }
        .inAppBrowser(path: $path)
        // Outside `inAppBrowser`, so links to threads followed in the leading
        // column open beside it as well.
        .environment(\.openThread, OpenThreadAction { thread, _ in
            selectedThread = thread
            detailPath = NavigationPath()
        })
    }
}

extension View {
    /// Sets a `List` on the grouped background when it's the root of a split
    /// view's leading column, so the sidebar reads as its own pane beside the
    /// white content. Elsewhere the list keeps its own background.
    func sidebarColumnBackground() -> some View {
        modifier(SidebarColumnBackgroundModifier())
    }
}

private struct SidebarColumnBackgroundModifier: ViewModifier {
    @Environment(\.isSidebarColumnRoot) private var isSidebarColumnRoot

    func body(content: Content) -> some View {
        if isSidebarColumnRoot {
            content
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
        } else {
            content
        }
    }
}

private extension View {
    /// The detail column's own navigation: threads opened within it push onto
    /// its stack, as do links to Hacker News, and other links open the browser
    /// from it.
    func detailColumnActions(path: Binding<NavigationPath>) -> some View {
        inAppBrowser(path: path)
            .environment(\.openThread, OpenThreadAction { thread, path in
                path.wrappedValue.append(thread)
            })
    }
}
