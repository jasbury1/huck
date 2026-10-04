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
    /// The `FeedFilters` turned on from a feed's options menu.
    static let filtersKey = "feed.filters"
}

/// Shared `@AppStorage` keys for how comments and posts are read.
enum ReadingSettings {
    /// Whether code is drawn as code — monospaced, in a block of its own — or
    /// as ordinary text. Defaults on.
    static let formatsCodeKey = "reading.formatsCode"
    /// Whether paragraphs quoted with `>` are set apart in an outlined box,
    /// or left as written. Defaults on.
    static let formatsQuotesKey = "reading.formatsQuotes"
    /// Whether new accounts' names are tinted green in threads, as on Hacker
    /// News. Defaults on. Off also skips the page read that finds them.
    static let highlightsNewUsersKey = "reading.highlightsNewUsers"
}

/// The app's preferences, presented as a sheet from the Account tab's toolbar.
/// It brings its own `NavigationStack` rather than joining the account tab's,
/// which sits behind the sheet; stories opened from Hidden Stories are pushed
/// onto this one.
struct SettingsView: View {
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    /// Counts the hidden stories for their row.
    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.dismiss) private var dismiss

    /// Whether story cells show the link's domain after the title. Defaults on.
    @AppStorage(FeedSettings.displayStoryDomainKey) private var displayStoryDomain = true

    @AppStorage(ReadingSettings.formatsCodeKey) private var formatsCode = true
    @AppStorage(ReadingSettings.formatsQuotesKey) private var formatsQuotes = true
    @AppStorage(ReadingSettings.highlightsNewUsersKey) private var highlightsNewUsers = true

    /// Light/dark override. Applied at the app's root, not here — this is only
    /// where it's chosen.
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Shows the Debug tab. Only offered where `DebugMode.isAvailable`.
    @AppStorage(DebugMode.enabledKey) private var isDebugModeEnabled = false
    @Environment(UserSession.self) private var session

    @State private var isConfirmingClearHistory = false

    /// Settings' own stack. Hidden Stories lists real story cells, so it's a
    /// story stack too: tapping one opens it here, in the sheet.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Activity") {
                    NavigationLink(value: SettingsPage.hiddenStories) {
                        Label {
                            Text("Hidden Stories")
                        } icon: {
                            SettingsIcon(systemImage: "eye.slash", color: .gray)
                        }
                    }
                    .badge(interactionStore.hiddenIDs.count)
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
                    Toggle(isOn: $formatsQuotes) {
                        Label {
                            Text("Format Quotes")
                        } icon: {
                            SettingsIcon(systemImage: "quote.opening", color: .purple)
                        }
                    }
                    Toggle(isOn: $highlightsNewUsers) {
                        Label {
                            Text("Highlight New Users")
                        } icon: {
                            SettingsIcon(systemImage: "person.badge.clock", color: .green)
                        }
                    }
                } header: {
                    Text("Comments")
                } footer: {
                    Text("Format Code shows code in a monospaced font, set apart from the text around it. Format Quotes outlines paragraphs quoted with “>”. Highlight New Users tints the names of recently created accounts green, as Hacker News does while you're signed in.")
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
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .hiddenStories:
                    HiddenStoriesView(path: $path)
                }
            }
            .navigationDestination(for: ItemNavigation.self) { navigation in
                StoryDetailsView(from: navigation, path: $path)
            }
        }
        // The same story handling as the app's own stacks, for the story cells
        // Hidden Stories shows. Applied here rather than inherited from the
        // account tab: its browser would try to present from behind this
        // sheet, and its links would land on the account tab's stack.
        .inAppBrowser(path: $path)
        .storyActionsEnabled()
    }
}

/// The pages Settings pushes onto its own stack.
private enum SettingsPage: Hashable {
    case hiddenStories
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
        // Fitted into a fixed inner box rather than sized by font, so a wide
        // symbol (the code brackets, the eye) keeps the same margin to the
        // badge's edge as a narrow one, as in the Settings app.
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(width: 18, height: 18)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    SettingsView()
        .environment(RecentlyViewedStore(session: UserSession()))
        .environment(InteractionStore(session: UserSession()))
        .environment(UserSession())
}
