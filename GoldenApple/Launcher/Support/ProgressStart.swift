import Foundation

nonisolated extension ProgressManager {
    /// Starts the subprogress a caller passed in, or a detached manager when the caller passed none.
    static func start(_ subprogress: consuming Subprogress?, totalCount: Int?) -> ProgressManager {
        if let subprogress = subprogress.take() {
            return subprogress.start(totalCount: totalCount)
        }
        return ProgressManager(totalCount: totalCount)
    }
}
