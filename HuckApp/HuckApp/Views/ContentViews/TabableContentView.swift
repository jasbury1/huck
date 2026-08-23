//
//  TabableContent.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

struct TabableContentView: View {
    @State private var currentTab: ContentTab = .posts
    
    private var title: String
    
    private let cardBackgroundColor = Color(UIColor.systemBackground)
    
    private var availableTabs: [ContentTab] {
        var tabs: [ContentTab] = [.posts, .comments]
        // TODO: This is so that this view can later be purposed for the logged in user's profile
        if false {
            tabs.append(.recentlyViewed)
        }
        return tabs
    }
    
    init(title: String) {
        self.title = title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SortableHeader(title: title)
            tabBarButtons
            Divider()
        }
    }
    
    /// A single tab pill. Unselected it shows only its symbol on a neutral fill;
    /// selected it fills with the tab's color and expands to include the title.
    private func tabPill(for tab: ContentTab) -> some View {
        let selected = currentTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.3)) { currentTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                if selected {
                    Text(tab.title)
                        .fontWeight(.semibold)
                        .fixedSize()
                }
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, selected ? 14 : 11)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(tab.color) : AnyShapeStyle(Color(.secondarySystemFill)))
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    var tabBarButtons: some View {
        HStack(spacing: 10) {
            ForEach(availableTabs, id: \.self) { tab in
                tabPill(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(cardBackgroundColor)
        // Animate the pills for swipe-driven selection changes too.
        .animation(.snappy(duration: 0.3), value: currentTab)
    }
}

