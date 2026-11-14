import Foundation
import Testing

@testable import ShortcutPhoneCore

/// Records every OS call instead of making it.
actor FakeOS: AppLauncher, TextTyper, AccessibilityChecker, FrontmostAppProvider {
    enum Call: Equatable {
        case launch(String)
        case paste(String)
        case keys(String)
        case open(String, app: String)
    }

    private(set) var calls: [Call] = []
    var frontmost: AppRef?
    var trusted = true
    var launchFails = false

    init(frontmost: AppRef? = nil) {
        self.frontmost = frontmost
    }

    func set(frontmost: AppRef?) { self.frontmost = frontmost }
    func set(trusted: Bool) { self.trusted = trusted }
    func set(launchFails: Bool) { self.launchFails = launchFails }

    func current() async -> AppRef? { frontmost }
    func isTrusted() async -> Bool { trusted }

    func launchOrActivate(bundleId: String) async throws(ActionError) {
        if launchFails { throw .launchFailed(bundleId: bundleId) }
        calls.append(.launch(bundleId))
    }

    func pasteAndReturn(_ text: String) async throws(ActionError) {
        calls.append(.paste(text))
    }

    func open(url: String, inApp bundleId: String) async throws(ActionError) {
        if launchFails { throw .openFailed(url: url) }
        calls.append(.open(url, app: bundleId))
    }

    func send(_ keys: String) async throws(ActionError) {
        calls.append(.keys(keys))
    }
}

@Suite struct PressDispatcherTests {
    let config: Config
    let slack = AppRef(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")
    let safari = AppRef(bundleId: "com.apple.Safari", name: "Safari")

    init() throws {
        config = try Config.decode(Fixtures.data("config/spec-example.json"))
    }

    func dispatcher(_ os: FakeOS) -> PressDispatcher {
        PressDispatcher(launcher: os, typer: os, accessibility: os, frontmost: os)
    }

    func press(_ buttonId: String, with os: FakeOS) async -> ActionError? {
        do {
            try await dispatcher(os).handle(buttonId: buttonId, config: config)
            return nil
        } catch {
            return error
        }
    }

    @Test func globalAppButtonLaunchesFromAnyApp() async {
        let os = FakeOS(frontmost: safari)
        #expect(await press("btn_2", with: os) == nil)
        #expect(await os.calls == [.launch("com.tinyspeck.slackmacgap")])
    }

    @Test func appButtonWorksWithNoFrontmostApp() async {
        let os = FakeOS(frontmost: nil)
        #expect(await press("btn_1", with: os) == nil)
        #expect(await os.calls == [.launch("com.apple.Safari")])
    }

    @Test func textButtonPastesWhenItsAppIsFrontmost() async {
        let os = FakeOS(frontmost: slack)
        #expect(await press("btn_3", with: os) == nil)
        #expect(await os.calls == [.paste("LGTM, merging.")])
    }

    @Test func keysButtonSendsWhenItsAppIsFrontmost() async {
        let os = FakeOS(frontmost: slack)
        #expect(await press("btn_4", with: os) == nil)
        #expect(await os.calls == [.keys("cmd+k")])
    }

    @Test func pageButtonInAnotherAppIsWrongApp() async {
        let os = FakeOS(frontmost: safari)
        let error = await press("btn_3", with: os)
        #expect(error == .wrongApp(expected: slack.bundleId, actual: safari.bundleId))
        #expect(error?.pressError == .wrongApp)
        #expect(await os.calls.isEmpty)
    }

    @Test func pageButtonWithNoFrontmostAppIsWrongApp() async {
        let os = FakeOS(frontmost: nil)
        #expect(await press("btn_4", with: os) == .wrongApp(expected: slack.bundleId, actual: nil))
        #expect(await os.calls.isEmpty)
    }

    @Test func unknownButton() async {
        let os = FakeOS(frontmost: slack)
        #expect(await press("btn_404", with: os) == .unknownButton(id: "btn_404"))
        #expect(await os.calls.isEmpty)
    }

    @Test func launchFailure() async {
        let os = FakeOS()
        await os.set(launchFails: true)
        #expect(await press("btn_1", with: os) == .launchFailed(bundleId: "com.apple.Safari"))
    }

    @Test func textWithoutAccessibilityIsRejectedBeforeTyping() async {
        let os = FakeOS(frontmost: slack)
        await os.set(trusted: false)
        #expect(await press("btn_3", with: os) == .noAccessibility)
        #expect(await press("btn_4", with: os) == .noAccessibility)
        #expect(await os.calls.isEmpty)
    }

    @Test func appButtonsDoNotNeedAccessibility() async {
        let os = FakeOS()
        await os.set(trusted: false)
        #expect(await press("btn_1", with: os) == nil)
    }

    @Test func focusIsCheckedAtPressTime() async {
        let os = FakeOS(frontmost: slack)
        #expect(await press("btn_3", with: os) == nil)
        await os.set(frontmost: safari)
        #expect(
            await press("btn_3", with: os)
                == .wrongApp(expected: slack.bundleId, actual: safari.bundleId))
    }

    /// The spec example plus a web-page button on the Slack page (any app's page works the
    /// same; in practice it's a browser's).
    func withUrlButton() -> Config {
        var config = config
        config.pages[0].buttons.append(
            Button(id: "web_p", label: "Docs", action: .url("https://docs.example.com")))
        return config
    }

    func pressUrl(with os: FakeOS) async -> ActionError? {
        do {
            try await dispatcher(os).handle(buttonId: "web_p", config: withUrlButton())
            return nil
        } catch {
            return error
        }
    }

    @Test func urlButtonOpensInThePagesApp() async {
        let os = FakeOS(frontmost: slack)
        #expect(await pressUrl(with: os) == nil)
        #expect(await os.calls == [.open("https://docs.example.com", app: slack.bundleId)])
    }

    @Test func urlButtonHasNoFocusGuard() async {
        // Nothing is typed, so another app being frontmost doesn't matter.
        let os = FakeOS(frontmost: safari)
        #expect(await pressUrl(with: os) == nil)
        #expect(await os.calls == [.open("https://docs.example.com", app: slack.bundleId)])
    }

    @Test func urlButtonNeedsNoAccessibility() async {
        let os = FakeOS(frontmost: slack)
        await os.set(trusted: false)
        #expect(await pressUrl(with: os) == nil)
    }

    @Test func urlOpenFailureIsLaunchFailed() async {
        let os = FakeOS(frontmost: slack)
        await os.set(launchFails: true)
        let error = await pressUrl(with: os)
        #expect(error == .openFailed(url: "https://docs.example.com"))
        #expect(error?.pressError == .launchFailed)
    }

    @Test func mapsEveryErrorToItsWireCode() {
        #expect(ActionError.noAccessibility.pressError == .noAccessibility)
        #expect(ActionError.launchFailed(bundleId: "x").pressError == .launchFailed)
        #expect(ActionError.unknownButton(id: "x").pressError == .unknownButton)
    }
}
