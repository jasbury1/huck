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
    /// Hacker News refused the comment. It doesn't say why in a form we can
    /// read, and the reasons are varied — a duplicate, posting too fast, a
    /// stale form token, a thread that's been locked.
    case commentFailed
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
        case .commentFailed:
            return "Hacker News wouldn't accept your comment. You may be posting too quickly — wait a moment and try again."
        case .unknown: return "Unknown Error."
        }
    }
}
