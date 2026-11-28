//
//  SafariView.swift
//  Huck
//
//  Created by James Asbury on 8/5/26.
//

import SafariServices
import SwiftUI

/// Presents `SFSafariViewController` -- Apple's standardized in-app browser --
/// whenever `link` is set. It shares Safari's networking and cache (so pages
/// load fast) and provides the familiar chrome: a Reader-capable address bar
/// plus the bottom toolbar with share, back/forward, and an "open in Safari"
/// button.
///
/// Apple requires `SFSafariViewController` to be presented modally, never
/// embedded, and it dismisses itself when its Done button is tapped. So it's
/// presented the way UIKit expects, from an invisible anchor view controller,
/// rather than inside a SwiftUI `fullScreenCover`. A cover would be dismissed
/// twice — once by Safari, then again by SwiftUI when `link` is cleared — and
/// the second dismissal closes whatever presented the cover, such as the
/// Settings sheet.
private struct SafariPresenter: UIViewControllerRepresentable {
    @Binding var link: BrowserLink?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.link = $link
        if let link, coordinator.browser == nil {
            let browser = SFSafariViewController(url: link.url)
            browser.delegate = coordinator
            browser.modalPresentationStyle = .fullScreen
            coordinator.browser = browser
            anchor.present(browser, animated: true)
        } else if link == nil, let browser = coordinator.browser {
            // Cleared from code rather than by Done, so it's still showing.
            coordinator.browser = nil
            browser.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(link: $link)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var link: Binding<BrowserLink?>
        /// The browser on screen, if any.
        weak var browser: SFSafariViewController?

        init(link: Binding<BrowserLink?>) {
            self.link = link
        }

        /// Done was tapped or the browser swiped away. Safari has dismissed
        /// itself, so this only catches the state up — and forgets the browser
        /// first, so the update that follows doesn't dismiss it again.
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            browser = nil
            link.wrappedValue = nil
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

/// The page the in-app browser is showing.
private struct BrowserLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct InAppBrowserModifier: ViewModifier {
    @Binding var path: NavigationPath
    @State private var link: BrowserLink?
    @Environment(\.openThread) private var openThread

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
            .background {
                SafariPresenter(link: $link)
            }
    }

    /// Pushes the in-app screen for a link to Hacker News, returning whether
    /// `url` was one. Items open as threads, which a split view shows in its
    /// detail column.
    private func navigate(to url: URL) -> Bool {
        guard let destination = ItemNavigation(hackerNewsURL: url) else { return false }
        switch destination {
        case .item, .textStory:
            openThread(destination, from: $path)
        default:
            path.append(destination)
        }
        return true
    }
}

extension View {
    /// Enables `openInAppBrowser` for this view's subtree, presenting tapped
    /// links full screen in an `SFSafariViewController`. Links to Hacker
    /// News itself — stories, comments, and profiles, whether a story's link or
    /// one inside a comment — are pushed onto `path` instead, to open in the
    /// app. Apply it once per navigation stack, above the content that opens
    /// links.
    func inAppBrowser(path: Binding<NavigationPath>) -> some View {
        modifier(InAppBrowserModifier(path: path))
    }
}
