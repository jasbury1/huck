//
//  UserCommentRow.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import SwiftUI

/// A comment shown outside its thread: on a profile's Comments tab, or in the
/// search tab's comment results. The story it belongs to sits above it, and
/// tapping anywhere opens that thread scrolled to this comment — a comment on
/// its own is only half the conversation.
struct UserCommentRow: View {
    let comment: UserComment
    @Binding var path: NavigationPath

    @Environment(UserSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            Text(comment.text)
                .font(.body)
                .lineLimit(4)
            byline
        }
        // The enclosing LazyVStack centers its rows, so a short comment would
        // otherwise appear indented. Fill the width and pin content leading.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // The whole row is the comment, so tapping anywhere on it opens the
        // comment — not just the story link above it.
        .contentShape(Rectangle())
        .onTapGesture {
            if let storyId = comment.storyId {
                openInContext(storyId: storyId)
            }
        }
    }

    /// Who wrote it, and when. The name is its own tap target, navigating to
    /// the author's profile — a plain `Button`, not a `NavigationLink`, so it
    /// doesn't claim the row's tap the way a link would.
    private var byline: some View {
        HStack(spacing: 5) {
            if !comment.author.isEmpty {
                Button {
                    path.append(ItemNavigation.userProfile(user: comment.author))
                } label: {
                    Text(comment.author)
                        .fontWeight(.semibold)
                        .foregroundStyle(authorColor)
                }
                .buttonStyle(.plain)
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            Text(comment.timestamp.ageString())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Blue for the reader's own comments, matching how the thread view marks
    /// them. There's no OP colour here: outside a thread there's no story
    /// author to compare against.
    private var authorColor: Color {
        comment.author == session.username ? .blue : .secondary
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
                    text: "The thing nobody tells you about pricing is that it's a proxy for who you think your customer is.",
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
        }
    }
    .environment(UserSession())
}
