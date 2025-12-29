//
//  HackerNewsAPI.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

typealias CookieHandler = (Result<HTTPCookie, Error>) -> Void

//TODO: Replace this
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

extension URLSession {
    static func nonRedirectingEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let delegate = RedirectBlocker()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Prevent re-direction by calling handler with nil
        completionHandler(nil)
    }
}

class HackerNewsAPI {
    let baseUri = URL(string: "https://news.ycombinator.com/")
    
    func loginUri(username: String, password: String) -> URL {
        var components = URLComponents()
        components.path += "login"
        components.queryItems = [
            URLQueryItem(name: "acct", value: username), URLQueryItem(name: "pw", value: password),
        ]
        let url = components.url(relativeTo: baseUri)!
        return url
    }
    
    func login(username: String, password: String, cookieHandler: @escaping CookieHandler) {
        let session = URLSession.nonRedirectingEphemeralSession()
        let uri = loginUri(username: username, password: password)
        let dataTask = session.dataTask(with: uri, completionHandler: loginCompletionHandler(cookieHandler))
        dataTask.resume()
    }
    
    func loginCompletionHandler(_ cookieHandler: @escaping CookieHandler) -> (
        Data?, URLResponse?, Error?
    ) -> Void {
        
        let loginAction = { (data: Data?, response: URLResponse?, error: Error?) in
            if let data = data, let response = response as? HTTPURLResponse {
                if response.statusCode >= 400 && response.statusCode < 500 {
                    print("Failed here 1")
                } else {
                    let headerFields = response.allHeaderFields as! [String: String]
                    let base = self.baseUri!
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: base)
                    if let token = cookies.first(where: { $0.name == "user" }) {
                        print("Cookie!!")
                        print(token)
                        
                    } else {
                        cookieHandler(.failure(APIError.loginFailed))
                    }
                }
            } else if let error = error {
                print("Failed here 2")
            } else {
                preconditionFailure("Data and Error can't both be nil")
            }
        }
        return loginAction
    }
}

func login(username: String, password: String) {
    let api = HackerNewsAPI()
    api.login(username: username, password: password) {
        result in
        switch result {
        case .success(let token):
            print("We got cookie: \(token)")
        case .failure(let error):
            print("We don't got cookie")
        }
    }
    
}

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
