//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI
import UIKit

private extension Color {
    /// Marks the story's submitter on their own comments.
    ///
    /// Not plain `.orange`: at this text size, system orange against a light
    /// background lands around 2:1 contrast, which is muddy for everyone and
    /// unreadable for anyone who depends on contrast. This darkens it to about
    /// 4.6:1 there, clearing WCAG AA while still reading as orange rather than
    /// brown. Only the light appearance is changed — in dark mode the standard
    /// orange already sits near 10:1 against the background, so darkening it
    /// would take contrast away rather than add it.
    static let storySubmitter = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.72, green: 0.36, blue: 0, alpha: 1)
    })
}

struct CommentCellView: View {
    @State private var commentData: Comment
    /// When true, the row shrinks to just the username and a down chevron; the
    /// timestamp, body, and this comment's replies are hidden.
    let isCollapsed: Bool
    /// The story's submitter, so their own comments can be marked as such.
    let storyAuthor: String
    @Binding var path: NavigationPath

    /// Folds away just this comment's replies.
    let onCollapse: () -> Void
    /// Folds away the whole reply chain this comment sits in.
    let onCollapseThread: () -> Void

    /// Identifies the signed-in reader, so their own comments stand out.
    @Environment(UserSession.self) private var session

    private var indentationLevel = 0

    init(
        commentData: Comment,
        isCollapsed: Bool,
        storyAuthor: String,
        path: Binding<NavigationPath>,
        onCollapse: @escaping () -> Void,
        onCollapseThread: @escaping () -> Void
    ) {
        self.commentData = commentData
        self.isCollapsed = isCollapsed
        self.storyAuthor = storyAuthor
        self._path = path
        self.onCollapse = onCollapse
        self.onCollapseThread = onCollapseThread
        indentationLevel = commentData.nestingLevel
    }

