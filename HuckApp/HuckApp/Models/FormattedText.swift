//
//  FormattedText.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// The text of a comment or post, parsed for display: runs of prose, and the
/// code blocks and quotes between them.
///
/// Built from the markdown `normalizeHtmlText()` produces, where code blocks
/// are fenced. Code is kept apart rather than parsed as markdown because it's
/// drawn apart, in a block of its own.
///
/// Quotes are Hacker News convention rather than markup: HN has no quote
/// formatting, so people start a paragraph with `>` instead. Each such
/// paragraph, with its run of quoted neighbours, becomes one quote.
struct FormattedText {
    enum Content {
        /// Inline markdown, parsed.
        case prose(AttributedString)
        /// Code exactly as written, one line per line.
        case code(String)
        /// Quoted paragraphs, parsed, with their `>` markers taken off. The
        /// markers are put back where quotes aren't drawn as quotes — see
        /// `markedQuote(_:)`.
        case quote([AttributedString])
    }

    struct Block: Identifiable {
        /// The block's position in the text. Stable, since parsed text never
        /// changes.
        let id: Int
        let content: Content
    }

    let blocks: [Block]

    var containsCode: Bool {
        blocks.contains { if case .code = $0.content { true } else { false } }
    }

    var containsQuote: Bool {
        blocks.contains { if case .quote = $0.content { true } else { false } }
    }

    init(markdown: String) {
        var contents: [Content] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        /// The fence that opened the block being read, while inside one.
        var openFence: Substring?

        /// Ends the prose being read, split into its plain and quoted runs.
        func endProse() {
            let chunk = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            prose = []
            guard !chunk.isEmpty else { return }

            var plain: [Substring] = []
            var quoted: [Substring] = []
            func endPlain() {
                guard !plain.isEmpty else { return }
                contents.append(.prose(Self.parsed(plain.joined(separator: "\n\n"))))
                plain = []
            }
            func endQuote() {
                guard !quoted.isEmpty else { return }
                contents.append(.quote(quoted.map { Self.parsed(String(Self.unquoted($0))) }))
                quoted = []
            }
            for paragraph in chunk.split(separator: /\n[ \t]*\n/) {
                let paragraph = paragraph.trimmingPrefix(while: \.isNewline)
                guard !paragraph.allSatisfy(\.isWhitespace) else { continue }
                if Self.isQuote(paragraph) {
                    endPlain()
                    quoted.append(paragraph)
                } else {
                    endQuote()
                    plain.append(paragraph)
                }
            }
            endPlain()
            endQuote()
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if let fence = openFence {
                if line == fence {
                    contents.append(.code(code.joined(separator: "\n")))
                    code = []
                    openFence = nil
                } else {
                    code.append(line)
                }
            } else if line.count >= 3, line.allSatisfy({ $0 == "`" }) {
                endProse()
                openFence = line
            } else {
                prose.append(line)
            }
        }
        // An unclosed fence still opened a block; keep what it held as code.
        if openFence != nil {
            contents.append(.code(code.joined(separator: "\n")))
        }
        endProse()

        blocks = contents.enumerated().map { Block(id: $0.offset, content: $0.element) }
    }

    /// The whole text as one attributed string, for where it has to be a
    /// single `Text` — beside a poll option's count, say, or with code and
    /// quote formatting turned off.
    ///
    /// Code is marked as inline code, which `Text` draws monospaced, when
    /// `formatsCode` is on; otherwise it reads as ordinary text. Either way it
    /// wraps. Quotes keep their `>` markers, as written.
    func attributedString(formatsCode: Bool) -> AttributedString {
        var result = AttributedString()
        for block in blocks {
            if block.id > 0 {
                result += AttributedString("\n\n")
            }
            switch block.content {
            case let .prose(prose):
                result += prose
            case let .code(code):
                var run = AttributedString(code)
                if formatsCode {
                    run.inlinePresentationIntent = .code
                }
                result += run
            case let .quote(paragraphs):
                result += Self.markedQuote(paragraphs)
            }
        }
        return result
    }

    // MARK: - Quotes

    /// A quote as it was written: each paragraph behind its `>`, for where
    /// it's read inline rather than set apart.
    static func markedQuote(_ paragraphs: [AttributedString]) -> AttributedString {
        var result = AttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                result += AttributedString("\n\n")
            }
            result += AttributedString("> ") + paragraph
        }
        return result
    }

    /// Whether a paragraph is quoted. Prose from Hacker News still carries
    /// the marker as the entity it escapes it to; text the reader just posted
    /// carries it as typed.
    private static func isQuote(_ paragraph: Substring) -> Bool {
        let text = paragraph.drop(while: \.isWhitespace)
        return text.hasPrefix(">") || text.hasPrefix("&gt;")
    }

    /// The paragraph with its leading markers and the space after them
    /// removed. Nested markers (`>>`) are taken off too: a quote within a
    /// quote is drawn as one quote.
    private static func unquoted(_ paragraph: Substring) -> Substring {
        var text = paragraph.drop(while: \.isWhitespace)
        while true {
            if text.hasPrefix(">") {
                text = text.dropFirst()
            } else if text.hasPrefix("&gt;") {
                text = text.dropFirst(4)
            } else {
                break
            }
            text = text.drop(while: \.isWhitespace)
        }
        return text
    }

    /// Inline markdown, parsed, or the text as is if it won't parse.
    private static func parsed(_ markdown: String) -> AttributedString {
        let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return parsed ?? AttributedString(markdown)
    }

    // MARK: - Caching

    /// Parsing costs a fraction of a millisecond per comment — enough, across
    /// a screenful of rows re-rendered on every scroll or collapse, to be worth
    /// doing once per text. `NSCache` gives the memory back under pressure.
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 1_000
        return cache
    }()

    private final class Box {
        let text: FormattedText
        init(_ text: FormattedText) { self.text = text }
    }

    /// The parsed form of `markdown`, from the cache when it's been seen.
    static func cached(_ markdown: String) -> FormattedText {
        let key = markdown as NSString
        if let hit = cache.object(forKey: key) {
            return hit.text
        }
        let parsed = FormattedText(markdown: markdown)
        cache.setObject(Box(parsed), forKey: key)
        return parsed
    }
}
