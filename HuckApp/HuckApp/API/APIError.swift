//
//  APIError.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

public enum APIError: Error, LocalizedError {
    case loginFailed
    case notLoggedIn
    case missingAuthToken
    case voteFailed
    case favoriteFailed
    case unknown

    public var errorDescription: String? {
        switch self {
        case .loginFailed: return "Login Failed."
        case .notLoggedIn: return "You must be logged in to do that."
        case .missingAuthToken: return "Couldn't verify the action with Hacker News."
        case .voteFailed: return "Vote Failed."
        case .favoriteFailed: return "Favorite Failed."
        case .unknown: return "Unknown Error."
        }
    }
}
