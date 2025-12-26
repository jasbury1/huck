//
//  StoryThumbnail.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

// TODO: Not yet in use. Revisit

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers


struct StoryThumbnailView: View {
    @State private var thumbnailStatus: ThumbnailType = .loading
    @State private var metadata: LPLinkMetadata? = nil
    @State private var isValidUrl = true
    
    var storyData: StoryData
    
    var body: some View {
        VStack() {
            ZStack() {
                switch thumbnailStatus {
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
            Text("Title: \(storyData.title)")
        }
        .task(id: storyData) {
            await fetchThumbnail()
        }
        .clipped()
        .frame(width: 70, height: 70)
        .cornerRadius(15)
    }
    
    private func fetchThumbnail() async {
        if storyData.storyType != .link {
            thumbnailStatus = .text
            return
        }
        let url = storyData.url
        guard let url else {
            isValidUrl = false
            return
        }
        
        do {
            metadata = try await LPMetadataProvider().startFetchingMetadata(for: url)
            await loadThumbnailImage(from: metadata?.imageProvider)
        }
        catch {
            print("Error fetching URL metadata: \(error.localizedDescription)")
            isValidUrl = false
        }
    }
    
    private func loadThumbnailImage(from imageProvider: NSItemProvider?) async {
        let imageType = UTType.image.identifier
        do {
            guard let imageProvider, imageProvider.hasItemConformingToTypeIdentifier(imageType) else {
                thumbnailStatus = .failed
                return
            }
            
            let item = try await imageProvider.loadItem(forTypeIdentifier: imageType)
            if item is UIImage, let image = item as? UIImage {
                thumbnailStatus = .image(Image(uiImage: image))
            }
            else if item is URL {
                guard let url = item as? URL,
                      let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data)
                else {
                    thumbnailStatus = .failed
                    return
                }
                thumbnailStatus = .image(Image(uiImage: image))
            }
            else if item is Data {
                guard let data = item as? Data, let image = UIImage(data: data) else {
                    thumbnailStatus = .failed
                    return
                }
                thumbnailStatus = .image(Image(uiImage: image))
            }
        }
        catch {
            print("Error loading Image: \(error.localizedDescription)")
            thumbnailStatus = .failed
        }
    }
}

