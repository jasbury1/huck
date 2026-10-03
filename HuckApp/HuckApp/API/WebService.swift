//
//  WebService.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

nonisolated enum NetworkError: Error {
    case badUrl
    case invalidRequest
    case badResponse
    case badStatus
    case failedToDecodeResponse
}

class WebService {
    /// Fetches and decodes JSON. `@concurrent`, so the decoding runs on the
    /// global executor rather than the caller's: most callers are main-actor
    /// code, and the launch warm-up alone decodes hundreds of stories, which
    /// would otherwise all land on the main thread.
    @concurrent
    nonisolated func downloadData<T: Decodable & Sendable>(fromURL: String) async -> T? {
        do {
            guard let url = URL(string: fromURL) else { throw NetworkError.badUrl }
            let (data, response) = try await URLSession.shared.countedData(for: URLRequest(url: url))
            guard let response = response as? HTTPURLResponse else {
                throw NetworkError.badResponse
            }
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                print("Status: \(response.statusCode)")
                throw NetworkError.badStatus
            }
            guard let decodedResponse = try? JSONDecoder().decode(T.self, from: data) else {
                throw NetworkError.failedToDecodeResponse
            }
            
            return decodedResponse
        } catch NetworkError.badUrl {
            print("There was an error creating the URL")
        } catch NetworkError.badResponse {
            print("Did not get a valid response")
        } catch NetworkError.badStatus {
            print("Did not get a 2xx status code from the response")
        } catch NetworkError.failedToDecodeResponse {
            print("Failed to decode response into the given type")
        } catch {
            print("An error occured downloading the data")
        }
        
        return nil
    }
}
