//
//  StoryCellView.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

enum ThumbnailType {
    case loading
    case image(Image)
    case failed
    case text
}

struct StoryCellView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    
    @State private var thumbnailStatus: ThumbnailType = .loading
    @State private var metadata: LPLinkMetadata? = nil
    @State private var isValidUrl = true
    
    @Binding var path: NavigationPath
    
    init(storyId: Int, path: Binding<NavigationPath>) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
        self._path = path
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                switch storyData.storyType {
                case .link:
                    Button(action: {
                        path.append(ItemNavigation.linkStory(id: storyId, url: storyData.url!))
                    }) {
                        Text(storyData.title)
                    }
                    .buttonStyle(.plain)
                case .text:
                    Button(action: {
                        path.append(ItemNavigation.textStory(id: storyId))
                    }) {
                        Text(storyData.title)
                    }
                    .buttonStyle(.plain)
                case .unknown:
                    Text(storyData.title)
                }
                
                Text("")
                VStack(alignment: .leading){
                    Text("\(storyData.by)")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    HStack {
                        // Button to upvote the post
                        Button(action: {
                            // TODO
                        }) {
                            HStack {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.gray)
                                Text("\(storyData.score)")
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Button to view the comments
                        Button(action: {
                            path.append(ItemNavigation.textStory(id: storyId))
                        }) {
                            HStack {
                                Image(systemName: "bubble")
                                    .foregroundColor(.gray)
                                Text("\(storyData.commentCount)")
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Timestamp
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        Text(storyData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        
                        // Share the post
                        Image(systemName: "paperplane")
                            .foregroundColor(.gray)
                        
                        // Bookmark the post
                        Image(systemName: "bookmark")
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            // The image thumbnail
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
            }
            .clipped()
            .frame(width: 70, height: 70)
            .cornerRadius(15)
        }
        .task {
            await storyData.fetchData()
            await fetchThumbnail()
        }
        
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
