//
//  PollModel.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// A poll's options and the reader's votes in it, for the poll shown above a
/// thread.
///
/// The vote state lives here rather than in `InteractionStore`, which exists
/// to keep a story consistent across the many places it's shown. A poll's
/// options are only ever shown in one place, and the reader's votes are read
/// back from Hacker News each time the poll is opened, so there's nothing to
/// keep in step or to persist.
@MainActor
@Observable
final class PollModel {
    let pollID: Int
    let optionIDs: [Int]

    private(set) var options: [PollOption] = []

    /// `nil` until read, and whenever the reader is signed out.
    private(set) var ballot: PollBallot?

    /// Optimistic change to each option's count while a vote is applied, so
    /// the bars move on the tap rather than on the next load.
    private var voteDeltas: [Int: Int] = [:]

    /// Options with a vote on its way, so a quick second tap can't race it.
    private var votesInFlight: Set<Int> = []

    init(pollID: Int, optionIDs: [Int]) {
        self.pollID = pollID
        self.optionIDs = optionIDs
    }

    // MARK: - Reading

    func votes(for option: PollOption) -> Int {
        option.votes + voteDeltas[option.id, default: 0]
    }

    var totalVotes: Int {
        options.reduce(0) { $0 + votes(for: $1) }
    }

    /// The option's fraction of all votes cast, from 0 to 1.
    func share(of option: PollOption) -> Double {
        let total = totalVotes
        return total > 0 ? Double(votes(for: option)) / Double(total) : 0
    }

    func isVoted(_ option: PollOption) -> Bool {
        ballot?.voted.contains(option.id) ?? false
    }

    /// Whether Hacker News has closed the poll. Known only once a signed-in
    /// reader's ballot has loaded; until then it's presumed open, and a tap
    /// finds out.
    var isClosed: Bool {
        ballot.map { !$0.isOpen } ?? false
    }

    // MARK: - Loading

    func loadOptions() async {
        guard options.isEmpty else { return }
        options = await HackerNewsAPI.getPollOptions(ids: optionIDs)
    }

    /// Reads the reader's votes, or clears them when no one is signed in.
    func loadBallot() async {
        ballot = await HackerNewsAPI.pollBallot(pollID: pollID, optionIDs: optionIDs)
    }

    // MARK: - Voting

    /// Votes for an option, or withdraws the vote if it has one: updated
    /// optimistically, and rolled back if Hacker News refuses. Callers gate
    /// this behind login.
    func toggleVote(on option: PollOption) async {
        let id = option.id
        guard !votesInFlight.contains(id) else { return }
        votesInFlight.insert(id)
        defer { votesInFlight.remove(id) }

        // Tapped before the ballot arrived — straight after signing in, say.
        if ballot == nil { await loadBallot() }
        guard let ballot, ballot.tokens[id] != nil else { return }

        let wasVoted = ballot.voted.contains(id)
        setVoted(!wasVoted, on: id)
        do {
            try await HackerNewsAPI.setPollVote(optionID: id, voted: !wasVoted, ballot: ballot)
        } catch {
            setVoted(wasVoted, on: id)
            print("Poll vote failed for \(id): \(error)")
        }
    }

    private func setVoted(_ voted: Bool, on id: Int) {
        guard ballot?.voted.contains(id) != voted else { return }
        if voted {
            ballot?.voted.insert(id)
        } else {
            ballot?.voted.remove(id)
        }
        voteDeltas[id, default: 0] += voted ? 1 : -1
    }
}
