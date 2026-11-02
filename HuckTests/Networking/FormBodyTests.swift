//
//  FormBodyTests.swift
//  HuckTests
//

import Foundation
@testable import Huck
import Testing

struct FormBodyTests {
    private func body(_ fields: [(name: String, value: String)]) -> String {
        String(data: FormBody.encoded(fields), encoding: .utf8) ?? ""
    }

    @Test func joinsFieldsInOrder() {
        #expect(body([("acct", "pg"), ("pw", "secret"), ("goto", "news")]) == "acct=pg&pw=secret&goto=news")
    }

    /// The characters that would corrupt a form body if left unescaped.
    @Test(arguments: [
        ("a+b", "a%2Bb"),
        ("a&b", "a%26b"),
        ("a=b", "a%3Db"),
        ("a b", "a%20b"),
        ("a/b?c#d", "a%2Fb%3Fc%23d"),
    ])
    func escapesReservedCharacters(value: String, expected: String) {
        #expect(body([("text", value)]) == "text=\(expected)")
    }

    @Test func leavesUnreservedCharactersAlone() {
        #expect(body([("text", "Az09-._~")]) == "text=Az09-._~")
    }
}
