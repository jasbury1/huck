//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct CommentCellView: View {
    @State private var commentData: Comment
    @Binding var path: NavigationPath

    private var indentationLevel = 0

    init(commentData: Comment, path: Binding<NavigationPath>) {
        self.commentData = commentData
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
                    Text(commentData.timestamp.ageString())
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                Text(try! AttributedString(markdown: commentData.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    .font(.callout)
                //Text(commentData.text)
                Divider()
            }
            // Padding lives inside the text column so the rails stay full-height.
            .padding(.top, 8)
            // Fill the trailing edge instead of a Spacer so the HStack's spacing
            // only sits between the rails and the text, not to the right of it.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StoryTextView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    @State private var commentFetcher: CommentFetcher
    @Binding var path: NavigationPath

    /// Opens the linked page in the standardized in-app Safari browser.
    @Environment(\.openInAppBrowser) private var openInAppBrowser

    /// Height of the large in-content title and how far the list has scrolled,
    /// used to fade the small nav-bar title in as the large one scrolls off.
    @State private var titleHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

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
        List {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    storyHeader
                    if storyData.text != nil {
                        Text(try! AttributedString(markdown: storyData.text!, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        //Text(storyData.text!)
                    }
                    Text("By \(storyData.by)")
                        .font(.callout)
                        .foregroundStyle(.gray)
                    HStack {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.gray)
                        Text("\(storyData.score)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
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
                        Image(systemName: "bookmark")
                            .foregroundColor(.gray)
                    }
                }
            }

            Section {
                ForEach(commentFetcher.comments, id: \.id) { comment in
                    CommentCellView(commentData: comment, path: $path)
                        // The cell draws its own Divider; hide the List's
                        // built-in row separator so lines don't double up.
                        .listRowSeparator(.hidden)
                        // No vertical inset, so rows meet edge-to-edge and the
                        // indentation rails connect between comments.
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        // Leading swipe hides/collapses the comment; a full swipe
                        // triggers it. Behavior is stubbed for now.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                // TODO: Hide/collapse this comment thread
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            .tint(.gray)
                        }
                        // Trailing swipe exposes Upvote and Reply. Upvote is
                        // listed first so a full swipe triggers it. Both stubbed.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                // TODO: Upvote this comment
                            } label: {
                                Label("Upvote", systemImage: "arrow.up")
                            }
                            .tint(.green)
                            Button {
                                // TODO: Reply to this comment
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                            .tint(.blue)
                        }
                }
            } header: {
                commentsHeader
            }
        }
        .listStyle(.inset)
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
        }
        .task {
            await storyData.fetchData()
            await commentFetcher.fetchComments()
        }
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

    /// Section header shown between the post details and the comments. The inset
    /// list style pins it to the top once scrolled past. Holds the sort and
    /// more-options buttons inline with the title.
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
        // Section headers are uppercased by default; keep the title as written.
        .textCase(nil)
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
}

