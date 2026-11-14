import AppKit
import ShortcutPhoneCore

/// Launch or switch via NSWorkspace. For a running app this activates it and sends a reopen
/// event, which restores a window if none is visible.
public struct WorkspaceAppLauncher: AppLauncher {
    public init() {}

    public func launchOrActivate(bundleId: String) async throws(ActionError) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw .launchFailed(bundleId: bundleId)
        }
        await MainActor.run {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            where app.isHidden {
                app.unhide()
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw .launchFailed(bundleId: bundleId)
        }
    }

    public func open(url: String, inApp bundleId: String) async throws(ActionError) {
        guard let target = URL(string: url),
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { throw .openFailed(url: url) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(
                [target], withApplicationAt: app, configuration: configuration)
        } catch {
            throw .openFailed(url: url)
        }
    }
}
