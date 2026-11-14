import AppKit
import Carbon.HIToolbox
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneMac

/// Records key taps, and what the pasteboard held at each one. Never posts real events.
final class RecordingKeys: KeyPosting, @unchecked Sendable {
    struct Tap: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        let clipboard: String?
    }

    private let lock = NSLock()
    private var recorded: [Tap] = []
    nonisolated(unsafe) let board: NSPasteboard

    init(board: NSPasteboard) {
        self.board = board
    }

    var taps: [Tap] { lock.withLock { recorded } }

    func tap(keyCode: CGKeyCode, flags: CGEventFlags) {
        let clipboard = board.string(forType: .string)
        lock.withLock { recorded.append(Tap(keyCode: keyCode, flags: flags, clipboard: clipboard)) }
    }
}

@Suite struct MacTextTyperTests {
    nonisolated(unsafe) let board = NSPasteboard(
        name: .init("ShortcutPhoneTests-\(UUID().uuidString)"))

    func typer(_ keys: RecordingKeys) -> MacTextTyper {
        nonisolated(unsafe) let board = board
        return MacTextTyper(
            keys: keys, pasteboard: { Pasteboard(board) }, returnDelay: .zero,
            restoreDelay: .zero)
    }

    @Test func pastesThenReturnsThenRestores() async throws {
        board.clearContents()
        board.setString("user's clipboard", forType: .string)
        let keys = RecordingKeys(board: board)

        try await typer(keys).pasteAndReturn("Привет 👋")

        #expect(
            keys.taps == [
                .init(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, clipboard: "Привет 👋"),
                .init(keyCode: CGKeyCode(kVK_Return), flags: [], clipboard: "Привет 👋"),
            ])
        #expect(board.string(forType: .string) == "user's clipboard")
        board.releaseGlobally()
    }

    @Test func sendsKeyCombos() async throws {
        let keys = RecordingKeys(board: board)
        let typer = typer(keys)
        try await typer.send("cmd+shift+p")
        try await typer.send("1")
        try await typer.send("f5")
        #expect(
            keys.taps.map(\.keyCode) == [
                CGKeyCode(kVK_ANSI_P), CGKeyCode(kVK_ANSI_1), CGKeyCode(kVK_F5),
            ])
        #expect(keys.taps.map(\.flags) == [[.maskCommand, .maskShift], [], []])
        board.releaseGlobally()
    }
}

@Suite struct KeyCodesTests {
    static let allKeys: [String] =
        (Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
            + (1...20).map { "f\($0)" }
            + ["space", "return", "tab", "esc", "delete", "up", "down", "left", "right"]
            + KeyCombo.punctuation.map(String.init))

    @Test(arguments: allKeys)
    func everyParsableKeyHasACode(_ text: String) throws {
        let combo = try #require(KeyCombo.parse(text))
        #expect(KeyCodes.keyCode(for: combo.key) != nil, "\(text)")
    }

    @Test func codesAreDistinct() {
        let codes = Self.allKeys.compactMap { text in
            KeyCombo.parse(text).flatMap { KeyCodes.keyCode(for: $0.key) }
        }
        #expect(codes.count == Self.allKeys.count)
        #expect(Set(codes).count == codes.count)
    }

    @Test func modifierFlags() {
        #expect(
            KeyCodes.flags(for: [.command, .option, .control, .shift]) == [
                .maskCommand, .maskAlternate, .maskControl, .maskShift,
            ])
    }
}
