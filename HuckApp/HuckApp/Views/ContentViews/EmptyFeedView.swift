//
//  EmptyFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

/// The placeholder shown when a feed has finished loading with no content —
/// an empty Posts, Comments, Favorites, or Recently Viewed tab. Deliberately
/// understated (small, secondary-colored, light weights) rather than the large,
/// bold `ContentUnavailableView`, so an empty tab reads as quiet, not alarming.
struct EmptyFeedView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 56)
    }
}
