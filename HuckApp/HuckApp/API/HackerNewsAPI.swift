//
//  HackerNewsAPI.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

typealias CookieHandler = (Result<HTTPCookie, Error>) -> Void

extension URLSession {
    static func nonRedirectingEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let delegate = RedirectBlocker()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

class RedirectBlocker: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Prevent re-direction by calling handler with nil
        print("Redirect blocked")
        completionHandler(nil)
    }
}

class HackerNewsAPI {
    let baseUri = URL(string: "https://news.ycombinator.com/")!
    
    func loginUri(username: String, password: String) -> URL {
        var components = URLComponents()
        components.path += "login"
        components.queryItems = [
            URLQueryItem(name: "acct", value: username), URLQueryItem(name: "pw", value: password),
        ]
        let url = components.url(relativeTo: baseUri)!
        return url
    }
    
    func login(username: String, password: String, cookieHandler: @escaping CookieHandler) async throws {
        let session = URLSession.nonRedirectingEphemeralSession()
        let uri = loginUri(username: username, password: password)
        let request = URLRequest(url: uri)
        
        // Do not use request.httpMethod = "POST". It skips the redirect delegate
        do {
            // TODO: Move this all to web service
            let (_, response) = try await session.data(for: request, delegate: RedirectBlocker())
            guard let response = response as? HTTPURLResponse else {
                print("Bad response: \(response)")
                throw NetworkError.badResponse
            }
            let headerFields = response.allHeaderFields as! [String: String]
            let base = self.baseUri
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: base)
            if let token = cookies.first(where: { $0.name == "user" }) {
                print("Success. Calling cookie handler")
                cookieHandler(.success(token))
            } else {
                print("Failure. Calling cookie handler")
                cookieHandler(.failure(APIError.loginFailed))
            }
        }
        catch {
            // TODO: Re-wrap in a login specific error
            throw error
        }
    }
    
    func logout(username: String) {
        let cookies = readCookie(forURL: baseUri)
            .filter{ $0.name == "user" && $0.value.contains(username)}
        print("User cookies: \(cookies)")
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
}

func logout(username: String) {
    let api = HackerNewsAPI()
    api.logout(username: username)
}

// TODO: Eventually these wrappers will be able to pull dummy data with a MOC API handler.
// We should be able to set the HackerNewsAPI to be something different
func login(username: String, password: String) async throws {
    let api = HackerNewsAPI()
    var loginError: Error?
    do {
        try await api.login(username: username, password: password) {
            result in
            switch result {
            case .success(let token):
                print("Storing cookie.")
                let cookieStorage = HTTPCookieStorage.shared
                cookieStorage.setCookies([token],
                                         for: api.baseUri,
                                         mainDocumentURL: nil)
            case let .failure(error):
                print("Will not store cookie. Failed to log in.")
                loginError = error
            }
        }
        if loginError != nil {
            throw loginError!
        }
    }
    catch {
        throw error
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

func getUser(for username: String) async -> User? {
    let userdata = await AlgoliaAPIService.getUserData(username)
    if let userdata = userdata {
        return User(from: userdata)
    }
    return nil
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
