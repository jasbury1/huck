//
//  CommentContent.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import SwiftUI

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

extension Color {
    /// Marks who is speaking: red for the reader's own comments, orange for
    /// the story's submitter (the convention other clients use for OP). When
    /// the reader *is* the submitter, red wins — "this is you" is the more
    /// useful of the two, since they already know they posted the story.
    ///
    /// `storyAuthor` is `nil` wherever a comment is read outside its thread, on
    /// a profile or in search results: there's no story in view to be the
    /// author of, so there's nothing for the orange to mean.
    static func commentAuthor(
        _ author: String,
        reader: String?,
        storyAuthor: String? = nil
    ) -> Color {
        if let reader, author == reader {
            .red
        } else if let storyAuthor, author == storyAuthor {
            .storySubmitter
        } else {
            .primary
        }
    }
}

/// How a comment looks: the author line with a trailing accessory, the
/// comment's text, and the hairline below it.
///
/// Shared by the thread view's `CommentCellView` and the standalone rows on
/// profiles and in search results, so a comment reads the same wherever it's
/// found. What genuinely differs between those places is passed in rather than
/// branched on here — the thread hands over a timestamp *and* its options menu
/// as the accessory and wraps this in indentation rails, while a standalone row
/// hands over only a timestamp and puts the story's title above it.
struct CommentContent<Accessory: View>: View {
    let author: String
    /// See `Color.commentAuthor(_:reader:storyAuthor:)`. Passed in rather than
    /// derived, since only the caller knows whose story this is.
    let authorColor: Color

    /// The comment's text, or `nil` for a collapsed thread row, which shows
    /// its header alone.
    let text: String?

    /// Maximum lines of body text, or `nil` for all of it. Standalone rows
    /// clamp so one long comment can't own the list; in a thread the whole
    /// comment is the point.
    var lineLimit: Int? = nil

    /// Whether to draw the separating hairline. On in a thread, where it has to
    /// sit inside the text column so it doesn't cut across the rails; off in
    /// the lists that already draw their own between rows.
    var showsDivider = true

    @Binding var path: NavigationPath

    /// Tapping the header's empty space — the gap after the name, and the
    /// timestamp. The thread collapses the comment with it. `nil` leaves that
    /// space inert so an enclosing row's tap handler sees it instead.
    var onHeaderTap: (() -> Void)?

    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let text {
                Text(Self.formatted(text))
                    .font(.callout)
                    .lineLimit(lineLimit)
            }
            if showsDivider {
                Divider()
            }
        }
        // Fill the trailing edge instead of a Spacer so an enclosing HStack's
        // spacing only sits between the rails and the text, not to the right.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var header: some View {
        let row = HStack {
            // A Button (not a NavigationLink) keeps only the username tappable;
            // a NavigationLink in a List row makes the whole row the tap target.
            Button {
                path.append(ItemNavigation.userProfile(user: author))
            } label: {
                Text(author)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(authorColor)
            }
            .buttonStyle(.plain)
            Spacer()
            accessory()
        }

        // Only claim the header's empty space when there's something to do with
        // it. Installing the gesture regardless would swallow the tap, leaving
        // a standalone row's timestamp dead rather than opening the thread.
        if let onHeaderTap {
            row
                .contentShape(Rectangle())
                .onTapGesture(perform: onHeaderTap)
        } else {
            row
        }
    }

    /// Renders the comment's inline markdown — Hacker News allows italics,
    /// links, and code — falling back to the raw text rather than trapping on
    /// anything the parser rejects.
    private static func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// The timestamp as both views show it, in the accessory position.
struct CommentAgeLabel: View {
    let timestamp: Date

    var body: some View {
        Text(timestamp.ageString())
            .font(.footnote)
            .foregroundStyle(.gray)
    }
}

/// The ellipsis a comment's options hang from — a plain dropdown anchored to
/// the trailing edge of the header, which is the conventional affordance for a
/// per-row control and lighter than the sheet a story's "More" button presents.
///
/// Shared so the affordance is identical wherever a comment appears; only the
/// contents differ, since a thread comment can be collapsed and a standalone
/// one can't.
struct CommentOptionsMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
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
