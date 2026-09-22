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

    /// Who is signed in — the root of the per-user object graph, since the three
    /// stores below all key their state off it.
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

    /// App-wide, per-user store of the "Your Collections" lists, observed by the
    /// home feed's collections section and the story options menu's picker.
    @State private var collectionsStore: CollectionsStore

    /// The query driving the search tab. Held here, at the tab view, so the
    /// search tab can adopt the system's separated search-button appearance.
    @State private var searchText = ""

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Built here as one graph rather than defaulting independently: each of
        // these depends on the session, and the sync also writes into the store.
        let session = UserSession()
        let interactionStore = InteractionStore(session: session)
        _session = State(initialValue: session)
        _interactionStore = State(initialValue: interactionStore)
        _interactionSync = State(initialValue: InteractionSync(store: interactionStore, session: session))
        _recentlyViewedStore = State(initialValue: RecentlyViewedStore(session: session))
        _collectionsStore = State(initialValue: CollectionsStore(session: session))
    }

    var body: some View {
        TabView {
            Tab("Feed", systemImage: "newspaper.fill") {
                FeedView()
            }
            // Settings isn't a destination of its own — it's reached from the
            // gear in the Account tab's toolbar.
            Tab("Account", systemImage: "person.circle") {
                AccountView()
            }
            // The search field is declared inside this tab, not on the tab view:
            // a `searchable` outside the `TabView` propagates into every tab and
            // puts a search bar in each one's navigation bar.
            Tab(role: .search) {
                NavigationStack {
                    SearchView()
                        .searchable(text: $searchText)
                }
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .tint(.orange)
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
            collectionsStore.loadForCurrentUser()
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
            let ids = await HackerNewsAPI.getStoryIds(filter: .topStories)

            // Warm the first screen's details *and* thumbnails at launch, so the
            // very first visit to Top Stories is already populated instead of
            // fetching thumbnails on appear. Then warm the rest of the details.
            let firstWindow = Array(ids.prefix(HackerNewsAPI.thumbnailPrefetchWindow))
            await HackerNewsAPI.prefetchStories(ids: firstWindow)
            await HackerNewsAPI.prefetchThumbnails(ids: firstWindow)
            await HackerNewsAPI.prefetchStories(ids: ids)
        }
    }
}

#Preview {
    ContentView()
}
