import AppKit
import ShortcutPhoneCore

/// Apps in the usual Applications folders plus every running regular app, one per bundle ID,
/// sorted by name.
public struct WorkspaceInstalledApps: InstalledAppsProvider {
    public init() {}

    /// Searched two levels deep, so `Utilities` and vendor folders are covered.
    static let folders: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    public func apps() async -> [InstalledApp] {
        let running = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> InstalledApp? in
                    guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                    return InstalledApp(
                        bundleId: id, name: app.localizedName ?? Self.name(of: url),
                        path: url.path, running: true)
                }
        }
        var byId: [String: InstalledApp] = [:]
        for url in Self.folders.flatMap({ Self.appBundles(in: $0, depth: 2) }) {
            guard let id = Bundle(url: url)?.bundleIdentifier, byId[id] == nil else { continue }
            byId[id] = InstalledApp(
                bundleId: id, name: Self.name(of: url), path: url.path, running: false)
        }
        for app in running { byId[app.bundleId] = app }
        return byId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func appBundles(in folder: URL, depth: Int) -> [URL] {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return items.flatMap { url -> [URL] in
            if url.pathExtension == "app" { return [url] }
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            return depth > 1 && isFolder == true ? appBundles(in: url, depth: depth - 1) : []
        }
    }

    private static func name(of url: URL) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }
}
