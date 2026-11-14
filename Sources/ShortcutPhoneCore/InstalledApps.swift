/// An app the editor can pick for a page or an `app` button.
public struct InstalledApp: Equatable, Sendable, Codable {
    public let bundleId: String
    public let name: String
    public let path: String
    public let running: Bool

    public init(bundleId: String, name: String, path: String, running: Bool) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
        self.running = running
    }
}

/// Lists installed and running apps, for `GET /api/apps`.
public protocol InstalledAppsProvider: Sendable {
    func apps() async -> [InstalledApp]
}
