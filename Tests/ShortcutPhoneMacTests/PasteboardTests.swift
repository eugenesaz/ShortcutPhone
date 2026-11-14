import AppKit
import Testing

@testable import ShortcutPhoneMac

/// Uses a uniquely named pasteboard, never the real one.
@MainActor
@Suite struct PasteboardTests {
    let board = NSPasteboard(name: .init("ShortcutPhoneTests-\(UUID().uuidString)"))

    @Test func restoresEveryItemAndType() {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("rich", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .init("com.example.custom"))
        board.writeObjects([item])

        let pasteboard = Pasteboard(board)
        let saved = pasteboard.snapshot()
        let written = pasteboard.write("Привет 👋")
        #expect(board.string(forType: .string) == "Привет 👋")

        pasteboard.restore(saved, ifChangeCountIs: written)
        #expect(board.string(forType: .string) == "rich")
        #expect(board.data(forType: .init("com.example.custom")) == Data([1, 2, 3]))
        board.releaseGlobally()
    }

    @Test func doesNotClobberNewerContents() {
        let pasteboard = Pasteboard(board)
        board.clearContents()
        board.setString("old", forType: .string)
        let saved = pasteboard.snapshot()
        let written = pasteboard.write("pasted")

        board.clearContents()
        board.setString("copied by the user meanwhile", forType: .string)
        pasteboard.restore(saved, ifChangeCountIs: written)
        #expect(board.string(forType: .string) == "copied by the user meanwhile")
        board.releaseGlobally()
    }

    @Test func restoresAnEmptyPasteboard() {
        board.clearContents()
        let pasteboard = Pasteboard(board)
        let saved = pasteboard.snapshot()
        let written = pasteboard.write("x")
        pasteboard.restore(saved, ifChangeCountIs: written)
        #expect(board.string(forType: .string) == nil)
        board.releaseGlobally()
    }
}
