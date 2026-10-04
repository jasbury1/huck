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
    /// Marks who is speaking within a thread: red for the reader's own
    /// comments, orange for the story's submitter (the convention other clients
    /// use for OP). When the reader *is* the submitter, red wins — "this is
    /// you" is the more useful of the two, since they already know they posted
    /// the story.
    ///
    /// Only a thread calls this. A name is coloured to place it *among others* —
    /// which is you, which is the person everyone is replying to. Read on a
    /// profile or in search results there's no conversation to place it in, so
    /// those rows leave the name plain.
    static func commentAuthor(
        _ author: String,
        reader: String?,
        storyAuthor: String
    ) -> Color {
        if let reader, author == reader {
            .red
        } else if author == storyAuthor {
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

    /// Plain by default, since that's how a name reads everywhere except inside
    /// a thread. A thread passes its own colouring — see
    /// `Color.commentAuthor(_:reader:storyAuthor:)`, which only it can compute,
    /// being the only place that knows whose story this is.
    var authorColor: Color = .primary

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
                FormattedTextView(text: text, lineLimit: lineLimit)
                    .font(.callout)
                    // Links take the tint, which is primary outside content.
                    .tint(.orange)
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
        // No spacing of its own: the trailing controls carry their tap targets
        // as padding, so stack spacing on top of that would land *between* the
        // targets and read as a gap twice the size. See `CommentHeaderMetrics`.
        let row = HStack(spacing: 0) {
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
            Spacer(minLength: CommentHeaderMetrics.iconInset)
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
}

/// The metrics the trailing controls in a comment's header share.
///
/// They have to agree on one number, because each control's tap target is
/// padding around a small glyph: what the eye measures is the distance between
/// glyphs, which is the sum of the padding on either side of the gap. Left to
/// choose their own, the arrow and the ellipsis produced gaps of 16pt and 31pt
/// in a row that should read as one evenly-spaced group.
enum CommentHeaderMetrics {
    /// Padding around an icon inside its tap target. Half of a gap between two
    /// adjacent icons, and the whole gap between the timestamp and the first
    /// icon — which is why the timestamp carries it too.
    static let iconInset: CGFloat = 8

    /// An icon's own size, before its inset. `footnote` for these symbols.
    static let iconSize: CGFloat = 14

    /// The tap target around one icon: comfortable to hit, and identical for
    /// every control so the gaps either side of the middle one match.
    static var controlSize: CGFloat { iconSize + iconInset * 2 }
}

/// The timestamp as both views show it, in the accessory position.
struct CommentAgeLabel: View {
    let timestamp: Date

    var body: some View {
        Text(timestamp.ageString())
            .font(.footnote)
            .foregroundStyle(.gray)
            // Matches an icon's inset, so the gap from the timestamp to the
            // arrow equals the gap from the arrow to the ellipsis. Text has no
            // tap target of its own to supply it.
            .padding(.trailing, CommentHeaderMetrics.iconInset)
    }
}

/// A comment's upvote arrow, orange once upvoted, as it is on a story cell.
///
/// Takes the comment's item id rather than a model, since the two kinds of
/// comment row hold different types and a vote needs only the id. Sits between
/// the timestamp and the options menu wherever a comment is shown.
///
/// No score beside it, unlike a story's arrow: Hacker News shows a comment's
/// points only to its author, so there's no number to show or to move. (The
/// author sees `CommentScoreLabel` in its place.)
struct CommentUpvoteButton: View {
    let id: Int

    /// Drives the arrow's colour. Shared app-wide, so voting here colours the
    /// same comment everywhere it appears — a thread, a profile, search.
    @Environment(InteractionStore.self) private var interactionStore
    /// Handles the login gate and the toggle; see `storyActionsEnabled()`.
    @Environment(\.upvoteComment) private var upvoteComment

    private var isUpvoted: Bool { interactionStore.isCommentUpvoted(id) }

    var body: some View {
        Button {
            upvoteComment(id: id)
        } label: {
            Image(systemName: "arrow.up")
                .font(.footnote)
                .foregroundStyle(isUpvoted ? .orange : .gray)
                .frame(
                    width: CommentHeaderMetrics.controlSize,
                    height: CommentHeaderMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUpvoted ? "Remove upvote" : "Upvote")
    }
}

/// The score on one of the reader's own comments, in place of the upvote
/// arrow — Hacker News doesn't let anyone vote on their own comment, but does
/// show its author the points it has earned, and no one else.
///
/// The score is scraped — a page of the reader's comments at a time, see
/// `CommentScoreCache` — so it's asked for only once the row is on screen, and
/// the arrow is drawn straight away so the header doesn't shift when the
/// number lands. If it can't be read, the arrow stands alone.
struct CommentScoreLabel: View {
    let id: Int

    /// The reader, whose comment this is.
    @Environment(UserSession.self) private var session
    @State private var score: Int?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up")
            if let score {
                Text(score, format: .number)
                    .monospacedDigit()
                    .transition(.opacity)
            }
        }
        .font(.footnote)
        .foregroundStyle(.gray)
        // The same inset as the other controls, so the arrow alone occupies
        // exactly the upvote button's footprint and the gaps stay even.
        .padding(.horizontal, CommentHeaderMetrics.iconInset)
        .frame(height: CommentHeaderMetrics.controlSize)
        .animation(.default, value: score)
        .task(id: id) {
            guard let username = session.username else { return }
            score = await HackerNewsAPI.ownCommentScore(id: id, username: username)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\($0) points" } ?? "Your comment")
    }
}

/// The ellipsis a comment's options hang from — a plain dropdown anchored to
/// the trailing edge of the header, which is the conventional affordance for a
/// per-row control.
///
/// Shared so the affordance is identical wherever a comment appears; only the
/// contents differ, since a thread comment can be collapsed and a standalone
/// one can't.
struct CommentOptionsMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
                // Icons match their text, not the app's orange tint.
                .tint(.primary)
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.gray)
                // The same target as the upvote arrow. It used to be wider,
                // which put half again as much space before it as the arrow had
                // before it.
                .frame(
                    width: CommentHeaderMetrics.controlSize,
                    height: CommentHeaderMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Asks the reader to confirm deleting one of their comments, runs the
/// deletion, and reports a failure — the same exchange wherever a comment can
/// be deleted, whether from its thread or from the reader's profile.
private struct CommentDeletionModifier<Item>: ViewModifier {
    @Binding var target: Item?
    let delete: (Item) async throws -> Void

    @State private var error: (any Error)?

    func body(content: Content) -> some View {
        content
            .alert("Delete Comment?", item: $target) { item in
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await delete(item)
                        } catch {
                            self.error = error
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("It will be removed from Hacker News. This can't be undone.")
            }
            .alert("Couldn't Delete Comment", item: $error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
    }
}

extension View {
    /// Confirms and performs a comment deletion whenever `target` is set.
    /// `delete` throws to report a failure, which is shown in an alert.
    func confirmsCommentDeletion<Item>(
        of target: Binding<Item?>,
        delete: @escaping (Item) async throws -> Void
    ) -> some View {
        modifier(CommentDeletionModifier(target: target, delete: delete))
    }
}
