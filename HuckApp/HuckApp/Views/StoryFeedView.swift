//
//  StoryFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
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
    
    init(storyId: Int) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                switch storyData.storyType {
                case .link:
                    NavigationLink(destination: StoryWebView(url: storyData.url)) {
                        Text(storyData.title)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                case .text:
                    NavigationLink(destination: StoryTextView(storyId: storyId)) {
                        Text(storyData.title)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                case .unknown:
                    Text(storyData.title)
                }
                
                Text("")
                VStack(alignment: .leading){
                    Text("\(storyData.by)")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    HStack {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.gray)
                        Text("\(storyData.score)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "bubble")
                            .foregroundColor(.gray)
                        Text("\(storyData.commentCount)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        //Text("\(observableStory.story?.time ?? 0)")
                        Text(storyData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "paperplane")
                            .foregroundColor(.gray)
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

// TODO: Construct with an enum for the type of story
struct StoryFeedView: View {
    @State private var storyFilter: StoryFilter
    @State var observableStories = StoriesFeedData()
    
    init(filter: StoryFilter) {
        storyFilter = filter
    }
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) {item in
                StoryCellView(storyId: item)
            }
        }
        .listStyle(.plain)
        .task (id: storyFilter) {
            await self.observableStories.fetchStoryIds(filter: storyFilter)
        }
        .toolbar {
            if storyFilter == .topStories || storyFilter == .bestStories || storyFilter == .newStories {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu(content: {
                        Picker(selection: $storyFilter,
                               label: Text("Sorting options")) {
                            Text("Top").tag(StoryFilter.topStories)
                            Text("Best").tag(StoryFilter.bestStories)
                            Text("New").tag(StoryFilter.newStories)
                            
                        }
                    }, label: {
                        switch storyFilter {
                        case .topStories: Image(systemName: "arrow.up")
                                .foregroundColor(.yellow)
                        case .bestStories: Image(systemName: "trophy")
                                .foregroundColor(.yellow)
                        case .newStories: Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(.yellow)
                        default:
                            EmptyView()
                        }
                        
                    })
                }
            }
            
            
        }
        .navigationTitle(storyFilter.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Stories", systemImage: "newspaper") {
                // Changing the view to stories only applies if we are not on some type of story view
                // If we are not on a story view, default to top stories
                if storyFilter != .topStories && storyFilter != .bestStories && storyFilter != .newStories {
                    storyFilter = .topStories
                }
            }
            Button("Ask Hacker News", systemImage: "questionmark.bubble") {
                storyFilter = .askStories
            }
            Button("Show Hacker News", systemImage: "eye") {
                storyFilter = .showStories
            }
            Button("Job Listings", systemImage: "briefcase") {
                storyFilter = .jobStories
            }
        }
    }
}

@Observable
class StoriesFeedData {
    var storyIds: [Int] = []
    
    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await getStoryIdsAsync(filter: filter)
        self.storyIds = ids
    }
}
