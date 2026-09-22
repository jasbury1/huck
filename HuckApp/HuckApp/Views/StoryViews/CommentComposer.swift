//
//  CommentComposer.swift
//  HuckApp
//
//  Created by James Asbury on 9/19/26.
//

import SwiftUI

/// The size of the comment composer, ordered smallest to largest. Swiping the
/// composer's grabber moves exactly one step along this ladder, so the raw
/// values are meaningful: neighbouring cases are neighbouring sizes.
enum CommentComposerState: Int, CaseIterable, Comparable {
    /// No draft. Only the compose button is shown.
    case cancelled
    /// A single line of the draft, with the keyboard down.
    case collapsed
    /// The everyday writing size: grows with the content up to a cap.
    case normal
    /// A larger editing surface, the future home of richer input options.
    case expanded

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The next state up, or this one if already the largest.
    var raised: Self { Self(rawValue: rawValue + 1) ?? self }

    /// The next state down, or this one if already the smallest.
    var lowered: Self { Self(rawValue: rawValue - 1) ?? self }

    /// Whether the keyboard belongs on screen in this state.
    var wantsKeyboard: Bool { self >= .normal }

    /// How far the text box may grow before it starts scrolling internally.
    var lineLimit: ClosedRange<Int> {
        switch self {
        case .cancelled, .collapsed: 1...1
        case .normal: 1...5
        case .expanded: 6...14
        }
    }
}

/// A Liquid Glass comment composer that lives in the bottom-trailing corner of
/// a story. It travels through `CommentComposerState`: at rest it's a compact
/// compose button, and it grows into a text box that can be collapsed to a
/// single line or expanded into a larger editor.
///
/// Dragging the grabber moves one state per swipe; the text box's glass shape
/// morphs between sizes because every state shares one `glassEffectID`.
struct CommentComposer: View {
    /// The comment being replied to, or `nil` for a new top-level comment.
    /// Setting it opens the composer; discarding the draft clears it. Owned by
    /// the caller so a Reply action anywhere in the thread can drive the
    /// composer, and so the caller knows where to post the draft.
    @Binding var replyTarget: Comment?

    /// Called with the trimmed comment when the user taps send.
    let onSubmit: (String) -> Void

    @State private var state: CommentComposerState = .cancelled
    @State private var draft = ""
    /// Live vertical drag on the grabber, so the composer follows the finger
    /// before the gesture commits to a state change.
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isFocused: Bool
    /// Presents the "discard this comment?" confirmation.
    @State private var isConfirmingDiscard = false
    /// Lets the button and the text box morph into one another.
    @Namespace private var namespace

    /// One shared animation so every size change feels like the same control.
    private let transition = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// How far the grabber must travel (including fling) to change state.
    private let dragThreshold: CGFloat = 40

