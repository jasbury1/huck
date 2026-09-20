//
//  APIError.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

public enum APIError: Error, LocalizedError {
    case loginFailed
    /// Hacker News answered the login with its reCAPTCHA challenge instead of
    /// accepting or rejecting the credentials. Distinct from `loginFailed` so
    /// we don't tell someone their correct password is wrong.
    case loginValidationRequired
    case notLoggedIn
    case missingAuthToken
    case voteFailed
    case favoriteFailed
    case unknown

    public var errorDescription: String? {
        switch self {
        case .loginFailed: return "Incorrect username and/or password."
        case .loginValidationRequired:
            return "Hacker News asked for additional verification. Sign in at news.ycombinator.com, then try again."
        case .notLoggedIn: return "You must be logged in to do that."
        case .missingAuthToken: return "Couldn't verify the action with Hacker News."
        case .voteFailed: return "Vote Failed."
        case .favoriteFailed: return "Favorite Failed."
        case .unknown: return "Unknown Error."
        }
    }
}
