//
//  StoryThumbnail.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

/// Renders a story's thumbnail (or its placeholder for text / failed / loading
/// states) at a fixed square size. The image itself is resolved elsewhere via
/// `StoryModel.thumbnailStatus`; this view only draws the current status.
struct StoryThumbnailView: View {
    let status: ThumbnailType
    var size: CGFloat = 70

    var body: some View {
        ZStack {
            switch status {
                //case .loading:
                //ProgressView()
            case .image(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .text:
                Color(.systemGray6)
                Image(systemName: "text.alignleft")
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .foregroundStyle(Color(.systemFill))
            case .failed, .loading:
                Color(.quaternaryLabel)
                Image(systemName: "safari")
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .foregroundStyle(Color(.systemFill))
            }
        }
        .clipped()
        .frame(width: size, height: size)
        .cornerRadius(15)
    }
}
