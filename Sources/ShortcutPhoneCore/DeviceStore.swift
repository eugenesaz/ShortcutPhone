import Foundation

public protocol DeviceStore: Sendable {
    func load() throws -> [Device]
    func save(_ devices: [Device]) throws
}

/// `devices.json`, written atomically and readable only by the user.
public struct DeviceFileStore: DeviceStore {
    public let url: URL

    public init(url: URL = ConfigFile.directory.appendingPathComponent("devices.json")) {
        self.url = url
    }

    public func load() throws -> [Device] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.decoder.decode([Device].self, from: Data(contentsOf: url))
    }

    public func save(_ devices: [Device]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(devices).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
