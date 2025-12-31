//
//  APIError.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import Foundation

public enum APIError: Error, LocalizedError {
    case loginFailed
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .loginFailed: return "Login Failed."
        case .unknown: return "Unknown Error."
        }
    }
}
