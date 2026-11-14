import Foundation
import Testing

@testable import ShortcutPhoneCore

@Suite struct KeyComboTests {
    @Test func parsesModifiersAndLetter() throws {
        let combo = try #require(KeyCombo.parse("cmd+shift+p"))
        #expect(combo.modifiers == [.command, .shift])
        #expect(combo.key == .letter("p"))
    }

    @Test(arguments: [
        ("1", KeyCombo.Key.digit(1)), ("0", .digit(0)), ("f5", .function(5)),
        ("F20", .function(20)),
        ("space", .space), ("return", .return), ("enter", .return), ("tab", .tab), ("esc", .escape),
        ("escape", .escape), ("delete", .delete), ("backspace", .delete), ("up", .up),
        ("down", .down), ("left", .left), ("right", .right), ("K", .letter("k")),
    ])
    func parsesSingleKeys(_ text: String, _ key: KeyCombo.Key) throws {
        let combo = try #require(KeyCombo.parse(text))
        #expect(combo.modifiers.isEmpty)
        #expect(combo.key == key)
    }

    @Test(arguments: ["-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`"])
    func parsesPunctuation(_ text: String) throws {
        #expect(try #require(KeyCombo.parse("cmd+\(text)")).key == .punctuation(Character(text)))
    }

    @Test(arguments: [
        ("command+a", KeyCombo.Modifier.command), ("⌘+a", .command), ("alt+a", .option),
        ("option+a", .option), ("opt+a", .option), ("ctrl+a", .control), ("control+a", .control),
        ("shift+a", .shift),
    ])
    func acceptsModifierAliases(_ text: String, _ modifier: KeyCombo.Modifier) throws {
        #expect(try #require(KeyCombo.parse(text)).modifiers == [modifier])
    }

    @Test func toleratesSpacesAndCase() throws {
        let combo = try #require(KeyCombo.parse(" Cmd + Shift + P "))
        #expect(combo.modifiers == [.command, .shift])
        #expect(combo.key == .letter("p"))
    }

    @Test(arguments: [
        "", " ", "cmd", "cmd+shift", "cmd+a+b", "f0", "f21", "hyper+a", "cmd++", "a+cmd", "ab",
        "cmd+", "+a", "é",
    ])
    func rejectsInvalid(_ text: String) {
        #expect(KeyCombo.parse(text) == nil)
    }

    @Test func configValidationRejectsUnparseableKeys() throws {
        let config = Config(pages: [
            Page(
                bundleId: "com.example.app",
                buttons: [Button(id: "k", label: "x", action: .keys("cmd+nope"))])
        ])
        let data = try config.encoded()
        #expect(throws: ConfigError.self) { try Config.decode(data) }
        do {
            _ = try Config.decode(data)
        } catch {
            #expect(error.issues.map(\.path) == ["pages[0].buttons[0].keys"])
        }
    }
}

/// The same strings drive web/tests/key-combo.test.ts, so the editor agrees with the agent.
@Suite struct KeyComboFixtureTests {
    struct Cases: Decodable {
        let valid: [String]
        let invalid: [String]
    }

    static let cases = try? JSONDecoder().decode(
        Cases.self, from: Fixtures.data("keycombos.json"))

    @Test func fixtureLoads() {
        #expect(Self.cases != nil)
    }

    @Test(arguments: cases?.valid ?? [])
    func fixtureValidParses(_ text: String) {
        #expect(KeyCombo.parse(text) != nil)
    }

    @Test(arguments: cases?.invalid ?? [])
    func fixtureInvalidIsRejected(_ text: String) {
        #expect(KeyCombo.parse(text) == nil)
    }
}
