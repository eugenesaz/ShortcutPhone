import Foundation

/// The user's buttons and pages (`config.json`, schema version 1).
public struct Config: Equatable, Sendable, Codable {
    public static let currentVersion = 1
    public static let defaultPort = 8765

    public struct Server: Equatable, Sendable, Codable {
        public var port: Int

        public init(port: Int) {
            self.port = port
        }
    }

    public var version: Int
    public var server: Server
    public var global: [Button]
    public var pages: [Page]

    public init(
        version: Int = Config.currentVersion, server: Server = Server(port: Config.defaultPort),
        global: [Button] = [], pages: [Page] = []
    ) {
        self.version = version
        self.server = server
        self.global = global
        self.pages = pages
    }

    public static let empty = Config()

    /// Decodes and validates. Every problem comes back as a field-level issue.
    public static func decode(_ data: Data) throws(ConfigError) -> Config {
        let decoder = JSONDecoder()
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw ConfigError([issue(from: error)])
        }
        guard probe.version == currentVersion else {
            throw ConfigError([
                ConfigIssue(
                    path: "version",
                    message: "unsupported version \(probe.version); expected \(currentVersion)")
            ])
        }
        let config: Config
        do {
            config = try decoder.decode(Config.self, from: data)
        } catch {
            throw ConfigError([issue(from: error)])
        }
        let issues = ConfigValidator.issues(in: config)
        guard issues.isEmpty else { throw ConfigError(issues) }
        return config
    }

    /// Pretty-printed, stable key order, for writing to disk.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private static func issue(from error: any Error) -> ConfigIssue {
        guard let error = error as? DecodingError else {
            return ConfigIssue(path: "", message: "invalid JSON")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return ConfigIssue(
                path: FieldPath.string(context.codingPath + [key]), message: "is required")
        case .typeMismatch(let type, let context):
            return ConfigIssue(
                path: FieldPath.string(context.codingPath), message: "must be \(type)")
        case .valueNotFound(let type, let context):
            return ConfigIssue(
                path: FieldPath.string(context.codingPath), message: "must be \(type)")
        case .dataCorrupted(let context):
            let path = FieldPath.string(context.codingPath)
            return ConfigIssue(
                path: path, message: path.isEmpty ? "invalid JSON" : "has an invalid value")
        @unknown default:
            return ConfigIssue(path: "", message: "invalid config")
        }
    }
}

/// Formats coding paths as `pages[0].buttons[1].keys`.
enum FieldPath {
    static func string(_ path: [any CodingKey]) -> String {
        path.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}
