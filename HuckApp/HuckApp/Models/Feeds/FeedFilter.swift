//
//  FeedFilter.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// A rule that keeps stories out of a feed.
///
/// Not to be confused with `FeedKind`, which picks *which* feed to show
/// (Top, Best, New…); these narrow down whichever feed that is. Adding a rule
/// is a case here, its wording, and its test in `includes(_:in:)` — plus a
/// field on `FeedFilterContext` if it judges stories against something the
/// story doesn't carry itself.
///
/// Most rules are the reader's to switch on and off from a feed's menu. Some
/// are always applied instead, being the effect of something the reader did
/// elsewhere — see `isToggleable`.
///
/// Raw values are what's persisted, so they're spelled out: renaming a case
/// mustn't silently switch off a filter someone had turned on.
enum FeedFilter: String, CaseIterable, Identifiable {
    /// Stories the reader has already opened.
    case hideRead = "hideRead"
    /// Stories the reader has hidden, one at a time, with a swipe.
    case hidden = "hidden"

    var id: Self { self }

    /// Whether the reader switches it on and off from a feed's menu. The rest
    /// always apply, and appear nowhere: hiding a story is the switch.
    var isToggleable: Bool {
        switch self {
        case .hideRead: true
        case .hidden: false
        }
    }

    /// The filters a feed's menu offers.
    static var toggleable: [FeedFilter] { allCases.filter(\.isToggleable) }

    /// The filters applied whatever the reader has switched on.
    static var alwaysApplied: Set<FeedFilter> { Set(allCases.filter { !$0.isToggleable }) }

    /// The menu item that toggles it.
    var title: LocalizedStringKey {
        switch self {
        case .hideRead: "Hide Read"
        case .hidden: "Hidden Stories"
        }
    }

    var systemImage: String {
        switch self {
        case .hideRead: "eye.slash"
        case .hidden: "eye.slash"
        }
    }

    /// Says what's being left out while it's on, under the feed's title.
    var activeDescription: LocalizedStringKey {
        switch self {
        case .hideRead: "Read stories hidden"
        case .hidden: "Hidden stories left out"
        }
    }

    /// Whether `story` belongs in the feed under this rule.
    func includes(_ story: StoryModel, in context: FeedFilterContext) -> Bool {
        switch self {
        case .hideRead: !context.readIDs.contains(story.id)
        case .hidden: !context.hiddenIDs.contains(story.id)
        }
    }
}

/// What filters judge stories against, beyond the stories themselves.
///
/// A snapshot rather than a live view, taken when a feed loads, refreshes, or
/// has its filters changed. Read live, the story just opened would vanish
/// from the list the moment the reader came back to it; as a snapshot, it
/// stays — greyed, as read stories are — until the next refresh.
///
/// Hiding is the exception, being something the reader does *to the feed*:
/// a hidden story should go at once, so `hiddenIDs` is updated on its own as
/// stories are hidden, leaving the rest of the snapshot as it was.
struct FeedFilterContext {
    /// Stories the reader has opened.
    var readIDs: Set<Int> = []
    /// Stories the reader has hidden.
    var hiddenIDs: Set<Int> = []
}

extension FeedFilterContext {
    /// The current state of everything the filters can judge against.
    @MainActor
    init(recentlyViewed: RecentlyViewedStore, interactions: InteractionStore) {
        readIDs = Set(recentlyViewed.viewedIDs)
        hiddenIDs = interactions.hiddenIDs
    }
}

/// The filters a reader has turned on, along with those always applied.
///
/// `RawRepresentable` as a string so it can live in `@AppStorage` directly,
/// one setting for every feed: someone who hides read stories in Top wants
/// them hidden in Best too. Only the reader's own choices are stored.
struct FeedFilters: Equatable, RawRepresentable {
    /// The toggleable filters the reader has switched on.
    private(set) var active: Set<FeedFilter>

    init(_ active: Set<FeedFilter> = []) {
        self.active = active.filter(\.isToggleable)
    }

    /// Unknown names — a filter since removed — are skipped rather than
    /// failing the whole set.
    init(rawValue: String) {
        self.init(Set(rawValue.split(separator: ",").compactMap { FeedFilter(rawValue: String($0)) }))
    }

    var rawValue: String {
        active.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Whether the reader has switched none on. The always-applied filters
    /// still apply.
    var isEmpty: Bool { active.isEmpty }

    func contains(_ filter: FeedFilter) -> Bool {
        active.contains(filter)
    }

    mutating func set(_ filter: FeedFilter, isOn: Bool) {
        guard filter.isToggleable else { return }
        if isOn {
            active.insert(filter)
        } else {
            active.remove(filter)
        }
    }

    /// Whether `story` passes every filter that applies: those switched on,
    /// and those always applied.
    func includes(_ story: StoryModel, in context: FeedFilterContext) -> Bool {
        active.union(FeedFilter.alwaysApplied).allSatisfy { $0.includes(story, in: context) }
    }

    /// What the reader has chosen to leave out, for under the feed's title:
    /// the filter's own description when one is on, a count when several
    /// are, `nil` when none. Always-applied filters go unmentioned.
    var activeDescription: LocalizedStringKey? {
        switch active.count {
        case 0: nil
        case 1: active.first?.activeDescription
        default: "\(active.count) filters on"
        }
    }
}
