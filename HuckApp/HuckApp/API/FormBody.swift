//
//  FormBody.swift
//  HuckApp
//
//  Created by James Asbury on 9/21/26.
//

import Foundation

/// Builds `application/x-www-form-urlencoded` request bodies for the
/// reverse-engineered `news.ycombinator.com` endpoints.
///
/// Hacker News only accepts credentials and content through form POSTs, and
/// every one of them carries arbitrary user text — a password, a comment. That
/// makes the encoding load-bearing rather than incidental: `URLComponents`
/// leaves `+`, `&` and `=` intact in a query value, so a password containing
/// any of them, or a comment containing all three, would silently corrupt the
/// body. Encoding to RFC 3986's *unreserved* set instead means the only
/// characters left unescaped are ones with no meaning in a form body.
enum FormBody {
    /// Percent-encodes `fields` into a form body, preserving their order.
    ///
    /// Order is part of the contract: the hidden fields scraped from one of
    /// HN's forms are sent back in the order the form declared them, which a
    /// dictionary couldn't promise.
    static func encoded(_ fields: [(name: String, value: String)]) -> Data {
        let joined = fields
            .map { "\(percentEncoded($0.name))=\(percentEncoded($0.value))" }
            .joined(separator: "&")
        return Data(joined.utf8)
    }

    /// RFC 3986's unreserved set — everything outside it gets escaped.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
