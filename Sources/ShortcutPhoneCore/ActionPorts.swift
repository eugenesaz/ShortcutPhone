// OS side effects the dispatcher needs. Implemented in ShortcutPhoneMac, faked in tests.

public protocol AppLauncher: Sendable {
    /// Launches the app if needed, otherwise activates it (restoring a window if none is visible).
    func launchOrActivate(bundleId: String) async throws(ActionError)
    /// Opens `url` with the app `bundleId` (a browser: a new tab) and brings it to the front.
    func open(url: String, inApp bundleId: String) async throws(ActionError)
}

public protocol TextTyper: Sendable {
    /// Pastes `text` into the frontmost app, presses Return, then restores the clipboard.
    func pasteAndReturn(_ text: String) async throws(ActionError)
    /// Sends one key combo, e.g. `cmd+shift+p` or `1`.
    func send(_ keys: String) async throws(ActionError)
}

public protocol AccessibilityChecker: Sendable {
    /// Whether macOS lets this app post keystrokes.
    func isTrusted() async -> Bool
}
