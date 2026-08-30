//
//  SettingsView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

/// Shared `@AppStorage` keys for feed-appearance preferences, so the Settings
/// toggle and the views that read a preference stay in sync on one identifier.
enum FeedSettings {
    static let displayStoryDomainKey = "feed.displayStoryDomain"
}

struct SettingsView: View {
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    /// Whether story cells show the link's domain after the title. Defaults on.
    @AppStorage(FeedSettings.displayStoryDomainKey) private var displayStoryDomain = true

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

                Section("Feed Appearance") {
                    Toggle(isOn: $displayStoryDomain) {
                        Label {
                            Text("Display Story Domain")
                        } icon: {
                            SettingsIcon(systemImage: "globe", color: .blue)
                        }
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
                SettingsIcon(systemImage: systemImage, color: iconColor)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The iOS Settings-style icon badge: a colored SF Symbol in a small
/// rounded-rectangle. Shared by tappable rows and toggle rows.
private struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    SettingsView()
        .environment(RecentlyViewedStore())
}
