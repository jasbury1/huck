//
//  UserResultRow.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import SwiftUI

/// A user found by the search tab's Users category: their name, karma, and the
/// opening of their bio, as a row that opens the full profile.
struct UserResultRow: View {
    let user: User
    @Binding var path: NavigationPath

    /// The colours an avatar can take. Chosen to sit alongside the category
    /// pills rather than clash with them.
    private static let avatarColors: [Color] = [
        .orange, .blue, .purple, .pink, .teal, .indigo, .green, .red, .mint, .cyan,
    ]

    var body: some View {
        Button {
            path.append(ItemNavigation.userProfile(user: user.username))
        } label: {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(user.karma) karma")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !user.about.isEmpty {
                        Text(user.about)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var avatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(avatarColor)
            // Hacker News has no avatars, so this stands in for one rather than
            // saying anything — the name beside it is the information.
            .accessibilityHidden(true)
    }

    /// A colour picked from the username: arbitrary to look at, but the *same*
    /// arbitrary colour every time, so a user doesn't change colour as the row
    /// redraws or between launches. Hashed by hand because Swift's `Hasher` is
    /// seeded per process and so gives a different answer each run.
    private var avatarColor: Color {
        var hash: UInt64 = 5381
        for byte in user.username.lowercased().utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Self.avatarColors[Int(hash % UInt64(Self.avatarColors.count))]
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(["pg", "patio11", "tptacek", "jamesasbury"], id: \.self) { name in
            UserResultRow(
                user: User(
                    username: name,
                    karma: 157_432,
                    about: "Co-founder of Y Combinator. Essays at paulgraham.com."
                ),
                path: .constant(NavigationPath())
            )
            Divider()
        }
    }
}
