//
//  HTMLNormalizationTests.swift
//  HuckTests
//

@testable import Huck
import Testing

struct HTMLNormalizationTests {
    @Test func paragraphsBecomeBlankLines() {
        #expect("Hello<p>World".normalizeHtmlText() == "Hello\n\nWorld")
    }

    @Test func decodesCommonEntities() {
        #expect("it&#x27;s &quot;here&quot;".normalizeHtmlText() == "it's \"here\"")
    }

    @Test func italicsBecomeAsterisks() {
        #expect("an <i>important</i> point".normalizeHtmlText() == "an *important* point")
    }

    @Test func linksBecomeMarkdownLinks() {
        let html = #"see <a href="https:&#x2F;&#x2F;example.com" rel="nofollow">example</a>"#
        #expect(html.normalizeHtmlText() == "see [example](https://example.com)")
    }

    @Test func stripsUnknownTags() {
        #expect("<span>plain</span>".normalizeHtmlText() == "plain")
    }

    @Test func codeBlocksBecomeFencesWithTheirIndentRemoved() {
        let html = "<pre><code>  if a &lt; b {\n    go()\n  }\n</code></pre>"
        #expect(html.normalizeHtmlText() == "\n```\nif a < b {\n  go()\n}\n```\n")
    }

    @Test func fencesOutgrowBacktickRunsInTheCode() {
        let html = "<pre><code>  ```\n</code></pre>"
        #expect(html.normalizeHtmlText() == "\n````\n```\n````\n")
    }
}
