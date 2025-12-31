//
//  AuthenticationHandler.swift
//  HuckApp
//
//  Created by James Asbury on 12/29/25.
//

import Foundation

@Observable
class UserSession {
    static var shared: UserSession? {
        if _shared == nil {
            _shared = activeSession()
        }
        if let session = _shared {
            let now = Date.now
            if session.self .sessionExpiration! < now {
                _shared = nil
            }
        }
        return _shared
    }
        
    private(set) var username: String
    private(set) var sessionExpiration: Date?
    
    private static var _shared: UserSession? = nil
    
    private init(username: String, expiration: Date?) {
        self.username = username
        self.sessionExpiration = expiration
    }
    
    static func activeSession() -> UserSession? {
        let now = Date.now
        let url = URL(string: "https://news.ycombinator.com/")!
        let cookieStorage = HTTPCookieStorage.shared
        let cookies = cookieStorage.cookies(for: url) ?? []
        if cookies.isEmpty {
            return nil
        }
        let sortedCookies = cookies
            .filter {$0.expiresDate != nil }
            .sorted { $0.expiresDate! > $1.expiresDate! }
        let cookie = sortedCookies[0]
        if cookie.expiresDate! < now {
            return nil
        }
        let end = cookie.value.firstIndex(of: "&")
        let username = cookie.value[..<end!]
        return UserSession(username: "\(username)", expiration: sortedCookies[0].expiresDate!)
    }
}

func readCookie(forURL url: URL) -> [HTTPCookie] {
    let cookieStorage = HTTPCookieStorage.shared
    let cookies = cookieStorage.cookies(for: url) ?? []
    return cookies
}


func storeCookies(_ cookies: [HTTPCookie], forURL url: URL) {
    let cookieStorage = HTTPCookieStorage.shared
    cookieStorage.setCookies(cookies,
                             for: url,
                             mainDocumentURL: nil)
}
