//
//  ModerationActions.swift
//  Huck
//
//  Created by James Asbury on 11/27/26.
//

import SwiftUI

/// A story or comment the reader can flag for Hacker News' moderators.
struct FlagTarget: Hashable {
    enum Kind {
        case story
        case comment
    }

    let id: Int
    let kind: Kind

    static func story(_ id: Int) -> FlagTarget { FlagTarget(id: id, kind: .story) }
    static func comment(_ id: Int) -> FlagTarget { FlagTarget(id: id, kind: .comment) }

    /// The item's page on Hacker News, for reporting it by email instead.
    var hackerNewsURL: URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }
}

/// Asks to flag a story or comment, behind the login gate and a confirmation.
/// Owned by `storyActionsEnabled()` for the same reason as
/// `AddToCollectionAction`: it's offered from menus, which are gone by the time
/// an alert attached to them would appear.
struct FlagAction {
    let handler: (FlagTarget) -> Void
    func callAsFunction(_ target: FlagTarget) { handler(target) }
}

/// Asks to block a user, behind a confirmation. Blocking is kept on the device,
/// so there's no login gate.
struct BlockUserAction {
    let handler: (String) -> Void
    func callAsFunction(_ username: String) { handler(username) }
}

extension EnvironmentValues {
    @Entry var flag = FlagAction { _ in }
    @Entry var blockUser = BlockUserAction { _ in }
}

// MARK: - Menu rows

/// Flags a story or comment. Left out of the reader's own, which Hacker News
/// doesn't let them flag.
struct FlagMenuButton: View {
    let target: FlagTarget
    let author: String

    @Environment(\.flag) private var flag
    @Environment(UserSession.self) private var session

    var body: some View {
        if author != session.username {
            Button {
                flag(target)
            } label: {
                Label("Flag", systemImage: "flag")
            }
        }
    }
}

/// Blocks a user, or unblocks one already blocked. Left out for the reader
/// themselves, and for an author not yet known — a story still loading.
struct BlockUserMenuButton: View {
    let username: String

    @Environment(\.blockUser) private var blockUser
    @Environment(BlockedUsersStore.self) private var blockedUsers
    @Environment(UserSession.self) private var session

    var body: some View {
        if !username.isEmpty, username != session.username {
            if blockedUsers.isBlocked(username) {
                Button {
                    blockedUsers.unblock(username)
                } label: {
                    Label("Unblock \(username)", systemImage: "person")
                }
            } else {
                Button(role: .destructive) {
                    blockUser(username)
                } label: {
                    Label("Block \(username)", systemImage: "person.slash")
                }
                // The menu tints its icons primary, and the role colors only
                // the text, so the icon is tinted red to match.
                .tint(.red)
            }
        }
    }
}

// MARK: - Presentation

/// What came of a flag, for the alert that reports it.
private enum FlagOutcome {
    case flagged
    case failed(FlagTarget, any Error)
}

/// Wires `\.flag` and `\.blockUser` for its subtree, and presents the
/// confirmations and results they need. Applied by `storyActionsEnabled()`,
/// inside the modifier that provides `\.requireLogin`.
struct ModerationModifier: ViewModifier {
    @Environment(\.hackerNews) private var api
    @Environment(\.requireLogin) private var requireLogin
    @Environment(\.openURL) private var openURL
    @Environment(BlockedUsersStore.self) private var blockedUsers

    /// The item the reader is being asked to confirm flagging.
    @State private var flagTarget: FlagTarget?
    @State private var flagOutcome: FlagOutcome?
    /// The user the reader is being asked to confirm blocking.
    @State private var blockTarget: String?

    func body(content: Content) -> some View {
        content
            .environment(\.flag, FlagAction { target in
                requireLogin { flagTarget = target }
            })
            .environment(\.blockUser, BlockUserAction { username in
                blockTarget = username
            })
            .alert(flagConfirmationTitle, item: $flagTarget) { target in
                Button("Flag", role: .destructive) {
                    Task { await flag(target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Flagging asks Hacker News' moderators to review it against the site guidelines.")
            }
            .alert(flagOutcomeTitle, item: $flagOutcome) { outcome in
                if case let .failed(target, _) = outcome, let url = reportEmailURL(for: target) {
                    Button("Email Moderators") { openURL(url) }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { outcome in
                switch outcome {
                case .flagged:
                    Text("Thanks. Hacker News' moderators will take a look.")
                case let .failed(_, error):
                    Text(error.localizedDescription)
                }
            }
            .alert(blockConfirmationTitle, item: $blockTarget) { username in
                Button("Block", role: .destructive) {
                    withAnimation { blockedUsers.block(username) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their stories or comments. You can unblock them in Settings.")
            }
    }

    private func flag(_ target: FlagTarget) async {
        do {
            try await api.flagItem(id: target.id)
            flagOutcome = .flagged
        } catch {
            flagOutcome = .failed(target, error)
        }
    }

    private var flagConfirmationTitle: LocalizedStringResource {
        switch flagTarget?.kind {
        case .comment: "Flag This Comment?"
        case .story, nil: "Flag This Story?"
        }
    }

    private var flagOutcomeTitle: LocalizedStringResource {
        switch flagOutcome {
        case .failed: "Couldn't Flag"
        case .flagged, nil: "Flagged"
        }
    }

    private var blockConfirmationTitle: LocalizedStringResource {
        "Block \(blockTarget ?? "")?"
    }

    /// A message to Hacker News' moderators about the item, the way the site's
    /// guidelines ask anyone to report something that flagging can't.
    private func reportEmailURL(for target: FlagTarget) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hn@ycombinator.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Reporting \(target.hackerNewsURL.absoluteString)"),
            URLQueryItem(name: "body", value: "\(target.hackerNewsURL.absoluteString)\n\n"),
        ]
        return components.url
    }
}
