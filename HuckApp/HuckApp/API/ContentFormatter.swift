//
//  ContentFormatter.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

extension String {
    func normalizeHtmlText() -> String {
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
}
