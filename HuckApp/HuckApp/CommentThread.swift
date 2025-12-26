//
//  CommentThread.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

func getCommentThread(storyId: Int) async -> [CommentData] {
    var commentThread = [CommentData]()
    guard let story = await getStoryAsync(id: storyId) else {
        return commentThread
    }
    var dummy = CommentData(id: storyId)
    if let children = story.kids {
        for id in children{
            await getCommentChildren(id: id, nestLevel: 0, parent: &dummy, allComments: &commentThread)
        }
    }
    return commentThread
}

func getCommentChildren(id: Int, nestLevel: Int, parent: inout CommentData, allComments: inout [CommentData]) async {
    let comment = await getCommentAsync(id: id)
    if let comment = comment {
        var commentData = CommentData(id: id)
        commentData.nestingLevel = nestLevel
        commentData.parent = parent
        parent.children.append(commentData)
        allComments.append(commentData)
        for child in comment.kids {
            await getCommentChildren(id: child, nestLevel: nestLevel + 1, parent: &commentData, allComments: &allComments)
        }
    }
}
