//
//  FormattedTextView.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// The body of a comment or post: its prose, and any code or quotes in blocks
/// of their own, so it's plain where they start and stop.
///
/// Takes its font from the environment, and the code takes the monospaced
/// version of it. A `lineLimit` clamps the whole body, blocks and all, to
/// about that many lines of its font. Code and quotes are each set apart only
/// while their setting is on; with nothing to set apart it's a single `Text`.
struct FormattedTextView: View {
    let text: String
    var lineLimit: Int? = nil

    @AppStorage(ReadingSettings.formatsCodeKey) private var formatsCode = true
    @AppStorage(ReadingSettings.formatsQuotesKey) private var formatsQuotes = true

    private static let blockSpacing: CGFloat = 10

    var body: some View {
        let formatted = FormattedText.cached(text)
        if (formatsCode && formatted.containsCode) || (formatsQuotes && formatted.containsQuote) {
            if let lineLimit {
                LineClampedStack(lineLimit: lineLimit, spacing: Self.blockSpacing) {
                    // Measures a line of the font, for the stack's limit.
                    Text(verbatim: "X").hidden()
                    blocks(of: formatted)
                }
                // Blocks past the limit are parked outside the bounds.
                .clipped()
            } else {
                VStack(alignment: .leading, spacing: Self.blockSpacing) {
                    blocks(of: formatted)
                }
            }
        } else {
            Text(formatted.attributedString(formatsCode: formatsCode))
                .lineLimit(lineLimit)
        }
    }

    /// Each block drawn on its own. Whichever of code and quotes has its
    /// setting off reads as ordinary text, as in the single-`Text` form.
    private func blocks(of formatted: FormattedText) -> some View {
        ForEach(formatted.blocks) { block in
            switch block.content {
            case let .prose(prose):
                Text(prose)
            case let .code(code):
                if formatsCode {
                    CodeBlock(code: code)
                } else {
                    Text(code)
                }
            case let .quote(paragraphs):
                if formatsQuotes {
                    QuoteBlock(paragraphs: paragraphs)
                } else {
                    Text(FormattedText.markedQuote(paragraphs))
                }
            }
        }
    }
}

/// Quoted text inside a rounded outline, its `>` markers dropped since the
/// outline now says what they did.
///
/// The outline says it's a quote, and an outline rather than a fill keeps it
/// from being mistaken for a code block. The text is only a shade lighter than the reply around it — enough
/// to read as someone else's words, where `.secondary` was too faint to read
/// comfortably. It isn't italicized, which would swallow any italics the
/// quote carries, and Hacker News uses those for emphasis.
private struct QuoteBlock: View {
    let paragraphs: [AttributedString]

    var body: some View {
        // One `Text` rather than one per paragraph, so a clamped body
        // truncates the quote with an ellipsis like any other text.
        Text(paragraphs.joined(separator: "\n\n"))
            .foregroundStyle(.primary.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                // `systemGray3` stays visible against the background in both
                // appearances, where `.separator` all but vanished.
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
            }
            // The outline is drawn, so VoiceOver is told what it means.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Quote: ") + Text(paragraphs.joined(separator: "\n\n")))
    }
}

private extension [AttributedString] {
    func joined(separator: String) -> AttributedString {
        var result = AttributedString()
        for (index, element) in enumerated() {
            if index > 0 { result += AttributedString(separator) }
            result += element
        }
        return result
    }
}

/// A block of code on a tinted background. Long lines wrap within it.
///
/// It doesn't scroll sideways: in a thread, the comment's swipe actions take
/// every horizontal drag, so a scrolling block could never be scrolled.
private struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(code)
            .monospaced()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
    }
}

/// A vertical stack no taller than `lineLimit` lines, for clamping text made
/// of several blocks the way `lineLimit` clamps a single `Text`.
///
/// The block that crosses the limit is offered only the height that's left,
/// which a `Text` meets by truncating with an ellipsis; the blocks after it
/// are left out. The first subview is a one-line probe that measures the
/// line height, and is never shown.
private struct LineClampedStack: Layout {
    let lineLimit: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(width: proposal.width, subviews: subviews)
        let shown = frames.compactMap { $0 }
        return CGSize(
            width: proposal.width ?? shown.map(\.maxX).max() ?? 0,
            height: shown.map(\.maxY).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            if let frame {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size)
                )
            } else {
                // Below the clipped bounds, out of sight.
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 1), proposal: .zero)
            }
        }
    }

    /// Where each subview goes, or `nil` for one that isn't shown.
    private func frames(width: CGFloat?, subviews: Subviews) -> [CGRect?] {
        guard let probe = subviews.first else { return [] }
        let lineHeight = probe.sizeThatFits(.unspecified).height
        let maxHeight = lineHeight * CGFloat(lineLimit)

        var frames: [CGRect?] = [nil]
        var y: CGFloat = 0
        var isFull = false
        for subview in subviews.dropFirst() {
            let remaining = maxHeight - y
            // Less than a line left: nothing more can usefully be shown.
            guard !isFull, remaining >= lineHeight else {
                frames.append(nil)
                continue
            }
            var size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if size.height > remaining {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: remaining))
                isFull = true
            }
            frames.append(CGRect(x: 0, y: y, width: width ?? size.width, height: size.height))
            y += size.height + spacing
        }
        return frames
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            FormattedTextView(text: sample)
            // Clamped, as on a profile or in search results.
            FormattedTextView(text: sample, lineLimit: 6)
        }
        .font(.callout)
        .padding()
    }
}

private let sample = """
    &gt; Does D have lambdas?

    &gt; Or anything *like* them?

    Lambdas in D are just *nested* functions:
    ```
    int foo(int i) {
        int add(int x) { return i + x; } // nested function
        return add(3);
    }
    ```
    And a short block:
    ```
    x = 1
    ```
    """
