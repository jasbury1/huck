//
//  StoryWebView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI
import WebKit

struct StoryWebView: View {
    let url: URL?
    @State private var page = WebPage()

    var body: some View {
        WebView(page)
            .onAppear {
                if let url = url {
                    page.load(URLRequest(url: url))
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .toolbar() {
                Image(systemName: "safari")
            }
    }
}
