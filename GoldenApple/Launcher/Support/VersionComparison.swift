import Foundation

/// Compares version strings by splitting them into runs of digits and runs of other characters.
/// Digit runs compare as numbers and other runs as text, so `1.10` is above `1.9`.
/// When all shared runs are equal, the version with more runs is higher.
nonisolated enum VersionComparison {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = runs(of: lhs)
        let right = runs(of: rhs)
        for (leftRun, rightRun) in zip(left, right) {
            let result = compare(run: leftRun, with: rightRun)
            if result != .orderedSame {
                return result
            }
        }
        if left.count == right.count {
            return .orderedSame
        }
        return left.count < right.count ? .orderedAscending : .orderedDescending
    }

    static func isNewer(_ version: String, than other: String) -> Bool {
        compare(version, other) == .orderedDescending
    }

    private static func compare(run left: Substring, with right: Substring) -> ComparisonResult {
        guard isDigits(left), isDigits(right) else {
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        }
        // Compare digit runs without converting to integers, so very long numbers cannot overflow.
        let leftNumber = left.drop { $0 == "0" }
        let rightNumber = right.drop { $0 == "0" }
        if leftNumber.count != rightNumber.count {
            return leftNumber.count < rightNumber.count ? .orderedAscending : .orderedDescending
        }
        return leftNumber == rightNumber ? .orderedSame : (leftNumber < rightNumber ? .orderedAscending : .orderedDescending)
    }

    private static func runs(of version: String) -> [Substring] {
        var runs: [Substring] = []
        var start = version.startIndex
        var index = version.startIndex
        while index < version.endIndex {
            let next = version.index(after: index)
            if next == version.endIndex || version[next].isASCIIDigit != version[index].isASCIIDigit {
                runs.append(version[start..<next])
                start = next
            }
            index = next
        }
        return runs
    }

    private static func isDigits(_ run: Substring) -> Bool {
        run.first?.isASCIIDigit == true
    }
}

nonisolated private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
