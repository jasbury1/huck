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

    @Environment(UserSession.self) private var session

    /// How much of a long comment to show before clamping. Generous enough to
    /// read the point being made, short enough that one comment can't take over
    /// a list of results — the full text is a tap away in the thread.
    private static let bodyLineLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            storyLink
            CommentContent(
                author: comment.author,
                // No story author to compare against out here, so no OP colour.
                authorColor: .commentAuthor(comment.author, reader: session.username),
                text: comment.text,
                lineLimit: Self.bodyLineLimit,
                // The enclosing list already draws a separator between rows.
                showsDivider: false,
                path: $path
            ) {
                CommentAgeLabel(timestamp: comment.timestamp)
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
}
