//
//  HackerNewsAPI.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

func getComments(for id: Int) async -> [Comment]{
    var commentThread = [Comment]()
    guard let rootItem = await AlgoliaAPIService.getItemById(id: id) else {
        return commentThread
    }
    if let children = rootItem.children {
        for child in children {
            getChildComments(nestLevel: 0, itemData: child, comments: &commentThread)
        }
    }
    return commentThread
}

private func getChildComments(nestLevel: Int, itemData: ItemData, comments: inout[Comment]) {
    let comment = Comment(item: itemData)
    comment.nestingLevel = nestLevel
    comments.append(comment)
    if let children = itemData.children {
        for child in children {
            getChildComments(nestLevel: nestLevel + 1, itemData: child, comments: &comments)
        }
    }
}
