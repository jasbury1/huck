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

    /// The story being commented on, named in the header of a new top-level
    /// comment the way a reply names its author.
    let storyTitle: String

    /// Posts the trimmed comment when the user taps send. Throwing leaves the
    /// draft in place and surfaces the error, so a refused or dropped comment is
    /// never silently lost; returning normally means it's published.
    let onSubmit: (String) async throws -> Void

    /// Composing is only useful signed in, so the compose button routes through
    /// the app's shared login gate rather than letting someone write a comment
    /// they can't post.
    @Environment(\.requireLogin) private var requireLogin

    @State private var state: CommentComposerState = .cancelled
    @State private var draft = ""
    /// The field's selection, which the formatting buttons act on.
    @State private var selection: TextSelection?
    /// True while a post is in flight; holds the send button closed so one tap
    /// can't become two comments.
    @State private var isPosting = false
    /// Set when a post fails, presenting the error over the still-intact draft.
    @State private var postError: (any Error)?
    /// Live vertical drag on the grabber, so the composer follows the finger
    /// before the gesture commits to a state change.
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isFocused: Bool
    /// Presents the "discard this comment?" confirmation.
    @State private var isConfirmingDiscard = false
    /// Lets the button and the text box morph into one another.
    @Namespace private var namespace

    /// The resting compose button's diameter.
    private static let buttonDiameter: CGFloat = 56
    /// How far the whole control floats above the bottom edge.
    private static let bottomInset: CGFloat = 8

    /// How much room the composer takes up at rest.
    ///
    /// A scrolling view underneath should inset its content by this, or its
    /// last row ends up stranded behind the compose button — close enough to
    /// read, but with its controls unreachable. Only the *resting* size counts:
    /// once someone is writing, the composer is meant to cover the thread.
    static var reservedHeight: CGFloat { buttonDiameter + bottomInset }

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
                // The editor stays in one slot across every size: putting it in
                // a second branch would rebuild the text field, dropping focus
                // and tripping the observer below into collapsing the box.
                // Bottom-aligned so the "X" stays level with the box's bottom
                // edge, with the expand button stacked above it.
                HStack(alignment: .bottom, spacing: 12) {
                    editor
                    // Expanding gives the text box the full width, so the glass
                    // circles step aside and the "X" moves inside the box.
                    if state != .expanded {
                        VStack(spacing: 12) {
                            expandButton
                            cancelButton
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomInset)
        .offset(y: dragOffset)
        // Kept off the background view below, so it never competes with the
        // discard confirmation for the same presentation slot.
        .alert("Couldn't Post Comment", item: $postError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
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
            // A range into the old draft would be invalid in the next one.
            selection = nil
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

    /// Posts the draft, closing the composer only once it's actually published.
    ///
    /// A failed post keeps everything — the text, the reply target, the open
    /// composer — so the writer can simply tap send again; only the error is
    /// added. Losing a written comment to a dropped request would be the worst
    /// thing this control could do.
    private func submit() {
        let text = trimmedDraft
        guard !text.isEmpty, !isPosting else { return }
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                try await onSubmit(text)
                // Clear before transitioning: an empty draft is what lets
                // `move(to:)` past its "discard this comment?" guard.
                draft = ""
                move(to: .cancelled)
            } catch {
                postError = error
            }
        }
    }

    // MARK: - Pieces

    /// The compact button shown while cancelled; tapping it starts a comment.
    private var composeButton: some View {
        Button {
            requireLogin { move(to: .normal) }
        } label: {
            Image(systemName: "bubble.and.pencil")
                .font(.title2)
                .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("composer", in: namespace)
        .accessibilityLabel("Add a comment")
    }

    /// The text box: a top row for resizing and discarding, the reply header,
    /// the field itself, and send.
    private var editor: some View {
        VStack(spacing: 8) {
            topRow
            destinationHeader
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    replyTarget == nil ? "Add a comment…" : "Add a reply…",
                    text: $draft,
                    selection: $selection,
                    axis: .vertical
                )
                .focused($isFocused)
                .lineLimit(state.lineLimit)
                Button {
                    submit()
                } label: {
                    // A fixed frame for both states, so the row doesn't shift
                    // as the spinner takes the arrow's place.
                    Group {
                        if isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(trimmedDraft.isEmpty || isPosting)
                .accessibilityLabel("Post comment")
            }
            // The larger editor is where longer, formatted comments get
            // written, so that's where the formatting controls live.
            if state == .expanded {
                formattingBar
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        // While expanded the top row carries the discard button's own 44pt tap
        // target, which is inset enough on its own.
        .padding(.top, state == .expanded ? 0 : 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .glassEffectID("composer", in: namespace)
    }

    /// The highlighted range of the draft, or `nil` when nothing is highlighted
    /// (just a cursor, or a multi-range selection, which the field doesn't
    /// produce on iOS).
    private var selectedRange: Range<String.Index>? {
        guard case .selection(let range) = selection?.indices, !range.isEmpty else { return nil }
        return range
    }

    /// Orange pills that apply Hacker News formatting to the highlighted text.
    private var formattingBar: some View {
        HStack(spacing: 8) {
            formatButton("Format Code", systemImage: "chevron.left.forwardslash.chevron.right", format: .code)
            formatButton("Italicize", systemImage: "italic", format: .italic)
            Spacer()
        }
    }

    /// One formatting pill. Disabled until some text is highlighted, since
    /// there's nothing to format otherwise.
    private func formatButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        format: CommentFormat
    ) -> some View {
        Button {
            guard let range = selectedRange else { return }
            let result = format.apply(to: draft, range: range)
            draft = result.text
            // Keep the freshly formatted passage highlighted, so the change is
            // visible and another format can be applied on top of it.
            selection = TextSelection(range: result.range)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.orange)
        .disabled(selectedRange == nil)
    }

    /// Names where the draft will land — the comment being answered, or the
    /// story itself for a top-level comment — so it stays visible while
    /// writing. Sits inside the glass, between the grabber and the field, and
    /// reads as secondary to the draft itself.
    private var destinationHeader: some View {
        // A branch rather than a ternary inside `Text`, so both stay
        // `LocalizedStringKey`s.
        Group {
            if let replyTarget {
                Text("Replying to \(replyTarget.author)…")
            } else {
                Text("Posting to \(storyTitle)…")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// The text box's top row. While expanded the box spans the full width, so
    /// the discard "X" rides along the top edge, balanced by a shrink button on
    /// the leading edge that keeps the grabber centred under the finger.
    private var topRow: some View {
        // One HStack for every size, so the grabber — and the drag gesture that
        // drives the whole ladder — keeps its identity as the buttons come and go.
        HStack(spacing: 0) {
            if state == .expanded {
                shrinkButton
            }
            grabber
            if state == .expanded {
                discardButton
            }
        }
    }

    /// The expanded box's way back to the everyday size — the counterpart to
    /// `expandButton`, and a tappable alternative to swiping the grabber down.
    /// Plain like `discardButton`, since it also sits on the text box's glass.
    private var shrinkButton: some View {
        Button {
            move(to: .normal)
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                // A plain button only hit-tests what it draws; without this
                // the tap target would shrink to the glyph itself.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Shrink composer")
    }

    /// The expanded box's own discard control. Same "X" as the glass circle it
    /// replaces, but plain: it already sits on the text box's glass.
    private var discardButton: some View {
        Button {
            move(to: .cancelled)
        } label: {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                // As with `shrinkButton`: keep the full 44pt target.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Discard comment")
    }

    /// A separate glass circle that abandons the draft outright, mirroring the
    /// App Store search field's trailing "X". Shown while the box is compact,
    /// beneath `expandButton`; once expanded, `discardButton` takes over inside
    /// the box.
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

    /// A glass circle above the "X" that jumps straight to the expanded editor —
    /// a tappable alternative to swiping the grabber up. Shown alongside the
    /// "X", so it steps aside too once the box is expanded.
    private var expandButton: some View {
        Button {
            move(to: .expanded)
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("expand", in: namespace)
        .accessibilityLabel("Expand composer")
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
        CommentComposer(replyTarget: $replyTarget, storyTitle: "Show HN: A Hacker News client") { _ in }
    }
}
