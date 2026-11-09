import Foundation
import os

/// Reads and writes instance folders below `Instances/`.
nonisolated struct InstanceStore: Sendable {
    let paths: LauncherPaths

    /// Every readable instance, sorted by name. Folders that cannot be read are skipped and logged.
    func list() throws -> [Instance] {
        try FileSystem.createFolder(paths.instances)
        let folders = try FileSystem.contents(of: paths.instances).filter { folder in
            FileSystem.exists(InstancePaths(folder: folder).configurationFile)
        }
        let instances = folders.compactMap { folder -> Instance? in
            do {
                return try instance(id: folder.lastPathComponent)
            } catch {
                LauncherLog.instances.error("Skipping instance folder \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return instances.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func instance(id: String) throws -> Instance {
        let instancePaths = paths.instance(id)
        guard FileSystem.exists(instancePaths.configurationFile) else {
            throw LauncherError.instanceNotFound(id)
        }
        let configuration = try JSONFiles.readOwnFile(InstanceConfiguration.self, from: instancePaths.configurationFile)
        let components = try JSONFiles.readOwnFile(ComponentList.self, from: instancePaths.componentsFile).components
        guard let minecraftVersion = components.minecraftVersion else {
            throw LauncherError.missingMinecraftComponent(configuration.name)
        }
        let loader = components.loaderComponent
        return Instance(
            id: id,
            name: configuration.name,
            folder: instancePaths.folder,
            gameFolder: instancePaths.gameFolder,
            minecraftVersion: minecraftVersion,
            loader: loader?.loader,
            loaderVersion: loader?.version,
            lastPlayed: configuration.lastPlayed
        )
    }

    /// Reloads an instance from disk, so callers always work with the current files.
    func current(_ instance: Instance) throws -> Instance {
        try self.instance(id: instance.id)
    }

    /// Creates the folder, `Instance.json`, `Components.json` and the `Minecraft/` game directory.
    func create(name: String, components: [InstanceComponent]) throws -> Instance {
        let id = try uniqueFolderName(for: name)
        let instancePaths = paths.instance(id)
        do {
            try FileSystem.createFolder(instancePaths.gameFolder)
            try JSONFiles.writeOwnFile(ComponentList(components: components), to: instancePaths.componentsFile)
            try JSONFiles.writeOwnFile(InstanceConfiguration(name: name), to: instancePaths.configurationFile)
        } catch {
            try? FileSystem.removeIfPresent(instancePaths.folder)
            throw error
        }
        LauncherLog.instances.info("Created instance \(id, privacy: .public)")
        return try instance(id: id)
    }

    /// Changes the name. The folder is renamed too when the name gives a different folder name.
    func rename(_ instance: Instance, to name: String) throws -> Instance {
        guard let folderName = FileSystem.safeFolderName(name) else {
            throw LauncherError.invalidName(name)
        }
        let oldFolder = paths.instance(instance.id).folder
        guard FileSystem.exists(oldFolder) else {
            throw LauncherError.instanceNotFound(instance.name)
        }
        var id = instance.id
        if folderName != instance.id {
            // A change of letter case only keeps the same folder on a case-insensitive volume.
            let isCaseChange = folderName.lowercased() == instance.id.lowercased()
            id = isCaseChange ? folderName : FileSystem.uniqueName(folderName, in: paths.instances)
            try FileManager.default.moveItem(at: oldFolder, to: paths.instance(id).folder)
        }
        try updateConfiguration(id: id) { $0.name = name }
        return try self.instance(id: id)
    }

    /// Moves the instance folder to the Trash.
    func delete(_ instance: Instance) throws {
        let folder = paths.instance(instance.id).folder
        guard FileSystem.exists(folder) else {
            throw LauncherError.instanceNotFound(instance.name)
        }
        try FileSystem.moveToTrash(folder)
        LauncherLog.instances.info("Moved instance \(instance.id, privacy: .public) to the Trash")
    }

    // MARK: Files

    func components(of instance: Instance) throws -> [InstanceComponent] {
        try JSONFiles.readOwnFile(ComponentList.self, from: paths.instance(instance.id).componentsFile).components
    }

    @discardableResult
    func saveComponents(_ components: [InstanceComponent], for instance: Instance) throws -> Instance {
        try JSONFiles.writeOwnFile(ComponentList(components: components), to: paths.instance(instance.id).componentsFile)
        return try current(instance)
    }

    func configuration(of instance: Instance) throws -> InstanceConfiguration {
        try JSONFiles.readOwnFile(InstanceConfiguration.self, from: paths.instance(instance.id).configurationFile)
    }

    func updateConfiguration(of instance: Instance, _ change: (inout InstanceConfiguration) -> Void) throws {
        try updateConfiguration(id: instance.id, change)
    }

    private func updateConfiguration(id: String, _ change: (inout InstanceConfiguration) -> Void) throws {
        let file = paths.instance(id).configurationFile
        var configuration = try JSONFiles.readOwnFile(InstanceConfiguration.self, from: file)
        change(&configuration)
        try JSONFiles.writeOwnFile(configuration, to: file)
    }

    private func uniqueFolderName(for name: String) throws -> String {
        guard let folderName = FileSystem.safeFolderName(name) else {
            throw LauncherError.invalidName(name)
        }
        return FileSystem.uniqueName(folderName, in: paths.instances)
    }
}
