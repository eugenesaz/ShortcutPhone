import Foundation
import Testing

@testable import ShortcutPhoneCore

@Suite struct ConfigDecodeTests {
    @Test func decodesSpecExample() throws {
        let config = try Config.decode(Fixtures.data("config/spec-example.json"))
        #expect(config.version == 1)
        #expect(config.server.port == 8765)
        #expect(config.global.count == 2)
        #expect(config.global[0].action == .app(bundleId: "com.apple.Safari"))
        #expect(config.global[1].color == "#4A154B")
        let page = try #require(config.pages.first)
        #expect(page.bundleId == "com.tinyspeck.slackmacgap")
        #expect(page.columns == nil)
        #expect(page.buttons[0].action == .text("LGTM, merging."))
        #expect(page.buttons[0].label == "LGTM")
        #expect(page.buttons[0].emoji == "👍")
        #expect(page.buttons[1].action == .keys("cmd+k"))
    }

    @Test func roundTripsThroughJSON() throws {
        let config = try Config.decode(Fixtures.data("config/spec-example.json"))
        let again = try Config.decode(config.encoded())
        #expect(again == config)
    }

    @Test func encodesNullColumnsExplicitly() throws {
        let config = try Config.decode(Fixtures.data("config/spec-example.json"))
        let json = try #require(String(data: config.encoded(), encoding: .utf8))
        #expect(json.contains("\"columns\" : null"))
    }

    @Test func emptyConfigIsValid() throws {
        let again = try Config.decode(Config.empty.encoded())
        #expect(again == .empty)
        #expect(Config.empty.server.port == 8765)
    }
}

@Suite struct ConfigValidationTests {
    /// Decodes a config built from the spec example after `edit` changes its JSON object.
    func issues(_ edit: (inout [String: Any]) -> Void) throws -> [ConfigIssue] {
        let data = try Fixtures.data("config/spec-example.json")
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        let edited = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try Config.decode(edited)
            return []
        } catch {
            return error.issues
        }
    }

    func page(_ object: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var pages = object["pages"] as! [[String: Any]]
        change(&pages[0])
        object["pages"] = pages
    }

    func pageButton(
        _ object: inout [String: Any], _ index: Int, _ change: (inout [String: Any]) -> Void
    ) {
        page(&object) { page in
            var buttons = page["buttons"] as! [[String: Any]]
            change(&buttons[index])
            page["buttons"] = buttons
        }
    }

    @Test func rejectsUnknownVersion() throws {
        let found = try issues { $0["version"] = 2 }
        #expect(
            found == [ConfigIssue(path: "version", message: "unsupported version 2; expected 1")])
    }

    @Test func rejectsNotJSON() {
        #expect(throws: ConfigError.self) { try Config.decode(Data("nope".utf8)) }
    }

    @Test func reportsMissingFieldWithPath() throws {
        let found = try issues { o in pageButton(&o, 1) { $0["keys"] = nil } }
        #expect(found.map(\.path) == ["pages[0].buttons[1].keys"])
    }

    @Test func reportsUnknownButtonType() throws {
        let found = try issues { o in pageButton(&o, 0) { $0["type"] = "shell" } }
        #expect(found.map(\.path) == ["pages[0].buttons[0].type"])
    }

    @Test func reportsWrongValueType() throws {
        let found = try issues { $0["server"] = ["port": "eighty"] }
        #expect(found.map(\.path) == ["server.port"])
    }

    @Test func rejectsPortOutOfRange() throws {
        let found = try issues { $0["server"] = ["port": 70000] }
        #expect(found.map(\.path) == ["server.port"])
    }

    @Test func rejectsDuplicateButtonIDs() throws {
        let found = try issues { o in pageButton(&o, 1) { $0["id"] = "btn_1" } }
        #expect(
            found == [ConfigIssue(path: "pages[0].buttons[1].id", message: "duplicate id btn_1")])
    }

    @Test func rejectsEmptyID() throws {
        let found = try issues { o in pageButton(&o, 0) { $0["id"] = "" } }
        #expect(found.map(\.path) == ["pages[0].buttons[0].id"])
    }

    @Test(arguments: [0, 9, -1])
    func rejectsColumnsOutOfRange(_ columns: Int) throws {
        let found = try issues { o in page(&o) { $0["columns"] = columns } }
        #expect(found.map(\.path) == ["pages[0].columns"])
    }

    @Test(arguments: [1, 8])
    func acceptsColumnsInRange(_ columns: Int) throws {
        #expect(try issues { o in page(&o) { $0["columns"] = columns } } == [])
    }

    @Test func rejectsEmptyText() throws {
        let found = try issues { o in pageButton(&o, 0) { $0["text"] = "" } }
        #expect(found.map(\.path) == ["pages[0].buttons[0].text"])
    }

    @Test func rejectsEmptyKeys() throws {
        let found = try issues { o in pageButton(&o, 1) { $0["keys"] = " " } }
        #expect(found.map(\.path) == ["pages[0].buttons[1].keys"])
    }

    @Test func requiresLabelOrEmojiOnTextAndKeysButtons() throws {
        let found = try issues { o in
            pageButton(&o, 0) {
                $0["label"] = nil
                $0["emoji"] = nil
            }
        }
        #expect(found.map(\.path) == ["pages[0].buttons[0].label"])
    }

    @Test func allowsEmojiOnlyButton() throws {
        #expect(try issues { o in pageButton(&o, 0) { $0["label"] = nil } } == [])
    }

    @Test func rejectsNonAppButtonInGlobalStrip() throws {
        let found = try issues { o in
            var global = o["global"] as! [[String: Any]]
            global[0] = ["id": "g", "type": "text", "label": "x", "text": "hi"]
            o["global"] = global
        }
        #expect(found.map(\.path) == ["global[0].type"])
    }

    @Test(arguments: ["", "not a bundle id", "com.example/evil"])
    func rejectsBadBundleID(_ bundleId: String) throws {
        let found = try issues { o in page(&o) { $0["bundleId"] = bundleId } }
        #expect(found.map(\.path) == ["pages[0].bundleId"])
    }

    @Test func rejectsDuplicatePages() throws {
        let found = try issues { o in
            var pages = o["pages"] as! [[String: Any]]
            var copy = pages[0]
            copy["buttons"] = [[String: Any]]()
            pages.append(copy)
            o["pages"] = pages
        }
        #expect(found.map(\.path) == ["pages[1].bundleId"])
    }

    @Test(arguments: ["red", "#12345", "#GGGGGG", "4A154B"])
    func rejectsBadColor(_ color: String) throws {
        let found = try issues { o in pageButton(&o, 0) { $0["color"] = color } }
        #expect(found.map(\.path) == ["pages[0].buttons[0].color"])
    }

    @Test func acceptsLowercaseColor() throws {
        #expect(try issues { o in pageButton(&o, 0) { $0["color"] = "#4a154b" } } == [])
    }

    @Test func reportsAllIssuesAtOnce() throws {
        let found = try issues { o in
            o["server"] = ["port": 0]
            pageButton(&o, 0) { $0["text"] = "" }
        }
        #expect(found.map(\.path) == ["server.port", "pages[0].buttons[0].text"])
    }
}

