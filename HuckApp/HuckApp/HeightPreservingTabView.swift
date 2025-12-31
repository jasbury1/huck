//
//  HeightPreservingTabView.swift
//  HuckApp
//
//  Created by James Asbury on 12/31/25.
//

import SwiftUI

/// A variant of `TabView` that measures the height of child views to set an appropriate `minHeight` on its frame.
/// Source: https://bdewey.com/til/2023/03/01/swiftui-and-tabview-height/
struct HeightPreservingTabView<SelectionValue: Hashable, Content: View>: View {
    var selection: Binding<SelectionValue>?
    @ViewBuilder var content: () -> Content
    
    // `minHeight` needs to start as something non-zero or we won't measure the interior content height
    @State private var minHeight: CGFloat = 1
    
    var body: some View {
        TabView(selection: selection) {
            content()
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TabViewMinHeightPreference.self,
                            value: geometry.frame(in: .local).height
                        )
                    }
                }
        }
        .frame(minHeight: minHeight)
        .onPreferenceChange(TabViewMinHeightPreference.self) { minHeight in
            self.minHeight = minHeight
        }
    }
}

private struct TabViewMinHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
