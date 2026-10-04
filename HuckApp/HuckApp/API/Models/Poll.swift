//
//  Poll.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// One of a poll's choices, with the votes it has drawn.
struct PollOption: Identifiable, Sendable {
    let id: Int
    /// The option's wording, as inline markdown.
    let text: String
    let votes: Int
}

/// The signed-in reader's standing in a poll: which options they've voted
/// for, and the tokens that let them vote on the rest.
///
/// Hacker News treats each option as its own item, voted up or down like any
/// other, so this is per option rather than one answer for the whole poll.
struct PollBallot: Sendable {
    /// Options the reader has voted for.
    var voted: Set<Int>

    /// Each option's per-user vote token. An option with none can't be voted
    /// on — Hacker News drops the links once a poll is archived.
    let tokens: [Int: String]

    /// Whether any option can still be voted on.
    var isOpen: Bool { !tokens.isEmpty }
}
