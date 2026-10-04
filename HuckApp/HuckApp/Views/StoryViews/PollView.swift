//
//  PollView.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// A poll's options as a stack of result bars, shown beneath the poll's text.
///
/// Each option is a rounded rectangle filled from the leading edge in
/// proportion to its share of the votes, with its count on the trailing side.
/// Tapping one votes for it, outlining it; tapping it again takes the vote
/// back. Results are always visible — Hacker News shows them to everyone,
/// voter or not.
struct PollView: View {
    @State private var poll: PollModel

    @Environment(UserSession.self) private var session
    /// Voting needs an account, behind the same login sheet as upvoting.
    @Environment(\.requireLogin) private var requireLogin

    /// Counts taps that reach a vote, to drive the haptic.
    @State private var voteTaps = 0

    init(pollID: Int, optionIDs: [Int]) {
        _poll = State(initialValue: PollModel(pollID: pollID, optionIDs: optionIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if poll.options.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(poll.options) { option in
                    optionButton(for: option)
                }
                summary
            }
        }
        // Keyed on the total, which every vote and withdrawal moves, so the
        // bars slide and the outline fades in together with the tap.
        .animation(.snappy, value: poll.totalVotes)
        .sensoryFeedback(.selection, trigger: voteTaps)
        .task { await poll.loadOptions() }
        // Re-read whenever the account changes, so signing in from the login
        // sheet brings in the reader's votes, and signing out clears them.
        .task(id: session.username) { await poll.loadBallot() }
    }

    private func optionButton(for option: PollOption) -> some View {
        let votes = poll.votes(for: option)
        let share = poll.share(of: option)
        let isVoted = poll.isVoted(option)
        return Button {
            requireLogin {
                voteTaps += 1
                Task { await poll.toggleVote(on: option) }
            }
        } label: {
            PollOptionLabel(text: option.text, votes: votes, share: share, isVoted: isVoted)
        }
        .buttonStyle(PollOptionButtonStyle())
        .disabled(poll.isClosed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(PollOptionLabel.formatted(option.text)))
        .accessibilityValue(Text("^[\(votes) vote](inflect: true), \(share.formatted(.percent.precision(.fractionLength(0))))"))
        .accessibilityAddTraits(isVoted ? .isSelected : [])
    }

    /// The total under the options, and whether voting has ended.
    private var summary: some View {
        HStack(spacing: 4) {
            Text("^[\(poll.totalVotes) vote](inflect: true)")
                .contentTransition(.numericText())
            if poll.isClosed {
                Text("·")
                Text("Closed")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}

/// One option: its wording and count over a bar showing its share.
private struct PollOptionLabel: View {
    let text: String
    let votes: Int
    /// 0 to 1.
    let share: Double
    let isVoted: Bool

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.formatted(text))
                .frame(maxWidth: .infinity, alignment: .leading)
                // Links take the tint, which is primary outside content.
                .tint(.orange)
            Text(votes, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(votes)))
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            // The bar is a second, darker fill over the track, scaled rather
            // than sized so it animates smoothly and needs no geometry reader.
            // Primary-relative, so it darkens in light mode and lightens in
            // dark; the system fills alone left the two too close to tell apart.
            ZStack {
                Color(.tertiarySystemFill)
                Color.primary.opacity(0.14)
                    .scaleEffect(x: share, y: 1, anchor: .leading)
            }
        }
        .clipShape(Self.shape)
        .overlay {
            // Orange, as an upvoted arrow is: this is the reader's vote.
            Self.shape
                .strokeBorder(.orange, lineWidth: 4)
                .opacity(isVoted ? 1 : 0)
        }
        .contentShape(Self.shape)
    }

    /// Option text is formatted as a comment's is, kept to one `Text` to sit
    /// beside the count.
    static func formatted(_ text: String) -> AttributedString {
        FormattedText.cached(text).attributedString(formatsCode: true)
    }
}

/// A light press response, and no dimming when disabled: a closed poll's
/// results should read as clearly as an open one's.
private struct PollOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
