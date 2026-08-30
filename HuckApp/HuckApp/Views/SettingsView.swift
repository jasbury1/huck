//
//  SettingsView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    @State private var isConfirmingClearHistory = false

    var body: some View {
        NavigationStack {
            List {
                Section("Activity") {
                    SettingsRow(
                        title: "Clear Viewing History",
                        systemImage: "clock.arrow.circlepath",
                        iconColor: .orange
                    ) {
                        isConfirmingClearHistory = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Clear Viewing History?", isPresented: $isConfirmingClearHistory) {
                Button("Clear", role: .destructive) {
                    recentlyViewedStore.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your list of recently viewed stories. This can't be undone.")
            }
        }
    }
}

/// A single tappable settings row styled like the iOS Settings app: a colored
/// SF Symbol inside a small rounded-rectangle badge, followed by a title.
private struct SettingsRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(RecentlyViewedStore())
}
