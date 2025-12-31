//
//  User.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

@Observable
class User {
    let username: String
    
    var karma: Int
    var about: String
    
    init(username: String, karma: Int=0, about: String="") {
        self.username = username
        self.karma = karma
        self.about = about
    }
    
    init(from userdata: UserData) {
        self.username = userdata.username
        self.about = userdata.about?.normalizeHtmlText() ?? ""
        self.karma = userdata.karma ?? 0
    }
    
}
