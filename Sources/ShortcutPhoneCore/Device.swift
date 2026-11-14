import Foundation

/// A paired phone. Only the SHA-256 hash of its token is kept.
public struct Device: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public var name: String
    /// Hex SHA-256 of the device token.
    public let tokenHash: String
    public let pairedAt: Date
    /// Last reported screen layout, used for capacity.
    public var viewport: Viewport?

    public init(id: String, name: String, tokenHash: String, pairedAt: Date, viewport: Viewport?) {
        self.id = id
        self.name = name
        self.tokenHash = tokenHash
        self.pairedAt = pairedAt
        self.viewport = viewport
    }
}
