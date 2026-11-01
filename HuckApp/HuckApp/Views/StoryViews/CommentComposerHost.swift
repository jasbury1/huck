//
//  CommentComposerHost.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import SwiftUI

/// Draws a thread's comment composer over the whole of a split view, rather
/// than inside the thread's own column.
///
/// The keyboard spans the window, so beside a list — an unfolded iPhone Duo,
/// an iPad — a composer held to the thread's column sits off to one side of
/// it. `hostsCommentComposer()` puts a host in the environment; a thread on
/// screen hands it what the composer needs with `commentComposer(…)`, and the
/// host draws it. Where there's no host, the thread draws the composer itself.
@MainActor
@Observable
final class CommentComposerHost {
    /// What a thread hands over for its composer to be drawn.
    struct Request {
        /// The comment being written. Also identifies the thread that made
        /// the request, as each thread owns exactly one draft.
        let draft: CommentDraft
        let storyTitle: String
        let floatsComposeButton: Bool
        let onSubmit: (String) async throws -> Void
    }

    /// The composer to draw, if a thread on screen has asked for one.
    fileprivate private(set) var request: Request?

    /// Draws `request`'s composer, replacing any other thread's.
    fileprivate func show(_ request: Request) {
        self.request = request
    }

    /// Stops drawing the composer for `draft`, if it's still the one shown. A
    /// thread taking over may ask to be shown before the thread it replaces
    /// asks to be dismissed, so a stale dismissal must leave the new one be.
    fileprivate func dismiss(_ draft: CommentDraft) {
        if request?.draft === draft {
            request = nil
        }
    }
}

extension View {
    /// Draws the comment composer of whichever thread inside this view is on
    /// screen, across the whole of this view. Apply to a split view, so the
    /// composer centers over the keyboard rather than over one column.
    func hostsCommentComposer() -> some View {
        modifier(CommentComposerHostModifier())
    }

    /// Shows a comment composer for `draft` — drawn by the nearest
    /// `hostsCommentComposer()` while this view is on screen, or over this
    /// view itself where there's no host.
    func commentComposer(
        draft: CommentDraft,
        storyTitle: String,
        floatsComposeButton: Bool,
        onSubmit: @escaping (String) async throws -> Void
    ) -> some View {
        modifier(CommentComposerModifier(
            request: .init(
                draft: draft,
                storyTitle: storyTitle,
                floatsComposeButton: floatsComposeButton,
                onSubmit: onSubmit
            )
        ))
    }
}

private struct CommentComposerHostModifier: ViewModifier {
    @State private var host = CommentComposerHost()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let request = host.request {
                    CommentComposer(request: request)
                        // A fresh composer per thread, so one thread's state
                        // never carries into the next. Its draft lives on with
                        // the thread, so nothing written is lost.
                        .id(ObjectIdentifier(request.draft))
                }
            }
            .environment(host)
    }
}

private struct CommentComposerModifier: ViewModifier {
    let request: CommentComposerHost.Request

    @Environment(CommentComposerHost.self) private var host: CommentComposerHost?

    /// Whether this thread is on screen, the only time it holds the host.
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if host == nil {
                    CommentComposer(request: request)
                }
            }
            // Handed to the host only while on screen, so a page pushed above
            // the thread — or another tab — doesn't sit under its composer.
            .onAppear {
                isOnScreen = true
                host?.show(request)
            }
            .onDisappear {
                isOnScreen = false
                host?.dismiss(request.draft)
            }
            // Handed over again whenever what it shows changes.
            .onChange(of: request.storyTitle) { showIfOnScreen() }
            .onChange(of: request.floatsComposeButton) { showIfOnScreen() }
    }

    private func showIfOnScreen() {
        if isOnScreen { host?.show(request) }
    }
}

private extension CommentComposer {
    init(request: CommentComposerHost.Request) {
        self.init(
            draft: request.draft,
            storyTitle: request.storyTitle,
            floatsComposeButton: request.floatsComposeButton,
            onSubmit: request.onSubmit
        )
    }
}
