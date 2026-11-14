import AppKit
import ApplicationServices
import ShortcutPhoneCore

/// Whether this process may post synthetic input events.
public enum AccessibilityStatus {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security > Accessibility.
    /// Opens Privacy & Security › Accessibility, where the user can switch ShortcutPhone on.
    @MainActor
    public static func openSettings() {
        requestTrust()  // adds ShortcutPhone to the list so the user only has to tick it
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    @discardableResult
    public static func requestTrust() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// `AccessibilityChecker` backed by `AXIsProcessTrusted`.
public struct SystemAccessibility: AccessibilityChecker {
    public init() {}

    public func isTrusted() async -> Bool { AccessibilityStatus.isTrusted }
}
