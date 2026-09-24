//
//  SearchFilters.swift
//  HuckApp
//
//  Created by James Asbury on 9/23/26.
//

import SwiftUI

/// The refinements layered on top of a search query, chosen in the filters sheet.
///
/// Deliberately limited to what the Algolia search endpoint can express on its
/// own — an `author_` tag, a `num_comments` bound, and a `created_at_i` bound —
/// so no filter has to be re-applied client-side over a partial page of results.
struct SearchFilters: Equatable {
    /// An HN username, unprefixed. Empty means "any author".
    var author: String = ""

    /// A lower bound on a result's comment count; `nil` means no bound. Not
    /// applicable when searching comments, which have no count of their own.
    var minimumComments: Int?

    var dateRange: SearchDateRange = .allTime

    /// The author with surrounding whitespace dropped, since it goes straight
    /// into a tag.
    var trimmedAuthor: String {
        author.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether anything is actually narrowing the search. Drives the toolbar
    /// button's filled appearance and the summary strip under the tabs.
    var isActive: Bool {
        !trimmedAuthor.isEmpty || minimumComments != nil || dateRange != .allTime
    }

    /// The active filters, in the order they're shown in the sheet, as short
    /// phrases for the summary strip.
    func summaryPhrases(for tab: SearchTab) -> [String] {
        var phrases: [String] = []
        if !trimmedAuthor.isEmpty {
            phrases.append("by \(trimmedAuthor)")
        }
        if tab.supportsCommentCountFilter, let minimumComments {
            phrases.append("\(minimumComments)+ comments")
        }
        if let title = dateRange.summaryTitle {
            phrases.append(title)
        }
        return phrases
    }
}

/// How far back a search reaches, as a `created_at_i` lower bound.
enum SearchDateRange: CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case allTime

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .day: "Last day"
        case .week: "Last week"
        case .month: "Last month"
        case .year: "Last year"
        case .allTime: "All time"
        }
    }

    /// The label for the summary strip, or `nil` for the unrestricted default —
    /// "All time" isn't worth reporting as a filter.
    var summaryTitle: String? {
        switch self {
        case .day: "Last day"
        case .week: "Last week"
        case .month: "Last month"
        case .year: "Last year"
        case .allTime: nil
        }
    }

    /// The oldest timestamp this range admits, or `nil` for no bound.
    /// Calendar-based rather than a fixed number of seconds, so "last month"
    /// means the same date a month ago regardless of month length or DST.
    func earliestDate(relativeTo now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .day: calendar.date(byAdding: .day, value: -1, to: now)
        case .week: calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .allTime: nil
        }
    }
}
