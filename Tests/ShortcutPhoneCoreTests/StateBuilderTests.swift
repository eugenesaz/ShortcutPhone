import Testing

@testable import ShortcutPhoneCore

@Suite struct StateBuilderTests {
    let config: Config

    init() throws {
        config = try Config.decode(Fixtures.data("config/spec-example.json"))
    }

    @Test func frontmostAppWithPageGetsThatPage() {
        let slack = AppRef(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")
        let state = config.state(frontmost: slack)
        #expect(state.frontmost == slack)
        #expect(state.global == config.global)
        #expect(state.page?.bundleId == "com.tinyspeck.slackmacgap")
    }

    @Test func frontmostAppWithoutPageGetsNoPage() {
        let state = config.state(frontmost: AppRef(bundleId: "com.apple.finder", name: "Finder"))
        #expect(state.page == nil)
        #expect(state.global.count == 2)
    }

    /// The phone has no app list, so the agent names unlabeled app buttons.
    @Test func unlabeledAppButtonsGetTheAppName() {
        let names = ["com.apple.Safari": "Safari Browser", "com.tinyspeck.slackmacgap": "Slack"]
        let config = Config(global: [
            Button(id: "a", action: .app(bundleId: "com.apple.Safari")),
            Button(id: "b", label: "Chat", action: .app(bundleId: "com.tinyspeck.slackmacgap")),
            Button(id: "c", action: .app(bundleId: "com.example.unknown")),
        ])
        let state = config.state(frontmost: nil, appName: { names[$0] })
        #expect(state.global.map(\.label) == ["Safari Browser", "Chat", nil])
    }

    @Test func pageAppButtonsGetTheAppNameToo() {
        let notes = AppRef(bundleId: "com.apple.Notes", name: "Notes")
        let config = Config(pages: [
            Page(
                bundleId: "com.apple.Notes",
                buttons: [
                    Button(id: "p", action: .app(bundleId: "com.apple.Safari")),
                    Button(id: "t", emoji: "👋", action: .text("hi")),
                ])
        ])
        let state = config.state(frontmost: notes, appName: { _ in "Safari" })
        #expect(state.page?.buttons.map(\.label) == ["Safari", nil])
    }

    @Test func noFrontmostApp() {
        let state = config.state(frontmost: nil)
        #expect(state.frontmost == nil)
        #expect(state.page == nil)
    }
}

@Suite struct PinnedStripTests {
    static func app(_ id: String, pinned: Bool = false) -> Button {
        Button(id: id, pinned: pinned, action: .app(bundleId: "com.example.\(id)"))
    }

    @Test func pinnedAppsComeFirstOtherwiseConfigOrder() {
        let config = Config(global: [
            Self.app("a"), Self.app("b", pinned: true), Self.app("c"), Self.app("d", pinned: true),
        ])
        #expect(config.state(frontmost: nil).global.map(\.id) == ["b", "d", "a", "c"])
    }

    @Test func pinnedIsWrittenOnlyWhenTrue() throws {
        let config = Config(global: [Self.app("a"), Self.app("b", pinned: true)])
        let json = String(decoding: try config.encoded(), as: UTF8.self)
        #expect(json.components(separatedBy: "\"pinned\"").count == 2)
        #expect(try Config.decode(config.encoded()) == config)
    }
}
