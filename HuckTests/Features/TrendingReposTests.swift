//
//  TrendingReposTests.swift
//  HuckTests
//

@testable import Huck
import Testing

struct TrendingReposTests {
    @Test(arguments: [
        ("https://github.com/apple/swift", "apple/swift"),
        ("https://www.github.com/Apple/Swift", "apple/swift"),
        ("https://github.com/apple/swift.git", "apple/swift"),
        ("https://github.com/apple/swift/tree/main/docs", "apple/swift"),
        ("https://github.com/apple/swift/releases", "apple/swift"),
    ])
    func recognizesRepositoryLinks(url: String, key: String) {
        #expect(TrendingRepos.repositoryKey(for: url) == key)
    }

    @Test(arguments: [
        "https://github.com/apple",
        "https://github.com/apple/swift/issues/1",
        "https://github.com/apple/swift/pull/2",
        "https://github.com/trending/swift",
        "https://gist.github.com/someone/abc123",
        "https://gitlab.com/apple/swift",
        "not a url",
    ])
    func rejectsEverythingElse(url: String) {
        #expect(TrendingRepos.repositoryKey(for: url) == nil)
    }
}
