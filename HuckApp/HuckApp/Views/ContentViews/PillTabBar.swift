//
//  PillTabBar.swift
//  HuckApp
//
//  Created by James Asbury on 9/23/26.
//

import SwiftUI

/// A tab that can be drawn as one of the app's category pills.
protocol PillTab: Hashable {
    /// Shown only while the tab is selected.
    var title: LocalizedStringKey { get }
    /// Always visible in the pill, selected or not.
    var systemImage: String { get }
    /// The pill's fill color when selected.
    var color: Color { get }
}

/// The app's shared tab strip, à la the Mail app's category tabs: each tab is a
/// symbol in a capsule that expands to reveal its title when selected. Used by
/// the profile, the likes/favorites screens, and search.
///
/// The strip scrolls horizontally only when the pills don't fit — with a handful
/// of tabs it still reads as a plain, static row.
struct PillTabBar<Tab: PillTab>: View {
    let tabs: [Tab]
    @Binding var selection: Tab

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(tabs, id: \.self) { tab in
                    pill(for: tab)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Animate the pills for selection changes that come from outside the
        // strip — a swipe of a pager below it, say — not just from taps.
        .animation(.snappy(duration: 0.3), value: selection)
    }

    /// A single tab pill. Unselected it shows only its symbol on a neutral fill;
    /// selected it fills with the tab's color and expands to include the title.
    private func pill(for tab: Tab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = tab }
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
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    @Previewable @State var tab: SearchTab = .stories
    VStack {
        PillTabBar(tabs: SearchTab.allCases, selection: $tab)
        Divider()
        Spacer()
    }
}
