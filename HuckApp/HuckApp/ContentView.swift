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
    
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "newspaper.fill") {
                FeedView()
            }
            Tab("Account", systemImage: "person.circle") {
                AccountView()
                //UserView(username: "zdw")
            }
            
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
            Tab(role: .search) {
                SearchView()
            }
        }
        .tint(.orange)
        .onAppear(perform: startApp)
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
