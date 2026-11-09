import Foundation

/// Build-time values of the launcher. Users change their own values in `LauncherSettings`.
nonisolated struct GoldenAppleConfiguration: Sendable {
    var launcherName: String
    var launcherVersion: String
    var userAgent: String
    var metadataBaseURL: URL
    var libraryBaseURL: URL
    var resourceBaseURL: URL
    var microsoftClientID: String
    var microsoftRedirectURI: String
    var curseForgeAPIKey: String
    var dataDirectoryName: String

    static let `default`: GoldenAppleConfiguration = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return GoldenAppleConfiguration(
            launcherName: "GoldenApple",
            launcherVersion: version,
            userAgent: "GoldenApple/\(version)",
            metadataBaseURL: URL(string: "https://meta.prismlauncher.org/v1/")!,
            libraryBaseURL: URL(string: "https://libraries.minecraft.net/")!,
            resourceBaseURL: URL(string: "https://resources.download.minecraft.net/")!,
            microsoftClientID: "",
            microsoftRedirectURI: "goldenapple://oauth/microsoft",
            curseForgeAPIKey: "",
            dataDirectoryName: "GoldenApple"
        )
    }()
}
