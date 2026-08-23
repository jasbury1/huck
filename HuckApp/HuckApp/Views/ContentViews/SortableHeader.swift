//
//  SortableHeader.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

struct SortableHeader: View {
    private var title: String
    
    init (title: String) {
        self.title = title
    }
    
    var body: some View {
        HStack {
            Text(self.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Button("Hot") {}
                Button("Newest") {}
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button {
                // TODO: More options
            } label: {
                Image(systemName: "ellipsis")
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Opaque background so scrolled comments don't show through when pinned.
        .background(Color(UIColor.systemBackground))
    }
}
