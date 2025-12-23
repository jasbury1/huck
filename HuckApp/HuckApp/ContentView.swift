//
//  ContentView.swift
//  HuckApp
//
//  Created by James Asbury on 12/22/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "newspaper.fill") {
                FeedView()
            }
            Tab("Account", systemImage: "person.circle") {
                FeedView()
            }
            
            Tab("Settings", systemImage: "gearshape.fill") {
                FeedView()
            }
            Tab(role: .search) {}
        }
        .tint(.orange)
        
    }
}

#Preview {
    ContentView()
}
