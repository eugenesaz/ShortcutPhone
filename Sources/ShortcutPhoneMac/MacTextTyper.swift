import Foundation
import ShortcutPhoneCore

/// Types by pasting (save the clipboard, write the text, ⌘V, Return, restore the clipboard)
/// and sends key combos. Never logs the text.
public struct MacTextTyper: TextTyper {
    /// Gap between ⌘V and Return. Electron apps (Slack, VS Code, T3 Code) insert pasted text
    /// asynchronously; without a gap, Return can send the message before the text lands.
    public static let defaultReturnDelay = Duration.milliseconds(60)
    /// How long the target app gets to read the pasteboard before it is restored.
    public static let defaultRestoreDelay = Duration.milliseconds(300)

    private let keys: any KeyPosting
    private let pasteboard: @MainActor @Sendable () -> Pasteboard
    private let returnDelay: Duration
    private let restoreDelay: Duration

    public init(
        keys: any KeyPosting = KeyInjector(),
        pasteboard: @escaping @MainActor @Sendable () -> Pasteboard = { Pasteboard() },
        returnDelay: Duration = defaultReturnDelay, restoreDelay: Duration = defaultRestoreDelay
    ) {
        self.keys = keys
        self.pasteboard = pasteboard
        self.returnDelay = returnDelay
        self.restoreDelay = restoreDelay
    }

    public func pasteAndReturn(_ text: String) async throws(ActionError) {
        let (saved, written) = await MainActor.run {
            let board = pasteboard()
            let saved = board.snapshot()
            return (saved, board.write(text))
        }
        keys.pressCommandV()
        try? await Task.sleep(for: returnDelay)
        keys.pressReturn()
        try? await Task.sleep(for: restoreDelay)
        await MainActor.run { pasteboard().restore(saved, ifChangeCountIs: written) }
    }

    public func send(_ text: String) async throws(ActionError) {
        // Configs are validated on load, so an unparseable combo can't normally get here.
        guard let combo = KeyCombo.parse(text), let code = KeyCodes.keyCode(for: combo.key) else {
            throw .unknownButton(id: text)
        }
        keys.tap(keyCode: code, flags: KeyCodes.flags(for: combo.modifiers))
    }
}
