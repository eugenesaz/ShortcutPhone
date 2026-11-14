/// Runs a button press: looks the button up, applies the focus guard, then acts.
public actor PressDispatcher {
    private let launcher: any AppLauncher
    private let typer: any TextTyper
    private let accessibility: any AccessibilityChecker
    private let frontmost: any FrontmostAppProvider
    private let timing: any TimingLog
    /// The last queued typing action. Text and key presses run one at a time, in arrival order,
    /// whichever phone sent them: a paste saves and restores the clipboard, and overlapping
    /// pastes would lose the user's clipboard. (An actor alone doesn't prevent this, because
    /// it lets another press in while one awaits the typer.)
    private var typingQueue: Task<Void, Never>?

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
        @Sendable func started() {
            if let receivedAt { timing.record(.pressToAction, .now - receivedAt) }
        }
        guard let (button, owner) = config.lookup(buttonId) else {
            throw .unknownButton(id: buttonId)
        }
        switch button.action {
        case .app(let bundleId):
            started()
            try await launcher.launchOrActivate(bundleId: bundleId)
        case .text, .keys:
            try await inTypingQueue { () async throws(ActionError) in
                // Focus guard: text and keys go to the frontmost app, so a page's text/keys
                // buttons run only while that app is frontmost. Checked when this press's turn
                // comes, not when it arrived or from what the phone last saw.
                if case .page(let bundleId) = owner {
                    let actual = await self.frontmost.current()?.bundleId
                    guard actual == bundleId else {
                        throw .wrongApp(expected: bundleId, actual: actual)
                    }
                }
                guard await self.accessibility.isTrusted() else { throw .noAccessibility }
                started()
                if case .text(let text) = button.action {
                    try await self.typer.pasteAndReturn(text)
                } else if case .keys(let keys) = button.action {
                    try await self.typer.send(keys)
                }
            }
        case .url(let url):
            // Validation keeps url buttons out of the global strip.
            guard case .page(let browser) = owner else { throw .unknownButton(id: buttonId) }
            started()
            try await launcher.open(url: url, inApp: browser)
        case .folder:
            // The phone opens folders itself; there is nothing to run on the Mac.
            throw .unknownButton(id: buttonId)
        }
    }
}

extension PressDispatcher {
    /// Runs `action` after every typing action queued before it has finished.
    private func inTypingQueue(
        _ action: @escaping @Sendable () async throws(ActionError) -> Void
    ) async throws(ActionError) {
        let previous = typingQueue
        let run = Task { () async -> Result<Void, ActionError> in
            await previous?.value
            do throws(ActionError) {
                try await action()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        typingQueue = Task { _ = await run.value }
        try await run.value.get()
    }
}
