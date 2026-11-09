//
//  APIError.swift
//  Huck
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

/// Why a request's response couldn't be used, below the level of what the
/// app tells the reader.
nonisolated enum NetworkError: Error {
    case badUrl
    case invalidRequest
    case badResponse
    case badStatus
    case failedToDecodeResponse
}

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
    /// A reply was aimed at a comment the reader posted moments ago whose
    /// Hacker News id still can't be confirmed, so there's nothing to hang the
    /// reply off yet. Retrying usually resolves it.
    case unknownReplyTarget
    /// Hacker News no longer offers to delete the comment — the edit window
    /// has passed, or it has replies.
    case deleteUnavailable
    /// Hacker News offered to delete the comment but didn't accept the request.
    case deleteFailed
    /// Hacker News refused the submission. As with comments, it doesn't say
    /// why in a form we can read.
    case submitFailed
    case unknown

    public var errorDescription: String? {
        switch self {
        case .loginFailed: "Incorrect username and/or password."
        case .loginValidationRequired:
            "Hacker News asked for additional verification. Sign in at news.ycombinator.com, then try again."
        case .notLoggedIn: "You must be logged in to do that."
        case .missingAuthToken: "Couldn't verify the action with Hacker News."
        case .voteFailed: "Vote Failed."
        case .favoriteFailed: "Favorite Failed."
        case .commentFailed:
            "Hacker News wouldn't accept your comment. You may be posting too quickly — wait a moment and try again."
        case .unknownReplyTarget:
            "Hacker News hasn't finished publishing the comment you're replying to. Wait a moment and try again — your reply is saved."
        case .deleteUnavailable:
            "Hacker News no longer allows this comment to be deleted. Comments can only be deleted shortly after posting, before anyone replies."
        case .deleteFailed: "Hacker News didn't delete the comment. Try again in a moment."
        case .submitFailed:
            "Hacker News wouldn't accept your post. You may be posting too quickly, or the title or link may not be allowed — check them and try again."
        case .unknown: "Unknown Error."
        }
    }
}
