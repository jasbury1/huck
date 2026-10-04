//
//  ContentFormatter.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

extension String {
    /// Converts Hacker News's HTML to the inline markdown the views render.
    ///
    /// Code blocks are converted apart from the prose around them, into fenced
    /// blocks: the prose rules would strip anything in the code that looks
    /// like a tag and read its asterisks as italics.
    func normalizeHtmlText() -> String {
        var normalized = ""
        var rest = self[...]
        while let block = rest.firstMatch(of: /<pre><code>(.*?)<\/code><\/pre>/.dotMatchesNewlines()) {
            normalized += String(rest[..<block.range.lowerBound]).normalizedProse()
            normalized += Self.codeMarkdown(fromHTML: String(block.1))
            rest = rest[block.range.upperBound...]
        }
        return normalized + String(rest).normalizedProse()
    }

    private func normalizedProse() -> String {
        var normalized = self
            .replacingOccurrences(of: "<p>" , with: "\n\n")
            .replacingOccurrences(of: "&#x27;" , with: "'")
            .replacingOccurrences(of: "&#x2F;" , with: "/")
            .replacingOccurrences(of: "&quot;" , with: "\"")
            .replacingOccurrences(of: "<i>\\s?+", with: "*", options: .regularExpression)
            .replacingOccurrences(of: "\\s?+</i>", with: "*", options: .regularExpression)
            .replacingOccurrences(of: "<b>\\s?+", with: "**", options: .regularExpression)
            .replacingOccurrences(of: "\\s?+</b>", with: "**", options: .regularExpression)
            .replacingOccurrences(of: "<strong>\\s?+", with: "**", options: .regularExpression)
            .replacingOccurrences(of: "\\s?+</strong>", with: "**", options: .regularExpression)
            //nofollow not supported in markdown
            .replacingOccurrences(of: "\" rel=\"nofollow", with: "")
        
        normalized = normalized.replacing(/<a\s+href=.(.*?).>(.*)<\/a>/.ignoresCase()) { match in
            return "[\(match.2)](\(match.1))"
        }
        // Catch-all
        return normalized.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }

    // MARK: - Code

    /// A code block — lines indented two or more spaces where they were
    /// written — as a fenced markdown code block, its text exactly as written.
    /// `FormattedText` splits these out of the prose for the views to draw.
    ///
    /// The indent the whole block shares is removed, since it only marked the
    /// lines as code and costs width on a phone; any deeper indentation is the
    /// code's own and stays.
    private static func codeMarkdown(fromHTML html: String) -> String {
        let lines = decodingEntities(in: html)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.allSatisfy(\.isWhitespace) ? "" : $0 }
        // The final newline closes the block; it isn't a blank line of code.
        let trimmed = lines.last == "" ? lines.dropLast() : lines[...]
        let sharedIndent = trimmed
            .filter { !$0.isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
            .min() ?? 0
        let code = trimmed
            .map { $0.dropFirst(sharedIndent) }
            .joined(separator: "\n")
        // Longer than any run of backticks in the code, so no line of it can
        // be mistaken for the closing fence.
        let longestRun = code.matches(of: /`+/).map(\.output.count).max() ?? 0
        let fence = String(repeating: "`", count: Swift.max(3, longestRun + 1))
        return "\n\(fence)\n\(code)\n\(fence)\n"
    }

    /// Decodes the HTML entities Hacker News escapes code with. Markdown
    /// decodes them in prose, but leaves a code span's text exactly as written.
    private static func decodingEntities(in html: String) -> String {
        html
            .replacing(/&#x([0-9a-fA-F]+);/) { match in
                UInt32(match.1, radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.0)
            }
            .replacing(/&#([0-9]+);/) { match in
                UInt32(match.1).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.0)
            }
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            // Last, so an escaped entity like `&amp;lt;` comes out as `&lt;`.
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