    /// Marks who is speaking: blue for the reader's own comments, orange for the
    /// story's submitter (the convention other clients use for OP). When the
    /// reader *is* the submitter, blue wins — "this is you" is the more useful
    /// of the two, since they already know they posted the story.
    private var authorColor: Color {
        if let username = session.username, commentData.author == username {
            .blue
        } else if commentData.author == storyAuthor {
            .storySubmitter
        } else {
            .primary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Full-height indentation rails. Because the row has no vertical
            // insets (see `.listRowInsets` in StoryTextView), a rail reaches the
            // top and bottom edges of its row, so rails on adjacent same-level
            // comments meet to form one continuous line.
            ForEach(0..<indentationLevel, id:\.self) { _ in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Everything in the header that isn't the username or the menu
                // collapses the comment — the gap between them, and the
                // timestamp. The nested controls keep their own taps, so this
                // only claims the space nothing else wanted.
                HStack {
                    // A Button (not a NavigationLink) keeps only the username
                    // tappable; a NavigationLink in a List row makes the whole
                    // row the tap target.
                    Button {
                        path.append(ItemNavigation.userProfile(user: commentData.author))
                    } label: {
                        Text(commentData.author)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(authorColor)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isCollapsed {
                        // A down chevron signals a collapsed thread that can be
                        // expanded again. The menu is left off a collapsed row:
                        // it's a summary, and the parent disables its controls.
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    } else {
                        Text(commentData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        optionsMenu
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Guarded rather than a toggle: a collapsed row is expanded
                    // by the tap handler on the whole cell, which stays live
                    // while these controls are disabled.
                    if !isCollapsed { onCollapse() }
                }
                if !isCollapsed {
                    Text(try! AttributedString(markdown: commentData.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        .font(.callout)
                    //Text(commentData.text)
                }
                Divider()
            }
            // Padding lives inside the text column so the rails stay full-height.
            .padding(.top, 8)
            // Fill the trailing edge instead of a Spacer so the HStack's spacing
            // only sits between the rails and the text, not to the right of it.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The comment's own options, as a plain dropdown anchored to the ellipsis —
    /// the conventional affordance for a per-row control, and lighter than the
    /// sheet the story's "More" button presents.
    private var optionsMenu: some View {
        Menu {
            // A comment the reader posted seconds ago has no id yet, so there's
            // no permalink to copy until it has one.
            if let url = commentData.hackerNewsURL {
                Button {
                    UIPasteboard.general.url = url
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            Button {
                onCollapse()
            } label: {
                Label("Collapse", systemImage: "chevron.up")
            }
            // Only a reply has a chain above it to fold; on a top-level comment
            // this would do exactly what Collapse does.
            if commentData.nestingLevel > 0 {
                Button {
                    onCollapseThread()
                } label: {
                    Label("Collapse Thread", systemImage: "arrow.up.to.line")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.gray)
                // Wide and tall enough to hit comfortably without the header
                // growing much taller than the text it holds.
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StoryTextView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    @State private var commentFetcher: CommentFetcher
    @Binding var path: NavigationPath

    /// Opens the linked page in the standardized in-app Safari browser.
    @Environment(\.openInAppBrowser) private var openInAppBrowser

    /// Shared interaction state (drives the upvote arrow's color) and the upvote
    /// action (handles the login gate and the vote toggle).
    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.upvote) private var upvote
    @Environment(\.favorite) private var favorite
    /// Gates commenting and replying, which need an account, behind the same
    /// login sheet the story actions use.
    @Environment(\.requireLogin) private var requireLogin

    /// Names the author of a comment posted from here, so it can be shown in
    /// the thread before the APIs have caught up.
    @Environment(UserSession.self) private var session

    /// Records this story as recently viewed when its comments are opened — the
    /// single choke point for every route into a story's comments/text.
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    private var isUpvoted: Bool { interactionStore.interaction(for: storyId).isUpvoted }
    private var isFavorited: Bool { interactionStore.interaction(for: storyId).isFavorited }

    /// The fetched score plus any optimistic vote adjustment from the shared store,
    /// so this view stays in sync with the story's feed row.
    private var displayedScore: Int { storyData.score + interactionStore.scoreDelta(for: storyId) }

    /// Height of the large in-content title and how far the list has scrolled,
    /// used to fade the small nav-bar title in as the large one scrolls off.
    @State private var titleHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    /// Non-nil while the shared "More" options popover is presented.
    @State private var moreOptionsStory: StoryModel?

    /// The comment the composer is replying to, set by the Reply swipe action
    /// and cleared when the draft is discarded.
    @State private var replyTarget: Comment?

    /// A comment to bring into view as soon as the thread contains it.
    ///
    /// Comments stream in, so a request to scroll to one routinely arrives
    /// before the comment does — opening a story straight onto a comment is
    /// exactly that case. The request waits here until it can be honoured.
    @State private var pendingScrollTarget: Int?

    /// 0 while the large title is fully visible, 1 once it has scrolled off.
    private var titleCollapseProgress: CGFloat {
        titleHeight > 0 ? min(max(scrollOffset / titleHeight, 0), 1) : 0
    }

    /// `scrollTo` names a comment to open the story onto, brought into view once
    /// the thread carrying it has loaded.
    init(storyId: Int, path: Binding<NavigationPath>, scrollTo commentID: Int? = nil) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
        self.commentFetcher = CommentFetcher(id: storyId)
        self._path = path
        self._pendingScrollTarget = State(initialValue: commentID)
    }

    var body: some View {
        // The reader wraps the whole view rather than just the scroll view, so
        // that the composer overlay and each comment's own menu can all reach
        // the same proxy.
        ScrollViewReader { proxy in
            content(scrollProxy: proxy)
        }
    }

    private func content(scrollProxy: ScrollViewProxy) -> some View {
        ScrollView {
            // A plain LazyVStack (rather than a List) gives us direct control of
            // the layout, so collapsing a comment folds smoothly: the collapsed
            // row shrinks and its replies are removed while the username, sitting
            // at the top of its cell, stays anchored in place.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                storyDetailSection
                Divider()
                Section {
                    ForEach(commentFetcher.visibleComments, id: \.id) { comment in
                        let collapsed = commentFetcher.isCollapsed(comment)
                        CommentCellView(
                            commentData: comment,
                            isCollapsed: collapsed,
                            storyAuthor: storyData.by,
                            path: $path,
                            onCollapse: {
                                withAnimation(.easeInOut) {
                                    commentFetcher.toggleCollapsed(comment)
                                }
                            },
                            onCollapseThread: {
                                // Folding at the root can swallow everything
                                // between here and it, so follow the fold up to
                                // the stub rather than leaving the reader
                                // stranded somewhere they didn't choose.
                                let root = withAnimation(.easeInOut) {
                                    commentFetcher.collapseThread(containing: comment)
                                }
                                if let root {
                                    scroll(to: root.id, using: scrollProxy)
                                }
                            }
                        )
                            .padding(.horizontal, 16)
                            // Leading swipe (swipe right) exposes Upvote and Reply.
                            // Upvote is listed first so a full swipe triggers it. Both stubbed.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    // TODO: Upvote this comment
                                } label: {
                                    Label("Upvote", systemImage: "arrow.up")
                                }
                                .tint(.orange)
                                Button {
                                    // Opens the composer with this comment as
                                    // its target, behind the same login gate as
                                    // the compose button. Offered for every
                                    // comment, including one just posted — its
                                    // id is looked up on send, if it's needed.
                                    requireLogin { replyTarget = comment }
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                                .tint(.blue)
                            }
                            // Trailing swipe (swipe left) folds the thread closed:
                            // the replies are removed and the row shrinks to just
                            // the username. A full swipe triggers it.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(.easeInOut) {
                                        commentFetcher.toggleCollapsed(comment)
                                    }
                                } label: {
                                    Label("Collapse", systemImage: "chevron.up")
                                }
                                .tint(.gray)
                            }
                            // A collapsed comment disables its swipe actions (the
                            // swipeActions modifiers stay attached so the fold still
                            // animates); tapping anywhere on it expands the thread
                            // again. The tap gesture sits outside `disabled` so it
                            // keeps working while the row's own controls are off.
                            .disabled(collapsed)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if collapsed {
                                    withAnimation(.easeInOut) {
                                        commentFetcher.toggleCollapsed(comment)
                                    }
                                }
                            }
                            // New rows fade in as the thread streams; combined with the
                            // append-only snapshots this avoids any visible reflow.
                            .transition(.opacity)
                    }
                    commentsStatus
                } header: {
                    //SortableHeader(title: "Comments")
                }
            }
        }
        // Enables the row `swipeActions` above outside of a List (iOS 27+).
        .swipeActionsContainer()
        // Leaves room for the floating composer, so the last comment can scroll
        // clear of it instead of coming to rest underneath, close enough to read
        // but with its own controls unreachable.
        .contentMargins(.bottom, CommentComposer.reservedHeight)
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The small nav-bar title fades in as the large one scrolls off,
                // matching the username on the user page. Sizing to the nav bar's
                // central region (rather than forcing full width) lets a long
                // title tail-truncate before it reaches the trailing buttons.
                Text(storyData.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(titleCollapseProgress)
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Opens the same shared "More" options popover as the feed.
                Button {
                    moreOptionsStory = storyData
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                }
            }
        }
        // "More" options pop-up, shared with the story feed.
        .storyOptionsPopover(for: $moreOptionsStory)
        // Floating Liquid Glass compose control in the bottom-trailing corner.
        .overlay(alignment: .bottomTrailing) {
            CommentComposer(replyTarget: $replyTarget) { text in
                // Read the target before posting: a successful post closes the
                // composer, which clears it.
                let parent = replyTarget
                // Hacker News treats a top-level comment and a reply as the
                // same thing posted against a different parent: the story
                // itself, or the comment being answered.
                // Replying to a comment the reader posted in this same sitting
                // is the one thing that needs its Hacker News id, so this is
                // where that lookup happens — and the only place it happens.
                // Throwing keeps the draft, so "try again" is real advice.
                let parentId: Int
                if let parent {
                    guard let resolved = await commentFetcher.resolveItemID(for: parent) else {
                        throw APIError.unknownReplyTarget
                    }
                    parentId = resolved
                } else {
                    parentId = storyId
                }
                try await HackerNewsAPI.postComment(
                    parentId: parentId,
                    storyId: storyId,
                    text: text
                )
                // Show it immediately rather than re-reading the whole thread,
                // and scroll to it — a reply lands at the end of its parent's
                // replies, which is often off screen.
                let posted = commentFetcher.insertPostedComment(
                    text: text,
                    author: session.username ?? "",
                    replyingTo: parent
                )
                scroll(to: posted.id, using: scrollProxy)
            }
        }
        .task {
            recentlyViewedStore.recordView(storyId)
            await storyData.fetchData()
            await commentFetcher.fetchComments()
        }
        // The thread streams in, so a comment we were asked to scroll to may
        // only just have arrived. Retry on every snapshot until it has.
        .onChange(of: commentFetcher.comments.count) {
            scrollToPendingTarget(using: scrollProxy)
        }
    }

    // MARK: - Scrolling

    /// Brings a comment to the top of the view.
    ///
    /// When it isn't on screen to scroll to — still streaming in, or tucked
    /// inside a collapsed thread — the request is held rather than quietly
    /// dropped, and retried as the thread changes.
    private func scroll(to commentID: Int, using proxy: ScrollViewProxy) {
        guard commentFetcher.visibleComments.contains(where: { $0.id == commentID }) else {
            pendingScrollTarget = commentID
            return
        }
        pendingScrollTarget = nil
        withAnimation(.easeInOut) {
            proxy.scrollTo(commentID, anchor: .top)
        }
    }

    /// Retries a held scroll request now that the thread has changed.
    private func scrollToPendingTarget(using proxy: ScrollViewProxy) {
        guard let pendingScrollTarget else { return }
        scroll(to: pendingScrollTarget, using: proxy)
    }

    /// The loading indicator that trails the comment list. While loading it's a
    /// spinner — centred on its own before any comments arrive, then a footer as a
    /// streamed Firebase thread fills in below. Once loading finishes with no comments,
    /// it becomes a short empty-state note.
    @ViewBuilder
    private var commentsStatus: some View {
        if commentFetcher.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if commentFetcher.comments.isEmpty {
            Text("No comments yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    /// The post's details shown above the comments: headline, optional body,
    /// author, and the score/comment/time row with the upvote and favorite
    /// controls. Scrolls away above the pinned comments header.
    private var storyDetailSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            storyHeader
            if let text = storyData.text {
                Text(try! AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            }
            // Only the username is tappable, navigating to the author's profile;
            // a plain Button keeps the tap target limited to the name itself.
            HStack(spacing: 4) {
                Text("By")
                    .foregroundStyle(.gray)
                Button {
                    path.append(ItemNavigation.userProfile(user: storyData.by))
                } label: {
                    Text(storyData.by)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            .font(.callout)
            HStack {
                // Upvote button: arrow turns orange once upvoted; the action
                // handles login and the toggle.
                Button(action: {
                    upvote(storyData)
                }) {
                    HStack {
                        Image(systemName: "arrow.up")
                            .foregroundColor(isUpvoted ? .orange : .gray)
                        Text("\(displayedScore)")
                            .font(.footnote)
                            .foregroundStyle(isUpvoted ? .orange : .gray)
                    }
                }
                .buttonStyle(.plain)
                Image(systemName: "bubble")
                    .foregroundColor(.gray)
                Text("\(storyData.commentCount)")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                Image(systemName: "clock")
                    .foregroundColor(.gray)
                Text(storyData.timestamp.ageString())
                    .font(.footnote)
                    .foregroundStyle(.gray)
                // Share the post's Hacker News page via the share sheet.
                ShareLink(item: storyData.hackerNewsURL) {
                    Image(systemName: "paperplane")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                // Favorite the post. The heart fills red once favorited.
                Button(action: {
                    favorite(storyData)
                }) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .foregroundColor(isFavorited ? .red : .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    /// The story's headline. For a link post reached via its comments, the
    /// thumbnail is shown to the left of the title and the whole header is
    /// tappable, navigating to the linked page — mirroring the story cell's
    /// behavior.
    @ViewBuilder
    private var storyHeader: some View {
        if storyData.storyType == .link, let url = storyData.url {
            Button {
                openInAppBrowser(url)
            } label: {
                HStack(spacing: 12) {
                    StoryThumbnailView(status: storyData.thumbnailStatus)
                    titleView
                }
            }
            .buttonStyle(.plain)
        } else {
            titleView
        }
    }

    /// The large in-content title. Its measured height drives the fade-in of the
    /// small nav-bar title as it scrolls off.
    private var titleView: some View {
        Text(storyData.title)
            .font(.title2)
            .fontWeight(.heavy)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
    }

    /// Section header shown between the post details and the comments. As a
    /// pinned section header in the LazyVStack it sticks to the top once scrolled
    /// past, so it carries an opaque background. Holds the sort and more-options
    /// buttons inline with the title.
    private var commentsHeader: some View {
        HStack {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Button("Hot") {}
                Button("Newest") {}
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button {
                // TODO: More options
            } label: {
                Image(systemName: "ellipsis")
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Opaque background so scrolled comments don't show through when pinned.
        .background(Color(UIColor.systemBackground))
    }
}

@Observable
class CommentSectionData {
    var storyIds: [Int] = []
    
    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await HackerNewsAPI.getStoryIds(filter: filter)
        self.storyIds = ids
    }
}

#Preview("Comment cells") {
    CommentCellGallery()
        .environment(UserSession())
}

/// Sample comment rows at several depths, covering the author colours, the
/// options menu, and the collapsed row.
///
/// The samples are built in `body` rather than in the `#Preview` closure
/// because `Comment` is main-actor isolated and that closure isn't.
private struct CommentCellGallery: View {
    /// Builds a comment at a given depth. A `published` comment gets an
    /// `itemID`, which is what gives its menu the Copy Link row.
    private func comment(_ text: String, by author: String, level: Int, published: Bool = true) -> Comment {
        let comment = Comment(posted: text, author: author, nestingLevel: level)
        if published { comment.itemID = Int.random(in: 1...99_999_999) }
        return comment
    }

    var body: some View {
        let cells: [(comment: Comment, isCollapsed: Bool)] = [
            (comment("The story's submitter, so this name shows in orange.", by: "op_user", level: 0), false),
            (comment("Someone else, one level in — the name stays in the primary colour.", by: "commenter", level: 1), false),
            (comment("Deeper still. Only a reply offers Collapse Thread in its menu.", by: "third_party", level: 2), false),
            (comment("A collapsed row: just the name and a chevron, no menu.", by: "commenter", level: 1), true),
            (comment("Posted seconds ago, so it has no permalink to copy yet.", by: "op_user", level: 0, published: false), false),
        ]

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    CommentCellView(
                        commentData: cell.comment,
                        isCollapsed: cell.isCollapsed,
                        storyAuthor: "op_user",
                        path: .constant(NavigationPath()),
                        onCollapse: {},
                        onCollapseThread: {}
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

#Preview {
    let session = UserSession()
    StoryTextView(storyId: 46391572, path: .constant(NavigationPath()))
        .environment(session)
        .environment(InteractionStore(session: session))
        .environment(RecentlyViewedStore(session: session))
}

