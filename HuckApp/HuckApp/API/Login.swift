//
//  Login.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import Foundation
/*
enum Result {
    case success(HTTPURLResponse, Data)
    case failure(Error)
}
 */

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
/*
 func executeURLRequest(url: URLRequest, inSession session: URLSession = .shared, completion: @escaping (Result) -> Void) {
 print("Executing request")
 let task = session.dataTask(with: url) { data, response, error in
 
 if let response = response as? HTTPURLResponse,
 let data = data {
 completion(.success(response, data))
 return
 }
 
 if let error = error {
 completion(.failure(error))
 return
 }
 
 let error = NSError(domain: "com.cookiesetting.test", code: 101, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"])
 completion(.failure(error))
 }
 task.resume()
 }
 
 func login(username: String, password: String) {
 let base = URL(string: "https://news.ycombinator.com/")!
 let cookieStorage = HTTPCookieStorage.shared
 
 print("setting up configuration")
 /*
  let configuration = URLSessionConfiguration.default
  configuration.httpCookieAcceptPolicy = .always
  configuration.httpShouldSetCookies = true
  */
 let configuration = URLSessionConfiguration.ephemeral
 configuration.httpCookieAcceptPolicy = .never
 
 print("Setting URL components")
 var components = URLComponents()
 components.path += "login"
 components.queryItems = [
 URLQueryItem(name: "acct", value: username), URLQueryItem(name: "pw", value: password),
 ]
 // TODO: Do I need to set goto to be something like news?
 let url = components.url(relativeTo: base)!
 var request = URLRequest(url: url)
 request.setValue("application/json", forHTTPHeaderField: "Content-Type")
 request.httpMethod = "POST"
 
 print("Creating URL session")
 let urlSession = URLSession(configuration: configuration)
 /*
  let task = urlSession.dataTask(with: request) { data, response, error in
  print("Error: \(error?.localizedDescription ?? "None")")
  print("Data: \(String(decoding: data ?? Data(), as: UTF8.self))")
  print("Response: \(String(describing: response))")
  
  let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as! [String: String], for: googleURL)
  }
  task.resume()
  
  //let cookieStorage = HTTPCookieStorage.shared
  let cookies = cookieStorage.cookies(for: base) ?? []
  print("Cookies after storing: ", cookies)
  */
 var cookies = readCookie(forURL: base)
 executeURLRequest(url: request, inSession: urlSession) { result in
 print("here 1")
 if  case let .success  (response, data) = result {
 
 guard let cookiesResponseHeader = response.allHeaderFields["Set-Cookie"] else {
 print("\(response.allHeaderFields)")
 print("\(cookiesResponseHeader)")
 return
 }
 
 
 cookies = readCookie(forURL: base)
 print("Cookies after request: ", cookies)
 
 let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as! [String: String], for: base)
 storeCookies(responseCookies, forURL: base)
 cookies = readCookie(forURL: base)
 print("Cookies after storing: ", cookies)
 
 }
 }
 
 // cookieStorage.setCookie(persistentCookie)
 
 }
 */
