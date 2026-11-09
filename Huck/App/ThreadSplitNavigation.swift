//
//  ThreadSplitNavigation.swift
//  Huck
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
/// Regular — an unfolded iPhone Duo, iPad, or a wide window — `root` and
/// everything pushed from it sit in the leading column, and threads opened
/// there show in a detail column alongside, so the list stays in view while
/// reading. The detail column has its own stack, so profiles and links followed
/// from a thread push there.
///
/// Compact — any iPhone, or a folded Duo — the split view collapses itself into
/// one stack: the thread and its pages sit on top of the leading column's, and
/// Back from the thread returns to the list. It's one split view at every
/// width, rather than a split view swapped for a stack, so folding or unfolding
/// keeps both stacks — and the system's bars — intact.
///
/// `root` brings its own `navigationDestination`s; the detail column handles
/// `ItemNavigation` itself.
struct ThreadSplitNavigation<Root: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var root: () -> Root

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The leading column's width range, in points. The minimum is the
    /// narrowest current iPhone, so its rows never get more cramped than on a
    /// phone; the maximum keeps the detail column the larger of the two.
    private static var minimumLeadingWidth: CGFloat { 362 }
    private static var idealLeadingWidth: CGFloat { 400 }
    private static var maximumLeadingWidth: CGFloat { 800 }

    /// The thread at the root of the detail column, if one's been opened.
    @State private var selectedThread: ItemNavigation?
    /// Pages pushed within the detail column, above `selectedThread`.
    @State private var detailPath = NavigationPath()
    /// Which column is on top once collapsed: the detail column while a thread
    /// is open, the leading one after Back. The split view sets it back to
    /// `.sidebar` itself when the thread is popped.
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    // Pages pushed within a split view's columns take their environment from
    // the split view, not from modifiers around the column's stack. So the
    // leading column's actions are set outside the split view, and the detail
    // column's are applied to each of its pages directly, overriding them.
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            NavigationStack(path: $path) {
                root()
                    // Only beside a detail column: collapsed, the leading
                    // column is the whole screen and keeps the phone's styling.
                    .environment(\.isSidebarColumnRoot, horizontalSizeClass == .regular)
            }
            // Never narrower than an iPhone's screen, which story rows and the
            // profile's header and tab pills are laid out for; the system may
            // still narrow it where the window can't fit both columns.
            .navigationSplitViewColumnWidth(
                min: Self.minimumLeadingWidth,
                ideal: Self.idealLeadingWidth,
                max: Self.maximumLeadingWidth
            )
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
        }
        // Over both columns, so a thread's composer centers over the keyboard
        // — which spans the window — rather than over the thread's column.
        .hostsCommentComposer()
        .inAppBrowser(path: $path)
        // Outside `inAppBrowser`, so links to threads followed in the leading
        // column open beside it as well.
        .environment(\.openThread, OpenThreadAction { thread, _ in
            selectedThread = thread
            detailPath = NavigationPath()
            // Collapsed, this is what pushes the thread over the list.
            preferredCompactColumn = .detail
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
            .columnDivider()
    }

    /// The line between the columns, which the system doesn't draw here — and
    /// both are white once a story list is pushed in the leading one.
    ///
    /// Drawn by each detail page, because those are the pages this view builds:
    /// the leading column's are declared by its root, and a page pushed there
    /// sits outside any overlay on the column's stack. The detail column runs
    /// underneath the sidebar, with the sidebar's width as its leading safe
    /// area, so the line keeps to that inset to land on the boundary. Vertically
    /// it runs the full height.
    func columnDivider() -> some View {
        overlay(alignment: .leading) {
            ColumnDivider()
                .ignoresSafeArea(edges: .vertical)
        }
    }
}

/// A vertical separator heavier than a `Divider`'s one-pixel hairline, so the
/// boundary between the columns reads more clearly than the separators within
/// them.
private struct ColumnDivider: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Collapsed, the detail page is the whole screen, with no column
        // beside it to divide from.
        if horizontalSizeClass == .regular {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2.5)
        }
    }
}
