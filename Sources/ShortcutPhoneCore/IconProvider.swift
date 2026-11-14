import Foundation

/// App icons as PNG, for `GET /icons/<bundleId>.png`.
public protocol IconProvider: Sendable {
    /// `nil` when no app with that bundle ID is installed.
    func pngIcon(bundleId: String, size: Int) async -> Data?
}
