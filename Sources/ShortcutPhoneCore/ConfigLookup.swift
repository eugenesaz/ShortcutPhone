/// Where a button lives. Page buttons only run while their app is frontmost.
public enum ButtonOwner: Equatable, Sendable {
    case global
    case page(bundleId: String)
}

extension Config {
    public func lookup(_ buttonId: String) -> (button: Button, owner: ButtonOwner)? {
        if let button = global.first(where: { $0.id == buttonId }) {
            return (button, .global)
        }
        for page in pages {
            for button in page.buttons {
                if button.id == buttonId { return (button, .page(bundleId: page.bundleId)) }
                if let inner = button.folder?.buttons.first(where: { $0.id == buttonId }) {
                    return (inner, .page(bundleId: page.bundleId))
                }
            }
        }
        return nil
    }

    public func page(for bundleId: String) -> Page? {
        pages.first { $0.bundleId == bundleId }
    }
}
