//
//  SafariView.swift
//  HuckApp
//
//  Created by James Asbury on 8/5/26.
//

import SwiftUI
import SafariServices

/// A SwiftUI wrapper around `SFSafariViewController` -- Apple's standardized
/// in-app browser. It shares Safari's networking and cache (so pages load fast)
/// and provides the familiar chrome: a Reader-capable address bar plus the
/// bottom toolbar with share, back/forward, and an "open in Safari" button.
///
/// Apple requires `SFSafariViewController` to be presented modally, never
/// embedded in a view-controller hierarchy — so this is surfaced through the
/// `.inAppBrowser()` modifier's full-screen cover rather than a navigation push.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    /// Called when the user taps Done or swipes the browser away, so the
    /// presenting cover can be dismissed.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

// MARK: - Presentation

/// An action that opens a URL in the app's in-app Safari browser. Injected into
/// the environment by `.inAppBrowser()` and called from anywhere below it, so
/// link-tap sites don't need to know how the browser is presented.
struct OpenInAppBrowserAction {
    fileprivate let handler: (URL) -> Void

    func callAsFunction(_ url: URL) {
        handler(url)
    }
}

extension EnvironmentValues {
    @Entry var openInAppBrowser = OpenInAppBrowserAction { _ in }
}

/// Wraps a URL so it can drive a `fullScreenCover(item:)` without conforming
/// `URL` itself to `Identifiable` app-wide.
private struct BrowserLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct InAppBrowserModifier: ViewModifier {
    @Binding var path: NavigationPath
    @State private var link: BrowserLink?

    func body(content: Content) -> some View {
        content
            .environment(\.openInAppBrowser, OpenInAppBrowserAction { url in
                if !navigate(to: url) {
                    link = BrowserLink(url: url)
                }
            })
            // Links inside comment and post text go through `openURL`. Only
            // Hacker News's own are taken over; the rest carry on to the
            // system as before.
            .environment(\.openURL, OpenURLAction { url in
                navigate(to: url) ? .handled : .systemAction
            })
            .fullScreenCover(item: $link) { link in
                SafariView(url: link.url) { self.link = nil }
                    .ignoresSafeArea()
            }
    }

    /// Pushes the in-app screen for a link to Hacker News, returning whether
    /// `url` was one.
    private func navigate(to url: URL) -> Bool {
        guard let destination = ItemNavigation(hackerNewsURL: url) else { return false }
        path.append(destination)
        return true
    }
}

extension View {
    /// Enables `openInAppBrowser` for this view's subtree, presenting tapped
    /// links in an `SFSafariViewController` full-screen cover. Links to Hacker
    /// News itself — stories, comments, and profiles, whether a story's link or
    /// one inside a comment — are pushed onto `path` instead, to open in the
    /// app. Apply it once per navigation stack, above the content that opens
    /// links.
    func inAppBrowser(path: Binding<NavigationPath>) -> some View {
        modifier(InAppBrowserModifier(path: path))
    }
}