@Suite struct ConfigLookupTests {
    let config: Config

    init() throws {
        config = try Config.decode(Fixtures.data("config/spec-example.json"))
    }

    @Test func findsGlobalButton() throws {
        let found = try #require(config.lookup("btn_2"))
        #expect(found.button.id == "btn_2")
        #expect(found.owner == .global)
    }

    @Test func findsPageButtonWithOwner() throws {
        let found = try #require(config.lookup("btn_4"))
        #expect(found.button.action == .keys("cmd+k"))
        #expect(found.owner == .page(bundleId: "com.tinyspeck.slackmacgap"))
    }

    @Test func unknownIDReturnsNil() {
        #expect(config.lookup("btn_404") == nil)
    }

    @Test func findsPageForApp() {
        #expect(config.page(for: "com.tinyspeck.slackmacgap")?.buttons.count == 2)
        #expect(config.page(for: "com.apple.Safari") == nil)
    }
}

@Suite struct UrlButtonTests {
    static func config(_ button: Button, global: Bool = false) -> Config {
        global
            ? Config(global: [button])
            : Config(pages: [Page(bundleId: "com.microsoft.edgemac", buttons: [button])])
    }

    static func paths(_ config: Config) throws -> [String] {
        let data = try config.encoded()
        do {
            _ = try Config.decode(data)
            return []
        } catch {
            return error.issues.map(\.path)
        }
    }

    @Test func roundTrips() throws {
        let config = Self.config(Button(id: "w", action: .url("https://example.com/a?b=c")))
        #expect(try Config.decode(config.encoded()) == config)
    }

    @Test func decodesTheJSONShape() throws {
        let json = #"""
            {"version":1,"server":{"port":8765},"global":[],"pages":[{"bundleId":"com.google.Chrome",
              "columns":null,"buttons":[{"id":"w","type":"url","url":"https://example.com"}]}]}
            """#
        let config = try Config.decode(Data(json.utf8))
        #expect(config.pages[0].buttons[0].action == .url("https://example.com"))
    }

    @Test func noLabelNeeded() throws {
        #expect(
            try Self.paths(Self.config(Button(id: "w", action: .url("https://a.example")))).isEmpty)
    }

    @Test func notAllowedInTheGlobalStrip() throws {
        let button = Button(id: "w", label: "x", action: .url("https://example.com"))
        #expect(try Self.paths(Self.config(button, global: true)) == ["global[0].type"])
    }

    @Test(arguments: ["", "example.com", "ftp://example.com", "javascript:alert(1)", "https://"])
    func rejectsNonWebURLs(_ url: String) throws {
        let button = Button(id: "w", action: .url(url))
        #expect(try Self.paths(Self.config(button)) == ["pages[0].buttons[0].url"])
    }
}
