//
//  FormattingToolbar.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

extension View {
    /// Adds Hacker News's formatting controls — code and italics — to the
    /// keyboard's floating bar, as in Notes, acting on `text` at `selection`.
    ///
    /// Shared by everywhere HN-formatted text is written, so the controls look
    /// and behave the same in a comment as in a post. `isEnabled` scopes the
    /// bar to one field when a form has several.
    func formattingKeyboardToolbar(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        isEnabled: Bool = true
    ) -> some View {
        toolbar {
            if isEnabled {
                ToolbarItemGroup(placement: .keyboard) {
                    // Neutral icons, as in Notes, rather than the app's orange
                    // tint.
                    Group {
                        FormatButton(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", format: .code, text: text, selection: selection)
                        FormatButton(title: "Italic", systemImage: "italic", format: .italic, text: text, selection: selection)
                    }
                    .tint(.primary)
                }
            }
        }
    }
}

/// One formatting button in the keyboard bar. Formats (or unformats) the
/// highlighted text, or with just a cursor, inserts the markup to type into.
private struct FormatButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let format: CommentFormat
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
            // Spelled out beside the symbol, since the markup these insert
            // isn't self-explanatory. A plain HStack rather than a `Label`:
            // toolbars reduce a `Label` to its icon, ignoring `labelStyle`.
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
        }
    }

    /// The text's selection or cursor. Before the field reports one, the
    /// cursor is taken to be at the end of the text.
    ///
    /// The field's selection can lag the text it indexes — an empty draft has
    /// been seen reporting a range past its end — and slicing with those
    /// indices traps, so anything out of bounds falls back to the end.
    private var selectedRange: Range<String.Index> {
        let end = text.endIndex..<text.endIndex
        guard case .selection(let range) = selection?.indices,
              range.lowerBound >= text.startIndex,
              range.upperBound <= text.endIndex
        else { return end }
        return range
    }
}
