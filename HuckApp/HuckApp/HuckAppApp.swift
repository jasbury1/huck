//
//  HuckAppApp.swift
//  HuckApp
//
//  Created by James Asbury on 12/22/25.
//

import SwiftUI

@main
struct HuckAppApp: App {
    var body: some Scene {
        WindowGroup {
            // The light/dark override is applied inside `ContentView`, and
            // deliberately not here as well. An `@AppStorage` change doesn't
            // re-evaluate an `App`'s body, so a copy at this level would hold
            // whatever the setting was at launch — and being the outer of the
            // two, it would win, masking the live one below it.
            ContentView()
        }
    }
}
