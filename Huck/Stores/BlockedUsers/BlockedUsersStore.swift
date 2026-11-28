//
//  BlockedUsersStore.swift
//  Huck
//
//  Created by James Asbury on 11/27/26.
//

import SwiftUI

/// The source of truth for the users the reader has blocked. A blocked user's
/// stories are left out of the feeds (see `FeedFilter.blockedUsers`) and their
/// comments, with the replies beneath them, out of threads (see
/// `CommentFetcher`).
///
/// Hacker News has no block of its own, so this never touches the network. It
/// belongs to the device rather than an account — unlike `InteractionStore` —
/// so it works signed out too, and nothing needs reloading when the account
/// changes. Injected app-wide via the environment.
@MainActor
@Observable
final class BlockedUsersStore {
    /// The store's single observed property, so reads in a view body refresh
    /// when someone is blocked or unblocked.
    private(set) var usernames: Set<String> = []

    init() {
        usernames = BlockedUsersPersistence.load().usernames
    }

    /// The blocked usernames in alphabetical order, for listing them in
    /// Settings.
    var sortedUsernames: [String] {
        usernames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func isBlocked(_ username: String) -> Bool {
        usernames.contains(username)
    }

    /// Blocks a user. An empty name — a story or comment whose details haven't
    /// loaded — is ignored.
    func block(_ username: String) {
        guard !username.isEmpty else { return }
        usernames.insert(username)
        persist()
    }

    func unblock(_ username: String) {
        usernames.remove(username)
        persist()
    }

    private func persist() {
        BlockedUsersPersistence.save(PersistedBlockedUsers(usernames: usernames))
    }
}
