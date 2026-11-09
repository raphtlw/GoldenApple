import Foundation

nonisolated extension Optional where Wrapped == String {
    /// The text, or nil when it is nil or empty.
    var nonEmpty: String? {
        guard let text = self, !text.isEmpty else {
            return nil
        }
        return text
    }
}
