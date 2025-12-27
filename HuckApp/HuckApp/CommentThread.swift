//
//  CommentThread.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

func getRootComments(storyId: Int) async -> [CommentModel] {
    var comments = [CommentModel]()
    guard let story = await getStoryAsync(id: storyId) else {
        return comments
    }
    if let children = story.kids {
        for id in children{
            if let comment = await getCommentAsync(id: id)
            {
                var commentData = CommentModel(id: id)
                commentData.nestingLevel = 0
                commentData.parent = nil
                comments.append(commentData)
            }
        }
    }
    return comments
}

func getCommentThread(storyId: Int) async -> [CommentModel] {
    print("Getting comments")
    var commentThread = [CommentModel]()
    guard let story = await getStoryAsync(id: storyId) else {
        return commentThread
    }
    var dummy = CommentModel(id: storyId)
    if let children = story.kids {
        for id in children{
            await getCommentChildren(id: id, nestLevel: 0, parent: &dummy, allComments: &commentThread)
        }
    }
    print("Done getting comments")
    return commentThread
}

func getCommentChildren(id: Int, nestLevel: Int, parent: inout CommentModel, allComments: inout [CommentModel]) async {
    let comment = await getCommentAsync(id: id)
    if let comment = comment {
        var commentData = CommentModel(id: id)
        commentData.nestingLevel = nestLevel
        commentData.parent = parent
        parent.children.append(commentData)
        allComments.append(commentData)
        for child in comment.kids {
            await getCommentChildren(id: child, nestLevel: nestLevel + 1, parent: &commentData, allComments: &allComments)
        }
    }
}
