//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct CommentCellView: View {
    @State private var commentData: Comment
    /// When true, the row shrinks to just the username and a down chevron; the
    /// timestamp, body, and this comment's replies are hidden.
    let isCollapsed: Bool
    @Binding var path: NavigationPath

    private var indentationLevel = 0

    init(commentData: Comment, isCollapsed: Bool, path: Binding<NavigationPath>) {
        self.commentData = commentData
        self.isCollapsed = isCollapsed
        self._path = path
        indentationLevel = commentData.nestingLevel
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
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isCollapsed {
                        // A down chevron signals a collapsed thread that can be
                        // expanded again.
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    } else {
                        Text(commentData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
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

    /// 0 while the large title is fully visible, 1 once it has scrolled off.
    private var titleCollapseProgress: CGFloat {
        titleHeight > 0 ? min(max(scrollOffset / titleHeight, 0), 1) : 0
    }

    init(storyId: Int, path: Binding<NavigationPath>) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
        self.commentFetcher = CommentFetcher(id: storyId)
        self._path = path
    }

    var body: some View {
        ScrollView {
            // A plain LazyVStack (rather than a List) gives us direct control of
            // the layout, so collapsing a comment folds smoothly: the collapsed
            // row shrinks and its replies are removed while the username, sitting
            // at the top of its cell, stays anchored in place.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                storyDetailSection

                Section {
                    ForEach(commentFetcher.visibleComments, id: \.id) { comment in
                        CommentCellView(commentData: comment, isCollapsed: commentFetcher.isCollapsed(comment), path: $path)
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
                                    // TODO: Reply to this comment
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
                    }
                } header: {
                    commentsHeader
                }
            }
        }
        // Enables the row `swipeActions` above outside of a List (iOS 27+).
        .swipeActionsContainer()
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The small nav-bar title fades in as the large one scrolls off,
                // matching the username on the user page.
                Text(storyData.title)
                    .font(.headline)
                    .lineLimit(1)
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
        .task {
            await storyData.fetchData()
            await commentFetcher.fetchComments()
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
            Text("By \(storyData.by)")
                .font(.callout)
                .foregroundStyle(.gray)
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
                Image(systemName: "paperplane")
                    .foregroundColor(.gray)
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

#Preview {
    StoryTextView(storyId: 46391572, path: .constant(NavigationPath()))
        .environment(InteractionStore())
}

