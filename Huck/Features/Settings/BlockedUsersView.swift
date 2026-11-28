//
//  BlockedUsersView.swift
//  Huck
//
//  Created by James Asbury on 11/27/26.
//

import SwiftUI

/// The users the reader has blocked, pushed from Settings, where each can be
/// unblocked — with a swipe, as in Mail's and Messages' lists, or with the
/// button on its row.
struct BlockedUsersView: View {
    @Environment(BlockedUsersStore.self) private var blockedUsers

    var body: some View {
        List {
            Section {
                ForEach(blockedUsers.sortedUsernames, id: \.self) { username in
                    HStack {
                        Text(username)
                        Spacer()
                        Button("Unblock") {
                            unblock(username)
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Unblock", role: .destructive) {
                            unblock(username)
                        }
                        // The inherited tint beats the destructive role's red.
                        .tint(.red)
                    }
                }
            } footer: {
                if !blockedUsers.usernames.isEmpty {
                    Text("Their stories and comments are hidden in Huck on this device. Hacker News isn't told.")
                }
            }
        }
        .overlay {
            if blockedUsers.usernames.isEmpty {
                ContentUnavailableView(
                    "No Blocked Users",
                    systemImage: "person.slash",
                    description: Text("Block someone from the menu on their stories, comments, or profile to stop seeing their posts.")
                )
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unblock(_ username: String) {
        withAnimation { blockedUsers.unblock(username) }
    }
}

#Preview {
    NavigationStack {
        BlockedUsersView()
    }
    .environment(BlockedUsersStore())
}
