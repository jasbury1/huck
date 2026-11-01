//
//  CompactCount.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import Foundation

extension FormatStyle where Self == IntegerFormatStyle<Int> {
    /// A count abbreviated to fit a tight row: 999 stays 999, 1,956 becomes
    /// "1.9K", 1,250,000 becomes "1.2M". Rounded down, so a story never looks
    /// more popular than it is. Localized, so the suffix follows the locale.
    static var compactCount: IntegerFormatStyle<Int> {
        .number
            .notation(.compactName)
            .precision(.fractionLength(0...1))
            .rounded(rule: .down)
    }
}
