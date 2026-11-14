import Foundation

/// A parsed `keys` value: zero or more modifiers plus exactly one key, e.g. `cmd+shift+p`,
/// `1`, `f5`, `space`. Case-insensitive; spaces around `+` are ignored.
public struct KeyCombo: Equatable, Sendable {
    public enum Modifier: Hashable, Sendable {
        case command, shift, option, control
    }

    public enum Key: Equatable, Sendable {
        /// `a`–`z`
        case letter(Character)
        /// `0`–`9`
        case digit(Int)
        /// `f1`–`f20`
        case function(Int)
        /// One of ``KeyCombo/punctuation``.
        case punctuation(Character)
        case space, `return`, tab, escape, delete, up, down, left, right
    }

    public static let punctuation: Set<Character> = [
        "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`",
    ]

    public let modifiers: Set<Modifier>
    public let key: Key

    private static let modifierNames: [String: Modifier] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "alt": .option, "opt": .option, "option": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
    ]

    private static let namedKeys: [String: Key] = [
        "space": .space, "return": .return, "enter": .return, "tab": .tab, "esc": .escape,
        "escape": .escape, "delete": .delete, "backspace": .delete, "up": .up, "down": .down,
        "left": .left, "right": .right,
    ]

    public static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !parts.contains(where: \.isEmpty) else { return nil }
        var modifiers: Set<Modifier> = []
        for name in parts.dropLast() {
            guard let modifier = modifierNames[name] else { return nil }
            modifiers.insert(modifier)
        }
        guard let key = key(named: last) else { return nil }
        return KeyCombo(modifiers: modifiers, key: key)
    }

    private static func key(named name: String) -> Key? {
        if let named = namedKeys[name] { return named }
        if name.count == 1, let char = name.first {
            if char.isASCII, char.isLetter { return .letter(char) }
            if let digit = char.wholeNumberValue, char.isASCII { return .digit(digit) }
            if punctuation.contains(char) { return .punctuation(char) }
            return nil
        }
        if name.hasPrefix("f"), let number = Int(name.dropFirst()), (1...20).contains(number) {
            return .function(number)
        }
        return nil
    }
}
