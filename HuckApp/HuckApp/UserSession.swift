//
//  UserSession.swift
//  HuckApp
//
//  Created by James Asbury on 12/29/25.
//

import Foundation

/// Who is signed in, and the only place the app decides that.
///
/// Hacker News authenticates with a `user` cookie, so the cookie jar is the real
/// source of truth; this type derives an account from it and *publishes* that
/// derivation. Being an `@Observable` instance injected through the environment —
/// like `InteractionStore` and the other per-user stores — is what makes signing
/// in and out propagate on its own: a view that reads `account` in its body is
/// re-evaluated when it changes, with no manual invalidation.
///
/// Sign-in and sign-out go through here rather than straight to `HackerNewsAPI`
/// so that changing the cookie and changing `account` are one step. Splitting
/// them is what previously let one login path update the session while another
/// forgot to.
@MainActor
@Observable
final class UserSession {
    /// The signed-in account, or `nil` when signed out.
    private(set) var account: Account?

    /// A signed-in Hacker News account.
    struct Account: Equatable, Sendable {
        let username: String
        /// When the auth cookie expires; the session is treated as ended past it.
        let expiration: Date
    }

    init() {
        refresh()
    }

    /// The signed-in username, or `nil`. Convenience for the common read.
    var username: String? { account?.username }

    var isSignedIn: Bool { account != nil }

    /// Re-derives the account from the cookie jar. Call when the cookies may have
    /// changed underneath the app, or to re-check an expiry — returning to the
    /// foreground is both.
    func refresh() {
        account = Self.storedAccount()
    }

    /// Signs in and adopts the resulting session. Throws if the credentials are
    /// rejected, leaving `account` untouched.
    func signIn(username: String, password: String) async throws {
        try await HackerNewsAPI.login(username: username, password: password)
        refresh()
    }

    /// Signs out, clearing the auth cookie and the account together.
    func signOut() {
        if let username = account?.username {
            HackerNewsAPI.logout(username: username)
        }
        account = nil
    }

    /// The account encoded in Hacker News' `user` cookie, or `nil` if there isn't
    /// a usable one. Every step is optional rather than forced: a cookie jar can
    /// hold a `user` cookie that is session-scoped, expired, or malformed, and
    /// none of those should be a crash.
    private static func storedAccount() -> Account? {
        let cookies = HTTPCookieStorage.shared.cookies(for: HackerNewsAPI.baseUri) ?? []
        guard let cookie = cookies.first(where: { $0.name == "user" }),
              let expiration = cookie.expiresDate,
              expiration > .now else {
            return nil
        }
        // The value is `<username>&<token>`.
        let username = cookie.value.prefix { $0 != "&" }
        guard !username.isEmpty else { return nil }
        return Account(username: String(username), expiration: expiration)
    }
}

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
