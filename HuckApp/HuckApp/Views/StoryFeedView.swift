//
//  StoryFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

enum ImageStatus {
    case loading
    case finished(Image)
    case failed
}

struct StoryCellView: View {
    let storyId: Int
    @State private var observableStory: StoryData
    @State private var thumbnailStatus: ImageStatus = .loading
    @State private var metadata: LPLinkMetadata? = nil
    @State private var isValidUrl = true
    
    init(storyId: Int) {
        self.storyId = storyId
        self.observableStory = StoryData(storyId: storyId)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                NavigationLink(destination: StoryWebView(url: URL(string: observableStory.story?.url ?? ""))) {
                    Text(observableStory.story?.title ?? "\(storyId)")
                }
                .navigationLinkIndicatorVisibility(.hidden)
                Text("")
                VStack(alignment: .leading){
                    Text("\(observableStory.story?.by ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    HStack {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.gray)
                        Text("\(observableStory.story?.score ?? 0)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "bubble")
                            .foregroundColor(.gray)
                        Text("\(observableStory.story?.kids.count ?? 0)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        //Text("\(observableStory.story?.time ?? 0)")
                        Text("1h")
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
                    case .loading:
                        ProgressView()

                    case .finished(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    case .failed:
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
            .task {
                await fetchMetadata()
            }
        }
        .task {
            await observableStory.getStory()
        }
    
    }
    
    private func fetchMetadata() async {
        let url = URL(string: observableStory.story?.url ?? "")
        guard let url else {
            isValidUrl = false
            return
        }

        do {
            metadata = try await LPMetadataProvider().startFetchingMetadata(for: url)
            await loadThumbnail(from: metadata?.imageProvider)
        }
        catch {
            print("Error fetching URL metadata: \(error.localizedDescription)")
            isValidUrl = false
        }
    }
    
    private func loadThumbnail(from imageProvider: NSItemProvider?) async {
        let imageType = UTType.image.identifier
        do {
            guard let imageProvider, imageProvider.hasItemConformingToTypeIdentifier(imageType) else {
                thumbnailStatus = .failed
                return
            }

            let item = try await imageProvider.loadItem(forTypeIdentifier: imageType)
            if item is UIImage, let image = item as? UIImage {
                thumbnailStatus = .finished(Image(uiImage: image))
            }
            else if item is URL {
                guard let url = item as? URL,
                      let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data)
                else {
                    thumbnailStatus = .failed
                    return
                }
                thumbnailStatus = .finished(Image(uiImage: image))
            }
            else if item is Data {
                guard let data = item as? Data, let image = UIImage(data: data) else {
                    thumbnailStatus = .failed
                    return
                }
                thumbnailStatus = .finished(Image(uiImage: image))
            }
        }
        catch {
            print("Error loading Image: \(error.localizedDescription)")
            thumbnailStatus = .failed
        }
    }
}

struct StoryFeedView: View {
    let observableStories = StoriesFeedData()
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) {item in
                StoryCellView(storyId: item)
            }
        }
        .listStyle(.plain)
        .task {
            await self.observableStories.fetchStoryIds()
        }
    }
}

@Observable
class StoriesFeedData {
    var storyIds: [Int] = []
    
    func fetchStoryIds() async {
        let ids = await getStoryIdsAsync()
        self.storyIds = ids
    }
}

@Observable
class StoryData {
    let storyId: Int
    var story: Story? = nil
    
    init(storyId: Int) {
        self.storyId = storyId
    }
    
    func getStory() async {
        self.story = await getStoryAsync(id: self.storyId)
    }
}

// TODO: eventually needs an enum for if we are sorting by top, best, or new
func getStoryIdsAsync() async -> [Int] {
    let url = "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"
    guard let stories: [Int] = await WebService().downloadData(fromURL: url) else {
        return []
    }
    print("Stories: \(stories)")
    return stories
}

struct Story: Codable {
    let title: String
    let by: String
    let score: Int
    let kids: [Int]
    let time: Int
    let url: String
}

func getStoryAsync(id: Int) async -> Story? {
    let url = "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty"
    guard let story: Story = await WebService().downloadData(fromURL: url) else {
        return nil
    }
    print("Story: \(story)")
    return story
}
