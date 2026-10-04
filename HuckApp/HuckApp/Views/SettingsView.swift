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

/// Shared `@AppStorage` keys for how comments and posts are read.
enum ReadingSettings {
    /// Whether code is drawn as code — monospaced, in a block of its own — or
    /// as ordinary text. Defaults on.
    static let formatsCodeKey = "reading.formatsCode"
}

/// The app's preferences, presented as a sheet from the Account tab's toolbar.
/// It brings its own `NavigationStack` for the title bar, rather than joining
/// the account tab's — that stack is for story navigation.
struct SettingsView: View {
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(\.dismiss) private var dismiss

    /// Whether story cells show the link's domain after the title. Defaults on.
    @AppStorage(FeedSettings.displayStoryDomainKey) private var displayStoryDomain = true

    @AppStorage(ReadingSettings.formatsCodeKey) private var formatsCode = true

    /// Light/dark override. Applied at the app's root, not here — this is only
    /// where it's chosen.
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Shows the Debug tab. Only offered where `DebugMode.isAvailable`.
    @AppStorage(DebugMode.enabledKey) private var isDebugModeEnabled = false
    @Environment(UserSession.self) private var session

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

                Section("Appearance") {
                    // The badge tracks the selection, so the row reads as the
                    // current appearance at a glance.
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    } label: {
                        Label {
                            Text("Theme")
                        } icon: {
                            SettingsIcon(systemImage: appearance.systemImage, color: .indigo)
                        }
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

                Section {
                    Toggle(isOn: $formatsCode) {
                        Label {
                            Text("Format Code")
                        } icon: {
                            SettingsIcon(systemImage: "chevron.left.forwardslash.chevron.right", color: .teal)
                        }
                    }
                } header: {
                    Text("Comments")
                } footer: {
                    Text("Shows code in a monospaced font, set apart from the text around it.")
                }

                if DebugMode.isAvailable(for: session.username) {
                    Section {
                        Toggle(isOn: $isDebugModeEnabled) {
                            Label {
                                Text("Debug Mode")
                            } icon: {
                                SettingsIcon(systemImage: "ladybug", color: .gray)
                            }
                        }
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("Adds a Debug tab with counts of every API request the app makes.")
                    }
                }
            }
            // Toggles and the picker are content, so they keep the app's orange;
            // the toolbar and the alert below follow the primary chrome tint.
            .tint(.orange)
            .navigationTitle("Settings")
            // Also applied here, not just at the app's root. A sheet takes the
            // window's appearance when it's presented but doesn't restyle when
            // that changes underneath it — and this sheet is the one place the
            // setting can be changed, so without this the picker would appear
            // to do nothing until it was dismissed.
            .preferredColorScheme(appearance.colorScheme)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        .environment(RecentlyViewedStore(session: UserSession()))
        .environment(UserSession())
}
