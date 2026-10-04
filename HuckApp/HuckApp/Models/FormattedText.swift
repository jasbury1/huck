//
//  FormattedText.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// The text of a comment or post, parsed for display: runs of prose, and the
/// code blocks between them.
///
/// Built from the markdown `normalizeHtmlText()` produces, where code blocks
/// are fenced. Code is kept apart rather than parsed as markdown because it's
/// drawn apart, in a block of its own.
struct FormattedText {
    enum Content {
        /// Inline markdown, parsed.
        case prose(AttributedString)
        /// Code exactly as written, one line per line.
        case code(String)
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

    init(markdown: String) {
        var contents: [Content] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        /// The fence that opened the block being read, while inside one.
        var openFence: Substring?

        func endProse() {
            let chunk = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            prose = []
            guard !chunk.isEmpty else { return }
            let parsed = try? AttributedString(
                markdown: chunk,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            contents.append(.prose(parsed ?? AttributedString(chunk)))
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
    /// single `Text` — beside a poll option's count, say, or with code
    /// formatting turned off.
    ///
    /// Code is marked as inline code, which `Text` draws monospaced, when
    /// `formatsCode` is on; otherwise it reads as ordinary text. Either way it
    /// wraps.
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
            }
        }
        return result
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
