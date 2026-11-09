import Foundation
import os

/// One file that GoldenApple installed from Modrinth or CurseForge.
nonisolated struct InstalledContentEntry: Codable, Hashable, Identifiable, Sendable {
    let provider: ContentProvider
    let projectID: String
    let versionID: String
    let title: String
    let versionNumber: String
    /// Relative to the instance `Minecraft/` folder, for example `mods/sodium.jar`.
    let path: String
    var sha1: String?

    var id: String { path }

    func isSameProject(as other: InstalledContentEntry) -> Bool {
        provider == other.provider && projectID == other.projectID
    }
}

/// The contents of `Installed Content.json`.
nonisolated private struct InstalledContentList: Codable {
    var entries: [InstalledContentEntry] = []
}

/// Reads and changes `Installed Content.json` of an instance and the files it lists.
nonisolated struct InstalledContentStore: Sendable {
    /// The entries, or none when the file does not exist yet.
    func entries(of instance: Instance) throws -> [InstalledContentEntry] {
        try load(instance).entries
    }

    func isInstalled(provider: ContentProvider, projectID: String, in instance: Instance) throws -> Bool {
        try entries(of: instance).contains { $0.provider == provider && $0.projectID == projectID }
    }

    /// Adds the entries. An older entry of the same project, or with the same path, is replaced,
    /// and its file is deleted when the new entry uses another path.
    func record(_ newEntries: [InstalledContentEntry], in instance: Instance) throws {
        var list = try load(instance)
        for entry in newEntries {
            let replaced = list.entries.filter { $0.isSameProject(as: entry) || $0.path == entry.path }
            for old in replaced where old.path != entry.path {
                try deleteFile(of: old, in: instance)
            }
            list.entries.removeAll { $0.isSameProject(as: entry) || $0.path == entry.path }
            list.entries.append(entry)
        }
        try save(list, for: instance)
    }

    /// Deletes the file of the entry and removes the entry. A file that is already gone is not an error.
    func remove(_ entry: InstalledContentEntry, from instance: Instance) throws {
        try deleteFile(of: entry, in: instance)
        var list = try load(instance)
        list.entries.removeAll { $0.path == entry.path }
        try save(list, for: instance)
    }

    // MARK: Files

    private func load(_ instance: Instance) throws -> InstalledContentList {
        let file = instance.paths.installedContentFile
        guard FileSystem.exists(file) else {
            return InstalledContentList()
        }
        return try JSONFiles.readOwnFile(InstalledContentList.self, from: file)
    }

    private func save(_ list: InstalledContentList, for instance: Instance) throws {
        try JSONFiles.writeOwnFile(list, to: instance.paths.installedContentFile)
    }

    private func deleteFile(of entry: InstalledContentEntry, in instance: Instance) throws {
        let file = try FileSystem.safeChild(entry.path, of: instance.gameFolder)
        try FileSystem.removeIfPresent(file)
        LauncherLog.content.info("Deleted \(entry.path, privacy: .public) from \(instance.id, privacy: .public)")
    }
}
