//
//  CommentFormatting.swift
//  HuckApp
//
//  Created by James Asbury on 9/28/26.
//

import Foundation

/// The formatting Hacker News supports in comments, applied as the plain-text
/// markup HN expects (see https://news.ycombinator.com/formatdoc):
///
/// - Italics: text surrounded by asterisks.
/// - Code: lines indented by two or more spaces, after a blank line.
///
/// Each format toggles: applied to text that already carries it, it removes it.
enum CommentFormat {
    case italic
    case code

    /// Applies (or removes) this format at `range` of `text`. An empty range is
    /// a cursor position, where the format's markup is inserted ready to type
    /// into. Returns the new text and the range to select afterwards — the
    /// formatted passage, or an empty range for where the cursor belongs.
    func apply(to text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        switch self {
        case .italic: Self.toggleItalic(text, range: range)
        case .code: Self.toggleCode(text, range: range)
        }
    }

    // MARK: - Italic

    /// Italicizes the selection, or un-italicizes it if it's already italic —
    /// whether the asterisks were selected along with the text or sit just
    /// outside it. With no selection, inserts a pair of asterisks with the
    /// cursor between them.
    private static func toggleItalic(_ text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        guard !range.isEmpty else {
            let result = replace(range, in: text, with: "**")
            let middle = result.text.index(after: result.range.lowerBound)
            return (result.text, middle..<middle)
        }

        let lines = text[range].split(separator: "\n", omittingEmptySubsequences: false)
        let contentLines = lines.filter { !$0.allSatisfy(\.isWhitespace) }

        // The selection includes the asterisks: strip each line's pair.
        if !contentLines.isEmpty, contentLines.allSatisfy(isWrappedInAsterisks) {
            let unwrapped = lines
                .map { line -> String in
                    guard let bounds = contentBounds(of: line), isWrappedInAsterisks(line) else { return String(line) }
                    let inner = line[line.index(after: bounds.lowerBound)..<bounds.upperBound]
                    return "\(line[..<bounds.lowerBound])\(inner)\(line[line.index(after: bounds.upperBound)...])"
                }
                .joined(separator: "\n")
            return replace(range, in: text, with: unwrapped)
        }

        // The asterisks sit just outside the selection: remove them.
        if range.lowerBound > text.startIndex, range.upperBound < text.endIndex {
            let before = text.index(before: range.lowerBound)
            if text[before] == "*", text[range.upperBound] == "*" {
                return replace(before..<text.index(after: range.upperBound), in: text, with: String(text[range]))
            }
        }

        // Wrap each line on its own: HN doesn't carry italics across lines.
        // Each pair hugs the line's text rather than its surrounding
        // whitespace, since HN won't italicize `* like this *`.
        let wrapped = lines
            .map { line -> String in
                guard let bounds = contentBounds(of: line) else { return String(line) }
                return "\(line[..<bounds.lowerBound])*\(line[bounds.lowerBound...bounds.upperBound])*\(line[line.index(after: bounds.upperBound)...])"
            }
            .joined(separator: "\n")
        return replace(range, in: text, with: wrapped)
    }

    /// Whether the line's text, ignoring surrounding whitespace, starts and
    /// ends with an asterisk.
    private static func isWrappedInAsterisks(_ line: Substring) -> Bool {
        guard let bounds = contentBounds(of: line), bounds.lowerBound < bounds.upperBound else { return false }
        return line[bounds.lowerBound] == "*" && line[bounds.upperBound] == "*"
    }

    /// The first and last non-whitespace characters of `line`, or `nil` for a
    /// blank line.
    private static func contentBounds(of line: Substring) -> ClosedRange<String.Index>? {
        guard let first = line.firstIndex(where: { !$0.isWhitespace }),
              let last = line.lastIndex(where: { !$0.isWhitespace })
        else { return nil }
        return first...last
    }

    // MARK: - Code

    /// Two spaces: the indent that makes a line code.
    private static let codeIndent = "  "

