//
//  Login.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import Foundation

func login(username: String, password: String) {
    let base = URL(string: "https://news.ycombinator.com/")!
    let cookieStorage = HTTPCookieStorage.shared
    
    let configuration = URLSessionConfiguration.default
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpShouldSetCookies = true
    
    var components = URLComponents()
    components.path += "login"
    components.queryItems = [
        URLQueryItem(name: "acct", value: username), URLQueryItem(name: "pw", value: password),
    ]
    // TODO: Do I need to set goto to be something like snews?
    let url = components.url(relativeTo: base)!
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    
    let urlSession = URLSession(configuration: configuration)
    urlSession.dataTask(with: request)
    
    // cookieStorage.setCookie(persistentCookie)
    
}
