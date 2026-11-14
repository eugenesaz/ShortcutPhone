extension Config {
    /// What the phone should show while `frontmost` is the active app.
    /// - Parameter appName: Display name for a bundle ID. App buttons without a label get it, since
    ///   the phone has no app list of its own and would otherwise show part of the bundle ID.
    public func state(
        frontmost: AppRef?, appName: (String) -> String? = { _ in nil }
    ) -> StateMessage {
        var shown: Page?
        if let bundleId = frontmost?.bundleId, var found = page(for: bundleId) {
            found.buttons = Self.named(found.buttons, appName)
            shown = found
        }
        return StateMessage(
            frontmost: frontmost, global: Self.named(stripOrder, appName), page: shown)
    }

    /// Gives unlabeled app buttons, including those in folders, the app's display name.
    private static func named(
        _ buttons: [Button], _ appName: (String) -> String?
    ) -> [Button] {
        buttons.map { button in
            var result = button
            switch button.action {
            case .app(let bundleId) where button.label == nil:
                result.label = appName(bundleId)
            case .folder(var folder):
                folder.buttons = named(folder.buttons, appName)
                result.action = .folder(folder)
            default:
                break
            }
            return result
        }
    }

    /// Global buttons as the strip shows them: pinned first, otherwise in config order.
    public var stripOrder: [Button] {
        global.filter(\.pinned) + global.filter { !$0.pinned }
    }
}
