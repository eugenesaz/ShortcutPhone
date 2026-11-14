import Foundation
import HTTPTypes
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing
import WSClient

@testable import ShortcutPhoneServer

enum TestFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func config() throws -> Config {
        try Config.decode(Data(contentsOf: root.appendingPathComponent("config/spec-example.json")))
    }
}

let slack = AppRef(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")
let finder = AppRef(bundleId: "com.apple.finder", name: "Finder")

final class MemoryDeviceStore: DeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Device] = []

    func load() throws -> [Device] { lock.withLock { stored } }
    func save(_ devices: [Device]) throws { lock.withLock { stored = devices } }
}

/// A server wired with in-memory fakes, plus helpers to pair and connect.
struct TestAgent {
    let hub: WebSocketHub
    let pairing: PairingService
    let configStore: ConfigStore
    let server: AgentServer

    init(
        config: Config? = nil, frontmost: AppRef? = nil, webRoot: String? = nil,
        loopback: Bool = true, authTimeout: Duration = .seconds(5), os: FakeOS = FakeOS(),
        timing: any TimingLog = NoTiming()
    ) throws {
        let config = try config ?? TestFixtures.config()
        hub = WebSocketHub(config: config, frontmost: frontmost)
        pairing = try PairingService(store: MemoryDeviceStore())
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutPhoneServerTests-\(UUID().uuidString)/config.json")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.encoded().write(to: configURL)
        configStore = ConfigStore(url: configURL)
        self.os = os
        let dispatcher = PressDispatcher(launcher: os, typer: os, accessibility: os, frontmost: os)
        server = AgentServer(
            hub: hub, pairing: pairing, configStore: configStore, dispatcher: dispatcher, icons: os,
            apps: os,
            webRoot: webRoot,
            host: "127.0.0.1", port: 0, authTimeout: authTimeout, timing: timing,
            editorKey: Self.editorKey, isLoopbackClient: { _ in loopback })
    }

    let os: FakeOS

    /// The editor key every test server uses (the app makes a random one per launch).
    static let editorKey = "test-editor-key"

    func pair(name: String = "test phone") async throws -> PairedDevice {
        try await pairing.redeem(pairing.createCode().value, deviceName: name)
    }
}

extension HTTPFields {
    /// Headers the editor sends: the test server's editor key.
    static var editor: HTTPFields { [.shortcutPhoneEditorKey: TestAgent.editorKey] }
}

extension WebSocketInboundMessageStream.AsyncIterator {
    /// Next text frame decoded as a server message.
    mutating func nextServerMessage() async throws -> ServerMessage? {
        guard case .text(let text)? = try await next() else { return nil }
        return try JSONDecoder().decode(ServerMessage.self, from: Data(text.utf8))
    }
}

extension WebSocketOutboundWriter {
    func send(_ message: ClientMessage) async throws {
        try await write(.text(String(decoding: try JSONEncoder().encode(message), as: UTF8.self)))
    }
}

extension TestClientProtocol {
    /// Opens `/ws`, authenticates, and hands the message iterator to `body`.
    @discardableResult
    func authedWS(
        token: String,
        _ body:
            @escaping @Sendable (
                inout WebSocketInboundMessageStream.AsyncIterator, WebSocketOutboundWriter
            ) async throws -> Void
    ) async throws -> WebSocketCloseFrame? {
        try await ws("/ws") { inbound, outbound, _ in
            try await outbound.send(.auth(token: token))
            var messages = inbound.messages(maxSize: 1 << 20).makeAsyncIterator()
            try await body(&messages, outbound)
        }
    }
}

/// A value set from inside a concurrently running closure.
actor Box<Value: Sendable> {
    private(set) var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        value = newValue
    }
}

/// Records OS calls instead of making them.
actor FakeOS:
    AppLauncher, TextTyper, AccessibilityChecker, FrontmostAppProvider, IconProvider,
    InstalledAppsProvider
{
    private(set) var launched: [String] = []
    private(set) var pasted: [String] = []
    var frontmost: AppRef?

    init(frontmost: AppRef? = nil) {
        self.frontmost = frontmost
    }

    func current() async -> AppRef? { frontmost }
    func isTrusted() async -> Bool { true }
    func launchOrActivate(bundleId: String) async throws(ActionError) { launched.append(bundleId) }
    func open(url: String, inApp bundleId: String) async throws(ActionError) {
        launched.append(url)
    }
    func pasteAndReturn(_ text: String) async throws(ActionError) { pasted.append(text) }
    func send(_ keys: String) async throws(ActionError) {}

    func apps() async -> [InstalledApp] {
        [
            InstalledApp(
                bundleId: "com.apple.Notes", name: "Notes",
                path: "/System/Applications/Notes.app", running: true),
            InstalledApp(
                bundleId: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app",
                running: false),
        ]
    }

    func pngIcon(bundleId: String, size: Int) async -> Data? {
        bundleId == "com.apple.Safari" ? Data("png:\(size)".utf8) : nil
    }
}

/// Parent of every suite that starts a live server. Run serially: with many live servers and
/// WebSocket clients starting in parallel, a run hung about one time in ten with the clients
/// stuck in the connect/upgrade inside NIO and WSClient (before any agent code ran), never
/// when serial. The whole suite takes well under a second either way.
@Suite(.serialized) enum LiveServerTests {}

/// Keeps every recorded timing event.
final class ServerRecordingTiming: TimingLog, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimingEvent] = []

    var events: [TimingEvent] { lock.withLock { recorded } }

    func record(_ event: TimingEvent, _ elapsed: Duration) {
        lock.withLock { recorded.append(event) }
    }
}
