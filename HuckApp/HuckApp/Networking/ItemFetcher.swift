//
//  ItemFetcher.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

@Observable
class ItemFetcher {
    let id: Int
    var storyItems: [ItemData] = []
    
    init(id: Int) {
        self.id = id
    }
    
    func fetchStoryItems() async {
        let rootItem = 
    }
}
