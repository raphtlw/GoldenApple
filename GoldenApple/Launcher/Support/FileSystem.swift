import Foundation

/// File helpers shared by the launcher.
nonisolated enum FileSystem {
    private static var manager: FileManager { .default }

    static func exists(_ url: URL) -> Bool {
        manager.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func createFolder(_ url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes through a temporary file, so readers never see a partial file.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        try createFolder(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }

    static func removeIfPresent(_ url: URL) throws {
        guard exists(url) || isSymbolicLink(url) else {
            return
        }
        try manager.removeItem(at: url)
    }

    /// Moves a file into place, replacing what is there.
    static func move(_ source: URL, to destination: URL) throws {
        try createFolder(destination.deletingLastPathComponent())
        try removeIfPresent(destination)
        try manager.moveItem(at: source, to: destination)
    }

    /// Deletes everything inside a folder and keeps the folder.
    static func emptyFolder(_ url: URL) throws {
        try createFolder(url)
        for item in try contents(of: url) {
            try manager.removeItem(at: item)
        }
    }

    /// The items in a folder, including hidden ones. A missing folder has no items.
    static func contents(of url: URL) throws -> [URL] {
        guard isDirectory(url) else {
            return []
        }
        return try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    /// Paths of the files below a folder, relative to it. Folders are not listed.
    static func relativeFilePaths(in folder: URL) throws -> [String] {
        try manager.subpathsOfDirectory(atPath: folder.path).filter { !isDirectory(folder.appending(path: $0)) }
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? manager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func setExecutable(_ url: URL) throws {
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func createSymbolicLink(at url: URL, pointingTo target: String) throws {
        try createFolder(url.deletingLastPathComponent())
        try removeIfPresent(url)
        try manager.createSymbolicLink(atPath: url.path, withDestinationPath: target)
    }

    static func copyIfMissing(_ source: URL, to destination: URL) throws {
        guard !exists(destination) else {
            return
        }
        try createFolder(destination.deletingLastPathComponent())
        try manager.copyItem(at: source, to: destination)
    }

    /// Copies a file into place, replacing what is there.
    static func replace(_ destination: URL, withCopyOf source: URL) throws {
        try createFolder(destination.deletingLastPathComponent())
        try removeIfPresent(destination)
        try manager.copyItem(at: source, to: destination)
    }

    static func moveToTrash(_ url: URL) throws {
        try manager.trashItem(at: url, resultingItemURL: nil)
    }

    // MARK: Paths and names

    /// Resolves a relative path inside `base`. Rejects empty, absolute and `..` paths.
    static func safeChild(_ relativePath: String, of base: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isUnsafe = relativePath.hasPrefix("/")
            || relativePath.hasPrefix("~")
            || components.isEmpty
            || components.contains("..")
            || relativePath.contains("\\")
        guard !isUnsafe else {
            throw LauncherError.unsafePath(relativePath)
        }
        return components.reduce(base) { url, component in url.appending(path: component) }
    }

    /// A folder name made from a display name, without `/`, `:` and other characters that cause trouble in paths.
    /// Returns nil when nothing usable is left.
    static func safeFolderName(_ name: String) -> String? {
        let unsafe = CharacterSet(charactersIn: "/:\\*?\"<>|").union(.controlCharacters).union(.illegalCharacters)
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { !unsafe.contains($0) }))
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        var folderName = words.joined(separator: " ")
        while folderName.hasPrefix(".") {
            folderName.removeFirst()
        }
        folderName = folderName.trimmingCharacters(in: .whitespaces)
        return folderName.isEmpty ? nil : folderName
    }

    /// `name`, or `name 2`, `name 3` and so on, so that no item with that name exists in `parent`.
    static func uniqueName(_ name: String, in parent: URL) -> String {
        var candidate = name
        var number = 2
        while exists(parent.appending(path: candidate)) {
            candidate = "\(name) \(number)"
            number += 1
        }
        return candidate
    }

    static func versionFolderName(_ version: String) -> String {
        version.replacing("/", with: "-")
    }
}
