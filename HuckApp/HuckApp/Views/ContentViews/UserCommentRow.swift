//
//  UserCommentRow.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import SwiftUI
import UIKit

/// A comment read outside its thread: on a profile's Comments tab, or in the
/// search tab's comment results.
///
/// It's styled as the thread's own comments are — same author line, same body
/// text, same rhythm, via `CommentContent` — because it's the same thing being
/// read. What a lone comment has that a thread comment doesn't is the story it
/// came from, named above it; what it lacks is everything that only makes sense
/// inside a thread: rails, collapsing, an options menu. Tapping it opens the
/// thread at this comment, which is the one thing a lone comment can't give you.
struct UserCommentRow: View {
    let comment: UserComment
    @Binding var path: NavigationPath
    /// Called once the comment has been deleted, so the list can drop the row.
    /// Lists that can't remove rows leave it `nil`, which withholds Delete.
    var onDeleted: (() -> Void)?

    /// Identifies the reader, to offer Delete on their own comments.
    @Environment(UserSession.self) private var session

    /// Set while the reader is confirming deletion of this comment.
    @State private var deleteTarget: UserComment?

    /// Whether to offer Delete: the list can remove the row, the reader wrote
    /// it, and Hacker News still allows it. The story id is needed for the
    /// request and for clearing the thread from the cache.
    private var isDeletable: Bool {
        onDeleted != nil
            && comment.storyId != nil
            && comment.author == session.username
            && HackerNewsAPI.isWithinDeleteWindow(comment.timestamp)
    }

    /// How much of a long comment to show before clamping. Generous enough to
    /// read the point being made, short enough that one comment can't take over
    /// a list of results — the full text is a tap away in the thread.
    private static let bodyLineLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            storyLink
            CommentContent(
                author: comment.author,
                // Plain, including the reader's own name: a colour places a name
                // within a conversation, and there's no conversation here.
                text: comment.text,
                lineLimit: Self.bodyLineLimit,
                // The enclosing list already draws a separator between rows.
                showsDivider: false,
                path: $path
            ) {
                CommentAgeLabel(timestamp: comment.timestamp)
                // The reader's own comments show their score instead of an
                // arrow they couldn't use.
                if comment.author == session.username {
                    CommentScoreLabel(id: comment.id)
                } else {
                    CommentUpvoteButton(id: comment.id)
                }
                optionsMenu
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.horizontal, 16)
        // The whole row is the comment, so tapping anywhere on it opens the
        // thread — not just the story link above. The author's name and the
        // story link keep their own taps.
        .contentShape(Rectangle())
        .onTapGesture {
            if let storyId = comment.storyId {
                openInContext(storyId: storyId)
            }
        }
        .confirmsCommentDeletion(of: $deleteTarget) { comment in
            guard let storyId = comment.storyId else { throw APIError.deleteFailed }
            try await HackerNewsAPI.deleteComment(id: comment.id, storyId: storyId)
            onDeleted?()
        }
    }

    /// The comment's options, in the same ellipsis a thread comment uses. The
    /// collapse actions are absent — there's no thread here to fold — but a
    /// permalink is a permalink wherever the comment is read.
    private var optionsMenu: some View {
        CommentOptionsMenu {
            if let url = comment.hackerNewsURL {
                Button {
                    UIPasteboard.general.url = url
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            // Names what tapping the row does, for anyone who looks in the menu
            // for it rather than guessing.
            if let storyId = comment.storyId {
                Button {
                    openInContext(storyId: storyId)
                } label: {
                    Label("Open in Thread", systemImage: "arrow.turn.up.left")
                }
            }
            if isDeletable {
                Divider()
                Button(role: .destructive) {
                    deleteTarget = comment
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                // The menu tints its icons primary, and the role colors only
                // the text, so the icon is tinted red to match.
                .tint(.red)
            }
        }
    }

    /// The story this comment sits in. Absent from a thread comment, where the
    /// story is already on screen above it.
    @ViewBuilder
    private var storyLink: some View {
        if let title = comment.storyTitle, let storyId = comment.storyId {
            Button {
                openInContext(storyId: storyId)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption2)
                    Text(title)
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens the story's thread scrolled to this comment, so it's read in the
    /// conversation it belongs to rather than on its own.
    private func openInContext(storyId: Int) {
        path.append(ItemNavigation.textStory(id: storyId, scrollTo: comment.id))
    }
}

#Preview {
    ScrollView {
        LazyVStack(spacing: 0) {
            UserCommentRow(
                comment: UserComment(
                    id: 1,
                    author: "patio11",
                    text: "The thing nobody tells you about pricing is that it's a proxy for who you think your customer is. *Every* number you put on a page is a sentence about who you expect to read it.",
                    storyTitle: "Ask HN: How do you price a B2B product?",
                    storyId: 2,
                    timestamp: .now.addingTimeInterval(-3600)
                ),
                path: .constant(NavigationPath())
            )
            Divider()
            UserCommentRow(
                comment: UserComment(
                    id: 3,
                    author: "pg",
                    text: "A short reply.",
                    storyTitle: nil,
                    storyId: nil,
                    timestamp: .now.addingTimeInterval(-86_400)
                ),
                path: .constant(NavigationPath())
            )
            Divider()
        }
    }
    .environment(UserSession())
    .environment(InteractionStore(session: UserSession()))
}
