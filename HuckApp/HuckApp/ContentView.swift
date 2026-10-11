//
//  ContentView.swift
//  HuckApp
//
//  Created by James Asbury on 12/22/25.
//

import SwiftUI
internal import Combine

struct ContentView: View {
    @StateObject var appController: ApplicationController = ApplicationController()

    /// Who is signed in — the root of the per-user object graph, since the
    /// interaction and recently-viewed stores below key their state off it.
    @State private var session: UserSession

    /// App-wide source of truth for per-story interaction state (upvotes, and
    /// later saved/hidden), observed by story views via the environment.
    @State private var interactionStore: InteractionStore

    /// Reconciles that state against the server — at launch, on returning to the
    /// foreground, on sign-in, and on pull-to-refresh. Throttled and coalesced
    /// internally, so call sites can ask freely.
    @State private var interactionSync: InteractionSync

    /// App-wide, per-user record of recently-viewed stories, observed by story
    /// views to grey seen titles and to build the account's "Recently viewed" list.
    @State private var recentlyViewedStore: RecentlyViewedStore

    /// App-wide store of the "Your Collections" lists — kept per device and
    /// synced through iCloud, independent of the HN account — observed by the
    /// home feed's collections section and the story options menu's picker.
    @State private var collectionsStore: CollectionsStore

    /// The query driving the search tab. Held here, at the tab view, so the
    /// search tab can adopt the system's separated search-button appearance.
    @State private var searchText = ""

    @Environment(\.scenePhase) private var scenePhase

    /// The window's size, measured here above the tab view and its columns, to
    /// choose the story row layout once for the whole app.
    @State private var windowSize = CGSize.zero

    /// The light/dark override, chosen in Settings. Applied here at the root of
    /// the window's content so it reaches every tab, and every sheet and popover
    /// presented from them — those follow the window's scheme, not the view they
    /// were presented from.
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Debug mode, switched on in Settings. Re-checked against the session so
    /// the tab goes away if the developer account signs out of a release build.
    @AppStorage(DebugMode.enabledKey) private var isDebugModeEnabled = false
    private var showsDebugTab: Bool {
        isDebugModeEnabled && DebugMode.isAvailable(for: session.username)
    }

    init() {
        // Built here as one graph rather than defaulting independently: each of
        // these depends on the session, and the sync also writes into the store.
        let session = UserSession()
        let interactionStore = InteractionStore(session: session)
        _session = State(initialValue: session)
        _interactionStore = State(initialValue: interactionStore)
        _interactionSync = State(initialValue: InteractionSync(store: interactionStore, session: session))
        _recentlyViewedStore = State(initialValue: RecentlyViewedStore(session: session))
        _collectionsStore = State(initialValue: CollectionsStore())
    }

    var body: some View {
        TabView {
            Tab("Feed", systemImage: "newspaper.fill") {
                FeedView()
                    .tint(.primary)
            }
            // Settings isn't a destination of its own — it's reached from the
            // gear in the Account tab's toolbar.
            Tab("Account", systemImage: "person.circle") {
                AccountView()
                    .tint(.primary)
            }
            if showsDebugTab {
                Tab("Debug", systemImage: "ladybug") {
                    DebugView()
                        .tint(.primary)
                }
            }
            // The search field is declared inside this tab, not on the tab view:
            // a `searchable` outside the `TabView` propagates into every tab and
            // puts a search bar in each one's navigation bar. `SearchView`
            // brings its own navigation stack, since opening a result has to
            // push within search rather than into another tab's stack.
            Tab(role: .search) {
                SearchView(searchText: $searchText)
                    .tint(.primary)
            }
        }
        // A bottom tab bar on iPhone; at regular widths (iPad, an unfolded
        // iPhone Duo) a top tab bar that can expand into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSearchActivation(.searchTabSelection)
        // Orange is the tab bar's selection color. Each tab's content is tinted
        // primary instead, because that's what its navigation chrome follows:
        // toolbar buttons, and the buttons of any alert shown inside it. Alerts
        // read the tint at their navigation stack, not where they're declared,
        // so this is the only level a neutral Cancel can be set from — and it
        // matches iOS's monochrome Liquid Glass bars. Content that should be
        // orange (links, toggles) is tinted where it's drawn.
        .tint(.orange)
        .preferredColorScheme(appearance.colorScheme)
        // Measured on a background that ignores the safe area, so it's the
        // whole window and the keyboard rising can't change the answer.
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        }
        // Chosen at the root, as split view columns take their environment from
        // above the split view rather than from their stacks.
        .environment(\.storyRowLayout, StoryRowLayout(windowSize: windowSize))
        .environment(session)
        .environment(interactionStore)
        .environment(interactionSync)
        .environment(recentlyViewedStore)
        .environment(collectionsStore)
        .onAppear(perform: startApp)
        // Launch.
        .task {
            await interactionSync.refresh()
        }
        // Collections changed on the user's other devices, for the app's lifetime.
        .task {
            await collectionsStore.observeCloudChanges()
        }
        // Returning to the foreground, where the drift most likely happened —
        // the user may have been on the HN site in between. Re-derive the session
        // first, since the auth cookie may have expired or changed while away.
        // `onChange` doesn't fire for the initial phase, so this doesn't double
        // up with `.task`.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            session.refresh()
            Task { await interactionSync.refresh() }
        }
        // The single reaction to the account changing, however it changed — the
        // gate's login sheet, the Account tab, an expiry noticed on foreground.
        // Every per-user store is re-pointed here, so no login path can leave one
        // behind. Order matters: the stores key their persistence off the session,
        // so reconciling before they reload would write the new account's state
        // into the old account's file.
        .onChange(of: session.account) {
            interactionStore.loadForCurrentUser()
            recentlyViewedStore.adoptGuestHistory()
            Task { await interactionSync.refresh() }
        }
    }
    
    func startApp() {
        print("Initializing application")
    }
}

class ApplicationController: ObservableObject {
    @Published private(set) var temp = false;
    
    init() {
        Task(priority: .medium){
            // Warm the main feeds, so the first visit to each is already
            // populated instead of loading on appear.
            await HackerNewsAPI.warmLaunchFeeds()
        }
    }
}

#Preview {
    ContentView()
}
