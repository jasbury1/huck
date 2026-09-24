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

    /// Whether any field is set, regardless of whether it applies to the tab
    /// being searched. What's actually narrowing *these* results is
    /// `activeFilters(for:)`.
    var isActive: Bool {
        !trimmedAuthor.isEmpty || minimumComments != nil || dateRange != .allTime
    }

    /// The active filters, in the order they appear in the sheet, as the
    /// individually-removable tokens shown under the search tabs.
    func activeFilters(for tab: SearchTab) -> [ActiveFilter] {
        // A username lookup takes no refinements, so nothing set here is
        // narrowing it — report none rather than tokens that do nothing.
        guard tab.supportsFilters else { return [] }

        var active: [ActiveFilter] = []
        if !trimmedAuthor.isEmpty {
            // Prefixed, since a bare username alongside "Last month" wouldn't
            // read as an author.
            active.append(ActiveFilter(kind: .author, label: "by \(trimmedAuthor)"))
        }
        if tab.supportsCommentCountFilter, let minimumComments {
            active.append(ActiveFilter(kind: .minimumComments, label: "\(minimumComments)+ comments"))
        }
        if let title = dateRange.summaryTitle {
            active.append(ActiveFilter(kind: .dateRange, label: title))
        }
        return active
    }

    /// Returns a single filter to its unset default, leaving the others alone —
    /// what the x on a filter token does.
    mutating func clear(_ kind: ActiveFilter.Kind) {
        switch kind {
        case .author: author = ""
        case .minimumComments: minimumComments = nil
        case .dateRange: dateRange = .allTime
        }
    }

    /// One filter as presented in the summary strip: what it says, and which
    /// field its x resets.
    struct ActiveFilter: Identifiable, Equatable {
        enum Kind: Hashable {
            case author
            case minimumComments
            case dateRange
        }

        let kind: Kind
        let label: String

        var id: Kind { kind }
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
