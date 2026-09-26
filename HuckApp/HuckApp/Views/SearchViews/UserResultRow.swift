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

    var body: some View {
        Button {
            path.append(ItemNavigation.userProfile(user: user.username))
        } label: {
            HStack(spacing: 12) {
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
}

#Preview {
    UserResultRow(
        user: User(
            username: "pg",
            karma: 157_432,
            about: "Co-founder of Y Combinator. Essays at paulgraham.com."
        ),
        path: .constant(NavigationPath())
    )
}
