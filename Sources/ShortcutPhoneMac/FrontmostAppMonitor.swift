import AppKit
import ShortcutPhoneCore

/// Reports the frontmost app using NSWorkspace activation notifications (no polling).
/// ShortcutPhone's own activations (e.g. opening its menu) are ignored.
public struct FrontmostAppMonitor: FrontmostAppProvider {
    public init() {}

    public func current() async -> AppRef? {
        await MainActor.run { Self.frontmost() }
    }

    /// The current frontmost app, then one element per change.
    @MainActor
    public func changes() -> AsyncStream<AppRef?> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let app =
                    note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let app, !Self.isSelf(app) else { return }
                continuation.yield(Self.ref(app))
            }
            nonisolated(unsafe) let observer = token
            continuation.onTermination = { _ in center.removeObserver(observer) }
            continuation.yield(Self.frontmost())
        }
    }

    @MainActor
    private static func frontmost() -> AppRef? {
        guard let app = NSWorkspace.shared.frontmostApplication, !isSelf(app) else { return nil }
        return ref(app)
    }

    private static func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private static func ref(_ app: NSRunningApplication) -> AppRef? {
        guard let bundleId = app.bundleIdentifier else { return nil }
        return AppRef(bundleId: bundleId, name: app.localizedName ?? bundleId)
    }
}
