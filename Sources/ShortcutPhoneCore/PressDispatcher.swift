/// Runs a button press: looks the button up, applies the focus guard, then acts.
public actor PressDispatcher {
    private let launcher: any AppLauncher
    private let typer: any TextTyper
    private let accessibility: any AccessibilityChecker
    private let frontmost: any FrontmostAppProvider
    private let timing: any TimingLog

    public init(
        launcher: any AppLauncher, typer: any TextTyper, accessibility: any AccessibilityChecker,
        frontmost: any FrontmostAppProvider, timing: any TimingLog = NoTiming()
    ) {
        self.launcher = launcher
        self.typer = typer
        self.accessibility = accessibility
        self.frontmost = frontmost
        self.timing = timing
    }

    /// - Parameter receivedAt: When the press arrived, to record press → action latency.
    public func handle(
        buttonId: String, config: Config, receivedAt: ContinuousClock.Instant? = nil
    ) async throws(ActionError) {
        func started() {
            if let receivedAt { timing.record(.pressToAction, .now - receivedAt) }
        }
        guard let (button, owner) = config.lookup(buttonId) else {
            throw .unknownButton(id: buttonId)
        }
        // Focus guard: text and keys go to the frontmost app, so a page's text/keys buttons run
        // only while that app is still frontmost, checked now rather than trusting what the
        // phone last saw. App and web-page buttons don't type anything and need no guard.
        if case .page(let bundleId) = owner, button.action.typesIntoFrontmostApp {
            let actual = await frontmost.current()?.bundleId
            guard actual == bundleId else { throw .wrongApp(expected: bundleId, actual: actual) }
        }
        switch button.action {
        case .app(let bundleId):
            started()
            try await launcher.launchOrActivate(bundleId: bundleId)
        case .text(let text):
            guard await accessibility.isTrusted() else { throw .noAccessibility }
            started()
            try await typer.pasteAndReturn(text)
        case .keys(let keys):
            guard await accessibility.isTrusted() else { throw .noAccessibility }
            started()
            try await typer.send(keys)
        case .url(let url):
            // Validation keeps url buttons out of the global strip.
            guard case .page(let browser) = owner else { throw .unknownButton(id: buttonId) }
            started()
            try await launcher.open(url: url, inApp: browser)
        }
    }
}

extension ButtonAction {
    /// Whether the action sends keystrokes to whatever app is frontmost.
    var typesIntoFrontmostApp: Bool {
        switch self {
        case .text, .keys: true
        case .app, .url: false
        }
    }
}
