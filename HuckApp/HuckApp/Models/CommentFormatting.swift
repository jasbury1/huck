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
enum CommentFormat {
    case italic
    case code

    /// Applies this format to `range` of `text`, returning the new text and the
    /// range the formatted passage now occupies, so it can stay selected.
    func apply(to text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        switch self {
        case .italic: Self.italicize(text, range: range)
        case .code: Self.formatAsCode(text, range: range)
        }
    }

    /// Wraps each selected line in asterisks. HN doesn't carry italics across
    /// lines, so a multi-line selection gets a pair per line. Each pair hugs the
    /// line's text rather than its surrounding whitespace, since HN won't
    /// italicize `* like this *`.
    private static func italicize(_ text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        let formatted = text[range]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let first = line.firstIndex(where: { !$0.isWhitespace }),
                      let last = line.lastIndex(where: { !$0.isWhitespace })
                else { return String(line) }
                return "\(line[..<first])*\(line[first...last])*\(line[line.index(after: last)...])"
            }
            .joined(separator: "\n")
        return replace(range, in: text, with: formatted)
    }

    /// Turns the selected lines into a code block: widens the selection to
    /// whole lines, indents each by two spaces, and makes sure blank lines
    /// separate the block from the text around it — HN only treats indented
    /// lines as code after a blank line.
    private static func formatAsCode(_ text: String, range: Range<String.Index>) -> (text: String, range: Range<String.Index>) {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
        // A selection ending just past a newline shouldn't pull in the next line.
        let effectiveEnd = range.upperBound > range.lowerBound && text[text.index(before: range.upperBound)] == "\n"
            ? text.index(before: range.upperBound)
            : range.upperBound
        let lineEnd = text[effectiveEnd...].firstIndex(of: "\n") ?? text.endIndex

        let block = text[lineStart..<lineEnd]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  " + $0 }
            .joined(separator: "\n")

        // `lineStart` is always the start of the text or just past a newline,
        // and `lineEnd` the end of the text or a newline.
        let before = text[..<lineStart]
        let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : "\n"
        let after = text[lineEnd...]
        let trailing = after.isEmpty || after.hasPrefix("\n\n") ? "" : "\n"
        return replace(lineStart..<lineEnd, in: text, with: block, padding: (leading, trailing))
    }

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
