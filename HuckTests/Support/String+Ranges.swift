//
//  String+Ranges.swift
//  HuckTests
//

/// Ranges into a string written the way a test reads, for exercising code that
/// takes a selection.
extension String {
    /// The range of the first occurrence of `substring`.
    func range(of substring: String) -> Range<String.Index> {
        guard let range = firstRange(of: substring) else {
            preconditionFailure("\"\(substring)\" not found in \"\(self)\"")
        }
        return range
    }

    /// An empty range — a cursor — `offset` characters into the string.
    func cursor(at offset: Int) -> Range<String.Index> {
        let index = index(startIndex, offsetBy: offset)
        return index..<index
    }

    /// How many characters into the string `index` is.
    func offset(of index: String.Index) -> Int {
        distance(from: startIndex, to: index)
    }
}
