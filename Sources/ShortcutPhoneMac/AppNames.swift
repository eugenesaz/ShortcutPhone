import AppKit

/// Display names of installed apps by bundle ID ("Mail" for `com.apple.mail`). Found names are
/// cached; misses aren't, so an app installed later gets its name.
public final class AppNames: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    public init() {}

    public func name(for bundleId: String) -> String? {
        if let cached = lock.withLock({ cache[bundleId] }) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return nil }
        let display = FileManager.default.displayName(atPath: url.path)
        let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        lock.withLock { cache[bundleId] = name }
        return name
    }
}
