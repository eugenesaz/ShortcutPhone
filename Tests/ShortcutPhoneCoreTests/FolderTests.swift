import Foundation
import Testing

@testable import ShortcutPhoneCore

@Suite struct FolderTests {
    static let wow = "com.blizzard.worldofwarcraft"

    static func text(_ id: String) -> Button {
        Button(id: id, label: id, action: .text("/\(id)"))
    }

    static func folder(
        _ buttons: [Button], id: String = "f", label: String? = "Social",
        afterPress: AfterPress = .back, columns: Int? = nil
    ) -> Button {
        Button(
            id: id, label: label,
            action: .folder(Folder(afterPress: afterPress, columns: columns, buttons: buttons)))
    }

    static func config(_ buttons: [Button], global: [Button] = []) -> Config {
        Config(global: global, pages: [Page(bundleId: wow, buttons: buttons)])
    }

    /// Field paths of every problem `Config.decode` reports.
    static func paths(_ config: Config) throws -> [String] {
        let data = try config.encoded()
        do {
            _ = try Config.decode(data)
            return []
        } catch {
            return error.issues.map(\.path)
        }
    }

    // MARK: JSON

    @Test func decodesTheJSONShape() throws {
        let json = #"""
            {"version":1,"server":{"port":8765},"global":[],"pages":[{"bundleId":"com.example.app",
              "columns":null,"buttons":[{"id":"f","type":"folder","label":"Social","emoji":"💬",
              "afterPress":"stay","columns":3,"buttons":[
                {"id":"t","type":"text","label":"Dance","text":"/dance"}]}]}]}
            """#
        let config = try Config.decode(Data(json.utf8))
        let button = config.pages[0].buttons[0]
        #expect(button.emoji == "💬")
        #expect(
            button.folder
                == Folder(
                    afterPress: .stay, columns: 3,
                    buttons: [Button(id: "t", label: "Dance", action: .text("/dance"))]))
    }

    @Test func afterPressDefaultsToBackAndColumnsToAuto() throws {
        let json = #"""
            {"version":1,"server":{"port":8765},"global":[],"pages":[{"bundleId":"com.example.app",
              "columns":null,"buttons":[{"id":"f","type":"folder","label":"F","buttons":[]}]}]}
            """#
        let folder = try #require(try Config.decode(Data(json.utf8)).pages[0].buttons[0].folder)
        #expect(folder == Folder(afterPress: .back, columns: nil, buttons: []))
    }

    @Test func roundTripsWithExplicitFields() throws {
        let config = Self.config([Self.folder([Self.text("a")], afterPress: .stay)])
        let data = try config.encoded()
        #expect(try Config.decode(data) == config)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""afterPress" : "stay""#))
        #expect(json.contains(#""type" : "folder""#))
    }

    @Test func rejectsUnknownAfterPress() throws {
        let json = #"""
            {"version":1,"server":{"port":8765},"global":[],"pages":[{"bundleId":"com.example.app",
              "columns":null,"buttons":[{"id":"f","type":"folder","label":"F","afterPress":"later",
              "buttons":[]}]}]}
            """#
        #expect(throws: ConfigError.self) { try Config.decode(Data(json.utf8)) }
    }

    // MARK: Validation

    @Test func validFolderHasNoIssues() throws {
        #expect(
            try Self.paths(Self.config([Self.folder([Self.text("a"), Self.text("b")])])).isEmpty)
    }

    @Test func emptyFolderIsAllowed() throws {
        #expect(try Self.paths(Self.config([Self.folder([])])).isEmpty)
    }

    @Test func notAllowedInTheGlobalStrip() throws {
        let config = Config(global: [Self.folder([])])
        #expect(try Self.paths(config) == ["global[0].type"])
    }

    @Test func foldersCannotNest() throws {
        let config = Self.config([Self.folder([Self.folder([], id: "g")])])
        #expect(try Self.paths(config) == ["pages[0].buttons[0].buttons[0].type"])
    }

    @Test func needsALabelOrEmoji() throws {
        let config = Self.config([Self.folder([], label: nil)])
        #expect(try Self.paths(config) == ["pages[0].buttons[0].label"])
    }

    @Test(arguments: [0, 9])
    func rejectsColumnsOutOfRange(_ columns: Int) throws {
        let config = Self.config([Self.folder([], columns: columns)])
        #expect(try Self.paths(config).contains("pages[0].buttons[0].columns"))
    }

    @Test func checksButtonsInside() throws {
        let bad = Button(id: "k", label: "K", action: .keys("not a combo"))
        let config = Self.config([Self.folder([Self.text("a"), bad])])
        #expect(try Self.paths(config) == ["pages[0].buttons[0].buttons[1].keys"])
    }

    @Test func idsMustBeUniqueAcrossFolders() throws {
        let config = Self.config([Self.text("a"), Self.folder([Self.text("a")])])
        #expect(try Self.paths(config) == ["pages[0].buttons[1].buttons[0].id"])
    }

    // MARK: Capacity

    @Test func folderHoldsPageCapacityMinusTheBackTile() throws {
        let capacity = EffectiveCapacity(viewports: [])
        let page = try #require(capacity.page(columns: nil))
        #expect(capacity.folder(columns: nil) == page - 1)
        #expect(capacity.folder(columns: 3) == capacity.page(columns: 3).map { $0 - 1 })
        #expect(capacity.folder(columns: 8) == nil)  // too narrow on a Pixel 5
    }

    @Test func fullFolderPassesOneMoreFails() throws {
        let capacity = EffectiveCapacity(viewports: [])
        let max = try #require(capacity.folder(columns: nil))
        let full = Self.config([Self.folder((0..<max).map { Self.text("b\($0)") })])
        #expect(capacity.issues(in: full).isEmpty)
        let over = Self.config([Self.folder((0...max).map { Self.text("b\($0)") })])
        #expect(capacity.issues(in: over).map(\.path) == ["pages[0].buttons[0].buttons"])
    }

    @Test func folderColumnsThatDoNotFitAreReported() {
        let capacity = EffectiveCapacity(viewports: [])
        let config = Self.config([Self.folder([], columns: 8)])
        #expect(capacity.issues(in: config).map(\.path) == ["pages[0].buttons[0].columns"])
    }

    @Test func folderCountsAsOneButtonOnItsPage() {
        let capacity = EffectiveCapacity(viewports: [])
        let config = Self.config([Self.folder((0..<20).map { Self.text("b\($0)") })])
        #expect(capacity.issues(in: config).isEmpty)
    }

    // MARK: Lookup, state and presses

    @Test func lookupFindsButtonsInFoldersWithThePageAsOwner() throws {
        let config = Self.config([Self.folder([Self.text("a")])])
        let found = try #require(config.lookup("a"))
        #expect(found.button == Self.text("a"))
        #expect(found.owner == .page(bundleId: Self.wow))
    }

    @Test func stateNamesAppButtonsInsideFolders() {
        let app = Button(id: "a", action: .app(bundleId: "com.apple.Safari"))
        let config = Self.config([Self.folder([app])])
        let state = config.state(
            frontmost: AppRef(bundleId: Self.wow, name: "WoW"), appName: { _ in "Safari" })
        #expect(state.page?.buttons[0].folder?.buttons[0].label == "Safari")
    }

    @Test func pressInFolderRunsWithFocusGuard() async throws {
        let config = Self.config([Self.folder([Self.text("dance")])])
        let os = FakeOS(frontmost: AppRef(bundleId: Self.wow, name: "WoW"))
        let dispatcher = PressDispatcher(launcher: os, typer: os, accessibility: os, frontmost: os)
        try await dispatcher.handle(buttonId: "dance", config: config)
        #expect(await os.calls == [.paste("/dance")])

        await os.set(frontmost: AppRef(bundleId: "com.apple.Safari", name: "Safari"))
        await #expect(throws: ActionError.wrongApp(expected: Self.wow, actual: "com.apple.Safari"))
        {
            try await dispatcher.handle(buttonId: "dance", config: config)
        }
    }

    @Test func pressingTheFolderItselfIsUnknown() async {
        let config = Self.config([Self.folder([])])
        let os = FakeOS(frontmost: AppRef(bundleId: Self.wow, name: "WoW"))
        let dispatcher = PressDispatcher(launcher: os, typer: os, accessibility: os, frontmost: os)
        await #expect(throws: ActionError.unknownButton(id: "f")) {
            try await dispatcher.handle(buttonId: "f", config: config)
        }
        #expect(await os.calls.isEmpty)
    }
}
