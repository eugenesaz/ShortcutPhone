import Carbon.HIToolbox
import CoreGraphics

/// Something that can press a key. `KeyInjector` in the app, a recorder in tests.
public protocol KeyPosting: Sendable {
    func tap(keyCode: CGKeyCode, flags: CGEventFlags)
}

extension KeyPosting {
    func pressCommandV() { tap(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand) }
    func pressReturn() { tap(keyCode: CGKeyCode(kVK_Return), flags: []) }
}

/// Posts synthetic keystrokes through the HID event tap (the lowest level available to apps,
/// so games that read input below the window server still see them).
/// Requires the Accessibility permission; without it macOS drops the events silently.
public struct KeyInjector: KeyPosting {
    public init() {}

    /// Presses and releases one key with the given modifiers.
    public func tap(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard
                let event = CGEvent(
                    keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
