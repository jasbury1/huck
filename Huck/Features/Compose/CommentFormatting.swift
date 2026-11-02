//
//  CommentFormatting.swift
//  Huck
//
//  Created by James Asbury on 9/28/26.
//

import Foundation

/// The formatting Hacker News supports in comments, applied as the plain-text
/// markup HN expects (see https://news.ycombinator.com/formatdoc):
///
/// - Italics: text surrounded by asterisks.
/// - Code: lines indented by two or more spaces, after a blank line.
/// - Quotes: not HN markup but HN convention — a paragraph starting with `>`,
///   which is also how `FormattedText` recognizes one.
///
/// Each format toggles: applied to text that already carries it, it removes it.
enum CommentFormat {
    case italic
    case code
    case quote

    /// Applies (or removes) this format at `range` of `text`. An empty range is
    /// a cursor position, where the format's markup is inserted ready to type
    /// into. Returns the new text and the range to select afterwards — the
    /// formatted passage, or an empty range for where the cursor belongs.
    func apply(to text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        switch self {
        case .italic: Self.toggleItalic(text, range: range)
        case .code: Self.toggleCode(text, range: range)
        case .quote: Self.toggleQuote(text, range: range)
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

    // MARK: - Quote

    /// What starts a quoted paragraph.
    private static let quoteMarker = "> "

    /// Quotes the paragraphs the selection touches, or unquotes them if every
    /// one is already quoted. Like a block quote in Notes, it acts on whole
    /// paragraphs — with just a cursor, the paragraph the cursor is in — since
    /// HN reads a quote as a paragraph that starts with `>`. On a blank line,
    /// starts a new quote at the cursor.
    private static func toggleQuote(_ text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        let region = paragraphRange(in: text, around: range)
        let lines = text[region].split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.contains(where: { !isBlank($0) }) else { return startQuote(in: text, at: range.lowerBound) }

        // Only a paragraph's first line takes the marker: HN runs the lines of
        // a paragraph together, so the marker quotes the whole paragraph.
        let startsParagraph = lines.indices.map { index in
            !isBlank(lines[index]) && (index == lines.startIndex || isBlank(lines[index - 1]))
        }
        let isUnquoting = lines.indices.filter { startsParagraph[$0] }.allSatisfy { isQuoted(lines[$0]) }
        let toggled = lines.indices.map { index -> String in
            let line = lines[index]
            guard startsParagraph[index] else { return String(line) }
            if isUnquoting { return unquoted(line) }
            return isQuoted(line) ? String(line) : quoteMarker + line
        }
        let result = replace(region, in: text, with: toggled.joined(separator: "\n"))
        guard range.isEmpty else { return result }

        // With just a cursor, keep it on the character it was on: the one
        // paragraph's first line gained or lost a marker ahead of it.
        let firstLine = lines[lines.startIndex]
        let cursor = text.distance(from: region.lowerBound, to: range.lowerBound)
        let markerStart = firstLine.prefix(while: \.isWhitespace).count
        let removedLength = firstLine.count - toggled[0].count
        let newCursor = isUnquoting
            ? (cursor > markerStart ? max(markerStart, cursor - removedLength) : cursor)
            : cursor + quoteMarker.count
        let index = result.text.index(result.range.lowerBound, offsetBy: newCursor)
        return (result.text, index..<index)
    }

    /// Starts a fresh quote on the blank line at `cursor`, with blank lines
    /// added around it as needed to keep it a paragraph of its own.
    private static func startQuote(in text: String, at cursor: String.Index) -> (text: String, range: Range<String.Index>) {
        // At the line's start, ahead of any spaces on it, which would
        // otherwise come before the marker and make the line read as code.
        let lineStart = startOfLine(in: text, at: cursor)
        var leading = ""
        if lineStart > text.startIndex {
            let previousEnd = text.index(before: lineStart)
            let previousLine = text[startOfLine(in: text, at: previousEnd)..<previousEnd]
            if !isBlank(previousLine) { leading = "\n" }
        }
        var trailing = ""
        if let lineEnd = text[cursor...].firstIndex(of: "\n") {
            let nextStart = text.index(after: lineEnd)
            let nextLine = text[nextStart..<(text[nextStart...].firstIndex(of: "\n") ?? text.endIndex)]
            if !isBlank(nextLine) { trailing = "\n" }
        }
        let result = replace(lineStart..<lineStart, in: text, with: quoteMarker, padding: (leading, trailing))
        return (result.text, result.range.upperBound..<result.range.upperBound)
    }

    /// The whole paragraphs `range` touches: from the blank line (or start of
    /// the text) before it to the blank line (or end) after.
    private static func paragraphRange(in text: String, around range: Range<String.Index>) -> Range<String.Index> {
        var start = startOfLine(in: text, at: range.lowerBound)
        while start > text.startIndex, !isBlank(text[start..<(text[start...].firstIndex(of: "\n") ?? text.endIndex)]) {
            let previousEnd = text.index(before: start)
            let previousStart = startOfLine(in: text, at: previousEnd)
            guard !isBlank(text[previousStart..<previousEnd]) else { break }
            start = previousStart
        }

        // A selection ending just past a newline shouldn't pull in the next line.
        let effectiveEnd = !range.isEmpty && text[text.index(before: range.upperBound)] == "\n"
            ? text.index(before: range.upperBound)
            : range.upperBound
        var end = text[effectiveEnd...].firstIndex(of: "\n") ?? text.endIndex
        while end < text.endIndex, !isBlank(text[startOfLine(in: text, at: end)..<end]) {
            let nextStart = text.index(after: end)
            let nextEnd = text[nextStart...].firstIndex(of: "\n") ?? text.endIndex
            guard !isBlank(text[nextStart..<nextEnd]) else { break }
            end = nextEnd
        }
        return start..<end
    }

    /// Whether the line starts with a quote marker, after any indentation.
    private static func isQuoted(_ line: Substring) -> Bool {
        line.drop(while: \.isWhitespace).hasPrefix(">")
    }

    /// The line with one level of quote marker, and the space after it, taken
    /// off. A nested quote (`>>`) keeps its inner level.
    private static func unquoted(_ line: Substring) -> String {
        let indent = line.prefix(while: \.isWhitespace)
        var rest = line.dropFirst(indent.count)
        guard rest.hasPrefix(">") else { return String(line) }
        rest = rest.dropFirst()
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return String(indent + rest)
    }

    private static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
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