    /// Turns the selected lines into a code block, or back into prose if every
    /// one of them is already indented as code. With no selection, starts a
    /// code line at the cursor.
    private static func toggleCode(_ text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        guard !range.isEmpty else { return startCodeLine(in: text, at: range.lowerBound) }

        let lineStart = startOfLine(in: text, at: range.lowerBound)
        // A selection ending just past a newline shouldn't pull in the next line.
        let effectiveEnd = text[text.index(before: range.upperBound)] == "\n"
            ? text.index(before: range.upperBound)
            : range.upperBound
        let lineEnd = text[effectiveEnd...].firstIndex(of: "\n") ?? text.endIndex
        let lines = text[lineStart..<lineEnd].split(separator: "\n", omittingEmptySubsequences: false)
        let contentLines = lines.filter { !$0.allSatisfy(\.isWhitespace) }

        if !contentLines.isEmpty, contentLines.allSatisfy({ $0.hasPrefix(codeIndent) }) {
            let outdented = lines
                .map { $0.hasPrefix(codeIndent) ? String($0.dropFirst(codeIndent.count)) : String($0) }
                .joined(separator: "\n")
            return replace(lineStart..<lineEnd, in: text, with: outdented)
        }

        let block = lines.map { codeIndent + $0 }.joined(separator: "\n")
        // HN only treats indented lines as code after a blank line, and a blank
        // line after keeps the text that follows from reading as part of it.
        // `lineStart` is always the start of the text or just past a newline,
        // and `lineEnd` the end of the text or a newline.
        let before = text[..<lineStart]
        let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : "\n"
        let after = text[lineEnd...]
        let trailing = after.isEmpty || after.hasPrefix("\n\n") ? "" : "\n"
        return replace(lineStart..<lineEnd, in: text, with: block, padding: (leading, trailing))
    }

    /// Inserts a fresh, indented code line at `cursor`, preceded by whatever
    /// newlines it takes to put a blank line between it and any prose above —
    /// but none inside a code block, which a blank line would split in two.
    private static func startCodeLine(in text: String, at cursor: String.Index) -> (text: String, range: Range<String.Index>) {
        let lineStart = startOfLine(in: text, at: cursor)
        let newlines: String
        if lineStart < cursor {
            // Mid-line: break onto a new line, adding a blank one after prose.
            newlines = text[lineStart...].hasPrefix(codeIndent) ? "\n" : "\n\n"
        } else if lineStart == text.startIndex {
            newlines = ""
        } else {
            // At the start of a line: the line above decides.
            let previousLine = text[startOfLine(in: text, at: text.index(before: lineStart))..<text.index(before: lineStart)]
            let isBlankOrCode = previousLine.allSatisfy(\.isWhitespace) || previousLine.hasPrefix(codeIndent)
            newlines = isBlankOrCode ? "" : "\n"
        }
        let result = replace(cursor..<cursor, in: text, with: newlines + codeIndent)
        return (result.text, result.range.upperBound..<result.range.upperBound)
    }

    /// The start of the line containing `index`.
    private static func startOfLine(in text: String, at index: String.Index) -> String.Index {
        text[..<index].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
    }

    // MARK: - Editing

    /// Replaces `range` with `replacement`, returning the result along with
    /// the range `replacement` occupies in it. `padding` is inserted around the
    /// replacement but left out of the returned range.
    private static func replace(
        _ range: Range<String.Index>,
        in text: String,
        with replacement: String,
        padding: (leading: String, trailing: String) = ("", "")
    ) -> (text: String, range: Range<String.Index>) {
        let prefix = String(text[..<range.lowerBound]) + padding.leading
        let result = prefix + replacement + padding.trailing + String(text[range.upperBound...])
        let start = result.index(result.startIndex, offsetBy: prefix.count)
        let end = result.index(start, offsetBy: replacement.count)
        return (result, start..<end)
    }
}