    /// The draft with surrounding whitespace removed — what actually gets sent.
    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            if state == .cancelled {
                composeButton
            } else {
                HStack(spacing: 12) {
                    editor
                    cancelButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(y: dragOffset)
        // A Reply action elsewhere in the thread sets the target while the
        // composer is closed, so open it — and focus the field — in response.
        .onChange(of: replyTarget?.id) { _, id in
            if id != nil, state == .cancelled {
                move(to: .normal)
            }
        }
        // Keeps the state in step with focus changes the composer didn't drive:
        // tapping the field while collapsed starts writing, and dismissing the
        // keyboard (Return, or the keyboard's own gesture) collapses the box.
        .onChange(of: isFocused) { _, focused in
            if focused, state == .collapsed {
                move(to: .normal)
            } else if !focused, state.wantsKeyboard {
                move(to: .collapsed)
            }
        }
        // Alerts are presented by UIKit, which ignores tints set on individual
        // buttons and colors them with the app's accent instead. Presenting from
        // a clear background view lets the alert inherit a neutral tint — so
        // Cancel reads as plain text — without recoloring the composer itself.
        // (Discard stays red: destructive buttons ignore the tint.)
        .background {
            Color.clear
                .tint(.primary)
                .alert("Discard this comment?", isPresented: $isConfirmingDiscard) {
                    Button("Discard", role: .destructive) { discard() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your comment will be lost.")
                }
        }
    }

    // MARK: - Transitions

    /// Moves to `newState`, bringing the keyboard and the draft along with it.
    ///
    /// The state is set before focus so the `isFocused` observer above sees the
    /// destination state rather than the one being left behind.
    private func move(to newState: CommentComposerState) {
        guard newState != state else { return }
        // Cancelling throws the draft away, so confirm first when there's
        // something to lose. Both routes to `.cancelled` — the cancel button and
        // a swipe down from `.collapsed` — pass through here.
        if newState == .cancelled, !trimmedDraft.isEmpty {
            isConfirmingDiscard = true
            return
        }
        if newState == .cancelled {
            draft = ""
            replyTarget = nil
        }
        withAnimation(transition) { state = newState }

        if !newState.wantsKeyboard {
            isFocused = false
        } else if !isFocused {
            // Let the field mount before focusing, so opening the composer
            // straight from the button reliably raises the keyboard.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isFocused = true
            }
        }
    }

    /// Throws the draft away and returns to the compose button. Clearing the
    /// text first lets the transition past `move(to:)`'s confirmation guard.
    private func discard() {
        draft = ""
        move(to: .cancelled)
    }

    // MARK: - Pieces

    /// The compact button shown while cancelled; tapping it starts a comment.
    private var composeButton: some View {
        Button {
            move(to: .normal)
        } label: {
            Image(systemName: "bubble.and.pencil")
                .font(.title2)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("composer", in: namespace)
        .accessibilityLabel("Add a comment")
    }

    /// The text box: a grabber for resizing, the reply header, the field
    /// itself, and send.
    private var editor: some View {
        VStack(spacing: 8) {
            grabber
            if let replyTarget {
                replyHeader(author: replyTarget.author)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(replyTarget == nil ? "Add a comment…" : "Add a reply…", text: $draft, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(state.lineLimit)
                Button {
                    onSubmit(trimmedDraft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(trimmedDraft.isEmpty)
                .accessibilityLabel("Post comment")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .glassEffectID("composer", in: namespace)
    }

    /// Names the comment being answered so the draft's destination stays
    /// visible while writing. Sits inside the glass, between the grabber and
    /// the field, and reads as secondary to the draft itself.
    private func replyHeader(author: String) -> some View {
        Text("Replying to \(author)…")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    /// A separate glass circle that abandons the draft outright, mirroring the
    /// App Store search field's trailing "X".
    private var cancelButton: some View {
        Button {
            move(to: .cancelled)
        } label: {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                // Smaller than the compose button so it reads as secondary to
                // the text box, but still the 44pt minimum tap target.
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("cancel", in: namespace)
        .accessibilityLabel("Discard comment")
    }

    /// The grab handle above the text box. Each swipe steps one state: up
    /// towards `expanded`, down towards `cancelled`.
    private var grabber: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            // A tall, full-width hit area so the thin pill is easy to grab.
            .frame(maxWidth: .infinity, minHeight: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        // Fold in the fling so a quick flick commits too.
                        let travel = value.translation.height
                            + value.predictedEndTranslation.height / 4
                        withAnimation(transition) { dragOffset = 0 }
                        if travel < -dragThreshold {
                            move(to: state.raised)
                        } else if travel > dragThreshold {
                            move(to: state.lowered)
                        }
                    }
            )
            .accessibilityLabel("Composer size")
            .accessibilityHint("Swipe up to expand, swipe down to collapse")
    }
}

#Preview {
    @Previewable @State var replyTarget: Comment?
    ZStack(alignment: .bottomTrailing) {
        Color(.systemBackground)
        CommentComposer(replyTarget: $replyTarget) { _ in }
    }
}
