import Foundation

/// Where the agent keeps its files.
public enum ConfigFile {
    /// `~/Library/Application Support/ShortcutPhone`
    public static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ShortcutPhone", isDirectory: true)
    }

    public static var configURL: URL { directory.appendingPathComponent("config.json") }

    /// Reads the config, or returns `.empty` when the file does not exist yet.
    public static func load(from url: URL = configURL) throws(ConfigError) -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError([ConfigIssue(path: "", message: "cannot read \(url.path)")])
        }
        return try Config.decode(data)
    }
}
