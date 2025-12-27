//
//  StoryData.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

enum StoryType {
    case link
    case text
    case unknown
}

// TODO: If this is observable, then just store these in our cache
// In parallel, we update with a thumbnail, then the views get updated
@Observable
class StoryModel : Equatable {
    let id: Int
    var storyType: StoryType
    var title: String
    var by: String
    var timestamp: Date
    var score: Int
    var url: URL?
    var commentCount: Int
    // TODO: Thumbnail handling
    var thumbnail: Image?
    var text: String?
    
    init(id: Int) {
        self.id = id
        self.storyType = .unknown
        self.title = ""
        self.by = ""
        self.timestamp = Date()
        self.score = 0
        self.commentCount = 0
        self.url = nil
        self.text = nil
    }
    
    func fetchData() async {
        if let story = await StoryCache.getStory(id: id) {
            if let url = story.url {
                storyType = .link
                self.url = URL(string: url)
            }
            else {
                storyType = .text
                self.url = nil
                self.text = story.text
            }
            self.title = story.title
            self.by = story.by
            self.timestamp = Date(timeIntervalSince1970: TimeInterval(story.time))
            self.score = story.score
            self.commentCount = story.kids?.count ?? 0
        }
    }
    
    static func ==(lhs: StoryModel, rhs: StoryModel) -> Bool {
        return lhs.title == rhs.title && lhs.id == rhs.id
    }
}
