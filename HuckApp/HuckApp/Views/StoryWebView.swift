//
//  StoryWebView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI
import WebKit

struct StoryWebView: UIViewRepresentable {
    var url: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = url {
            uiView.load(URLRequest(url: url))
        }
    }
}
