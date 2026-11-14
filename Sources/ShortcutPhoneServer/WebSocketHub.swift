import Foundation
import ShortcutPhoneCore

/// Tracks phone sockets and pushes `state` to every authenticated one whenever the frontmost
/// app or the config changes.
public actor WebSocketHub {
    /// What a socket's writer should do next.
    enum Output: Sendable {
        /// `focusChangedAt` is set on `state` pushed because the frontmost app changed.
        case message(ServerMessage, focusChangedAt: ContinuousClock.Instant? = nil)
        case close(code: UInt16)
    }

    /// Close code for a missing, invalid or revoked token.
    static let unauthorizedCode: UInt16 = 4401

    private struct Connection {
        let continuation: AsyncStream<Output>.Continuation
        var deviceId: String?
    }

    private var config: Config
    private var frontmost: AppRef?
    private var connections: [UUID: Connection] = [:]
    private var countWatchers: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var lastCount = 0
    private let appName: @Sendable (String) -> String?

    /// - Parameter appName: Display name for a bundle ID, used to label app buttons on the phone.
    public init(
        config: Config, frontmost: AppRef?,
        appName: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.config = config
        self.frontmost = frontmost
        self.appName = appName
    }

    private var state: ServerMessage {
        .state(config.state(frontmost: frontmost, appName: appName))
    }

    /// The config presses are resolved against.
    var currentConfig: Config { config }

    /// Authenticated phones currently connected.
    public var connectionCount: Int { connections.values.filter { $0.deviceId != nil }.count }

    /// The authenticated-phone count now, then every time it changes (for the menu).
    public func connectionCounts() -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        countWatchers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeCountWatcher(id) }
        }
        continuation.yield(connectionCount)
        return stream
    }

    private func removeCountWatcher(_ id: UUID) {
        countWatchers[id] = nil
    }

    private func countChanged() {
        let count = connectionCount
        guard count != lastCount else { return }
        lastCount = count
        for watcher in countWatchers.values { watcher.yield(count) }
    }

    /// Devices with at least one authenticated socket.
    var connectedDeviceIds: Set<String> { Set(connections.values.compactMap(\.deviceId)) }

    /// - Parameter changedAt: When the Mac reported the change, to record focus → state latency.
    public func setFrontmost(_ app: AppRef?, changedAt: ContinuousClock.Instant? = nil) {
        guard app != frontmost else { return }
        frontmost = app
        broadcastState(focusChangedAt: changedAt)
    }

    public func setConfig(_ newConfig: Config) {
        guard newConfig != config else { return }
        config = newConfig
        broadcastState()
    }

    /// Closes every socket of a revoked device.
    public func disconnectDevice(_ deviceId: String) {
        for (id, connection) in connections where connection.deviceId == deviceId {
            close(id, code: Self.unauthorizedCode)
        }
    }

    /// A new socket. Nothing is sent until it authenticates.
    func open() -> (id: UUID, outputs: AsyncStream<Output>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Output>.makeStream(
            bufferingPolicy: .bufferingNewest(32))
        connections[id] = Connection(continuation: continuation, deviceId: nil)
        return (id, stream)
    }

    func authenticate(_ id: UUID, deviceId: String) {
        guard var connection = connections[id] else { return }
        connection.deviceId = deviceId
        connections[id] = connection
        countChanged()
        connection.continuation.yield(.message(state))
    }

    /// Sends to one socket (e.g. a press result).
    func send(_ message: ServerMessage, to id: UUID) {
        connections[id]?.continuation.yield(.message(message))
    }

    func isAuthenticated(_ id: UUID) -> Bool { connections[id]?.deviceId != nil }

    func close(_ id: UUID, code: UInt16) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.continuation.yield(.close(code: code))
        connection.continuation.finish()
        countChanged()
    }

    func closeIfUnauthenticated(_ id: UUID) {
        if connections[id] != nil, !isAuthenticated(id) { close(id, code: Self.unauthorizedCode) }
    }

    func disconnect(_ id: UUID) {
        connections.removeValue(forKey: id)?.continuation.finish()
        countChanged()
    }

    private func broadcastState(focusChangedAt: ContinuousClock.Instant? = nil) {
        let message = Output.message(state, focusChangedAt: focusChangedAt)
        for connection in connections.values where connection.deviceId != nil {
            connection.continuation.yield(message)
        }
    }
}
