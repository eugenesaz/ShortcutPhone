extension Config {
    /// What the phone should show while `frontmost` is the active app.
    /// - Parameter appName: Display name for a bundle ID. App buttons without a label get it, since
    ///   the phone has no app list of its own and would otherwise show part of the bundle ID.
    public func state(
        frontmost: AppRef?, appName: (String) -> String? = { _ in nil }
    ) -> StateMessage {
        func named(_ buttons: [Button]) -> [Button] {
            buttons.map { button in
                guard button.label == nil, case .app(let bundleId) = button.action else {
                    return button
                }
                var named = button
                named.label = appName(bundleId)
                return named
            }
        }
        let page = frontmost.flatMap { page(for: $0.bundleId) }.map { page in
            var page = page
            page.buttons = named(page.buttons)
            return page
        }
        return StateMessage(frontmost: frontmost, global: named(stripOrder), page: page)
    }

    /// Global buttons as the strip shows them: pinned first, otherwise in config order.
    public var stripOrder: [Button] {
        global.filter(\.pinned) + global.filter { !$0.pinned }
    }
}
