import AppKit

/// Saves and restores the full contents of a pasteboard (every item, every type) around a paste.
@MainActor
public final class Pasteboard {
    public struct Snapshot: Sendable {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private let board: NSPasteboard

    /// Tests pass a uniquely named pasteboard; the app uses `.general`.
    public init(_ board: NSPasteboard = .general) {
        self.board = board
    }

    public var changeCount: Int { board.changeCount }

    public func snapshot() -> Snapshot {
        let items = (board.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
        return Snapshot(items: items)
    }

    /// Replaces the contents with a plain string. Returns the change count after writing.
    @discardableResult
    public func write(_ text: String) -> Int {
        board.clearContents()
        board.setString(text, forType: .string)
        return board.changeCount
    }

    /// Restores a snapshot, unless something else wrote to the pasteboard after
    /// `expectedChangeCount` (then the newer contents win and nothing is touched).
    public func restore(_ snapshot: Snapshot, ifChangeCountIs expectedChangeCount: Int) {
        guard board.changeCount == expectedChangeCount else { return }
        board.clearContents()
        let items = snapshot.items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
    }
}
