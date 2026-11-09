//
//  FormattingToolbar.swift
//  Huck
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// Hacker News's formatting controls — code, italics, and quotes — acting on
/// `text` at `selection`.
///
/// Shared by everywhere HN-formatted text is written, so the controls look
/// and behave the same in a comment as in a post. Drawn by the app rather than
/// placed in the keyboard's toolbar: the system doesn't reliably make room for
/// that bar above a floating composer, and it sits flush against the keys.
/// Each button is spelled out beside its symbol, since the markup isn't
/// self-explanatory, falling back to symbols alone where that won't fit.
struct FormattingButtons: View {
    @Binding var text: String
    @Binding var selection: TextSelection?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons(showsTitles: true)
            buttons(showsTitles: false)
        }
        // Neutral icons, as in Notes, rather than the app's orange tint.
        .tint(.primary)
    }

    private func buttons(showsTitles: Bool) -> some View {
        HStack(spacing: 20) {
            FormatButton(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", format: .code, showsTitle: showsTitles, text: $text, selection: $selection)
            FormatButton(title: "Italic", systemImage: "italic", format: .italic, showsTitle: showsTitles, text: $text, selection: $selection)
            FormatButton(title: "Quote", systemImage: "text.quote", format: .quote, showsTitle: showsTitles, text: $text, selection: $selection)
        }
    }
}

extension View {
    /// Floats `FormattingButtons` in a Liquid Glass bar along the bottom of
    /// this view while `isPresented` — above the keyboard, with a gap, as in
    /// Notes. For a form, whose fields don't carry controls of their own.
    func formattingBar(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        isPresented: Bool
    ) -> some View {
        safeAreaInset(edge: .bottom) {
            if isPresented {
                FormattingButtons(text: text, selection: selection)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
    }
}

/// One formatting button. Formats (or unformats) the highlighted text, or
/// with just a cursor, inserts the markup to type into.
private struct FormatButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let format: CommentFormat
    let showsTitle: Bool
    @Binding var text: String
    @Binding var selection: TextSelection?

    var body: some View {
        Button {
            let result = format.apply(to: text, range: selectedRange)
            text = result.text
            // Select the formatted passage, so the change is visible and can be
            // toggled straight back — or place the cursor inside new markup.
            selection = result.range.isEmpty
                ? TextSelection(insertionPoint: result.range.lowerBound)
                : TextSelection(range: result.range)
        } label: {
            // Icon-only keeps the title as the button's accessibility label.
            if showsTitle {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
    }

    /// The text's selection or cursor. Before the field reports one, the
    /// cursor is taken to be at the end of the text.
    ///
    /// The field's selection can lag the text it indexes — an empty draft has
    /// been seen reporting a range past its end — and slicing with those
    /// indices traps, so anything out of bounds falls back to the end.
    private var selectedRange: Range<String.Index> {
        let end = text.endIndex..<text.endIndex
        guard case let .selection(range) = selection?.indices,
              range.lowerBound >= text.startIndex,
              range.upperBound <= text.endIndex
        else { return end }
        return range
    }
}
