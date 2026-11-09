//
//  CommentFormatTests.swift
//  HuckTests
//

@testable import Huck
import Testing

struct CommentFormatTests {
    // MARK: - Italic

    @Test func italicWrapsTheSelection() {
        let text = "hello world"
        let result = CommentFormat.italic.apply(to: text, range: text.range(of: "world"))
        #expect(result.text == "hello *world*")
    }

    @Test func italicAtACursorInsertsAPairAroundIt() {
        let result = CommentFormat.italic.apply(to: "", range: "".cursor(at: 0))
        #expect(result.text == "**")
        #expect(result.range.isEmpty)
        #expect(result.text.offset(of: result.range.lowerBound) == 1)
    }

    @Test func italicRemovesSelectedAsterisks() {
        let text = "hello *world*"
        let result = CommentFormat.italic.apply(to: text, range: text.range(of: "*world*"))
        #expect(result.text == "hello world")
    }

    @Test func italicRemovesAsterisksJustOutsideTheSelection() {
        let text = "hello *world*"
        let result = CommentFormat.italic.apply(to: text, range: text.range(of: "world"))
        #expect(result.text == "hello world")
    }

    @Test func italicWrapsEachLineSeparately() {
        let text = "one\ntwo"
        let result = CommentFormat.italic.apply(to: text, range: text.startIndex..<text.endIndex)
        #expect(result.text == "*one*\n*two*")
    }

    // MARK: - Code

    @Test func codeIndentsTheLineAfterABlankLine() {
        let text = "intro\nlet x = 1"
        let result = CommentFormat.code.apply(to: text, range: text.range(of: "let x = 1"))
        #expect(result.text == "intro\n\n  let x = 1")
    }

    @Test func codeOutdentsLinesAlreadyIndented() {
        let text = "intro\n\n  let x = 1"
        let result = CommentFormat.code.apply(to: text, range: text.range(of: "let x"))
        #expect(result.text == "intro\n\nlet x = 1")
    }

    // MARK: - Quote

    @Test func quoteMarksTheCursorsParagraph() {
        let text = "Hello world"
        let result = CommentFormat.quote.apply(to: text, range: text.cursor(at: 3))
        #expect(result.text == "> Hello world")
    }

    @Test func quoteTogglesOff() {
        let text = "> Hello world"
        let result = CommentFormat.quote.apply(to: text, range: text.cursor(at: 5))
        #expect(result.text == "Hello world")
    }
}
