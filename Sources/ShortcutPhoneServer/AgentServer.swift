import Foundation
import Hummingbird
import HummingbirdWebSocket
import NIOCore
import ShortcutPhoneCore

/// The HTTP + WebSocket server the phone and the editor talk to.
public struct AgentServer: Sendable {
    public static let defaultPort = Config.defaultPort
    /// Largest inbound WebSocket message accepted from a phone.
    static let maxMessageSize = 64 * 1024

    let hub: WebSocketHub
    let pairing: PairingService
    let configStore: ConfigStore
    let dispatcher: PressDispatcher
    let icons: any IconProvider
    let apps: any InstalledAppsProvider
    let webRoot: String?
    let host: String
    let port: Int
    let authTimeout: Duration
    let timing: any TimingLog
    /// Secret the editor API requires. The menu opens `/editor#key=<editorKey>`.
    public let editorKey: String
    let isLoopbackClient: @Sendable (SocketAddress?) -> Bool

    /// - Parameters:
    ///   - webRoot: Folder with the built web UI (`index.html`, `editor.html`, assets).
    ///   - host: Bind address. `0.0.0.0` so the phone can reach it over the LAN.
    ///   - authTimeout: How long a new socket may take to send `auth`.
    ///   - editorKey: Defaults to a random 256-bit key, new on every launch.
    ///   - isLoopbackClient: Tests override this to simulate LAN clients.
    public init(
        hub: WebSocketHub, pairing: PairingService, configStore: ConfigStore,
        dispatcher: PressDispatcher,
        icons: any IconProvider, apps: any InstalledAppsProvider, webRoot: String? = nil,
        host: String = "0.0.0.0", port: Int = AgentServer.defaultPort,
        authTimeout: Duration = .seconds(5), timing: any TimingLog = NoTiming(),
        editorKey: String = SecureRandom.hex(bytes: 32),
        isLoopbackClient: (@Sendable (SocketAddress?) -> Bool)? = nil
    ) {
        self.hub = hub
        self.pairing = pairing
        self.configStore = configStore
        self.dispatcher = dispatcher
        self.icons = icons
        self.apps = apps
        self.webRoot = webRoot
        self.host = host
        self.port = port
        self.authTimeout = authTimeout
        self.timing = timing
        self.editorKey = editorKey
        self.isLoopbackClient = isLoopbackClient ?? { RoutePolicy.isLoopbackAddress($0) }
    }

    /// Forgets a device and closes its sockets immediately.
    @discardableResult
    public func revoke(deviceId: String) async throws -> Bool {
        let removed = try await pairing.revoke(deviceId)
        await hub.disconnectDevice(deviceId)
        return removed
    }

    private static func html(_ webRoot: String, _ file: String) throws -> Response {
        let url = URL(fileURLWithPath: webRoot).appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { throw HTTPError(.notFound) }
        return Response(
            status: .ok, headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    public func application() -> some ApplicationProtocol {
        let router = Router(context: AgentRequestContext.self)
        router.middlewares.add(
            LocalOnlyMiddleware(isLoopbackClient: isLoopbackClient, editorKey: editorKey))
        router.middlewares.add(DeviceTokenMiddleware(pairing: pairing))
        if let webRoot {
            router.middlewares.add(FileMiddleware(webRoot, searchForIndexHtml: true))
            // Page routes without a file of their own. `/editor` is loopback-only (see guard).
            router.get("/editor") { _, _ in try Self.html(webRoot, "editor.html") }
            router.get("/pair") { _, _ in try Self.html(webRoot, "index.html") }
        }
        addPairRoutes(to: router)
        addConfigRoutes(to: router)
        addIconRoutes(to: router)
        addEditorRoutes(to: router)

        let session = WebSocketSession(
            hub: hub, pairing: pairing, dispatcher: dispatcher, authTimeout: authTimeout,
            timing: timing)
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/ws") { _, _ in
            .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            try await session.run(inbound: inbound, outbound: outbound)
        }

        return Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: .init(
                address: .hostname(host, port: port), serverName: "ShortcutPhone"))
    }
}
