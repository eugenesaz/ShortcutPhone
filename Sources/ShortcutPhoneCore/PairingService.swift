import CryptoKit
import Foundation

public enum PairingError: Error, Equatable, Sendable {
    /// Unknown, already used, or expired.
    case invalidCode
}

public struct PairingCode: Equatable, Sendable {
    /// 128 random bits, hex.
    public let value: String
    public let expiresAt: Date
}

public struct PairedDevice: Equatable, Sendable {
    public let deviceId: String
    /// 256 random bits, hex. Shown to the phone once and never stored.
    public let token: String
}

/// One-time pairing codes, device tokens and the paired-device list.
public actor PairingService {
    public static let codeLifetime: TimeInterval = 5 * 60

    private let store: any DeviceStore
    private let now: @Sendable () -> Date
    private var codes: [String: Date] = [:]
    private var byId: [String: Device] = [:]
    private var idByHash: [String: String] = [:]
    private var order: [String] = []

    public init(store: any DeviceStore, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.store = store
        self.now = now
        for device in try store.load() {
            byId[device.id] = device
            idByHash[device.tokenHash] = device.id
            order.append(device.id)
        }
    }

    public var devices: [Device] { order.compactMap { byId[$0] } }

    public func createCode() -> PairingCode {
        pruneExpiredCodes()
        let code = PairingCode(
            value: SecureRandom.hex(bytes: 16), expiresAt: now() + Self.codeLifetime)
        codes[code.value] = code.expiresAt
        return code
    }

    public func redeem(_ code: String, deviceName: String) throws -> PairedDevice {
        pruneExpiredCodes()
        guard codes.removeValue(forKey: code) != nil else { throw PairingError.invalidCode }
        let token = SecureRandom.hex(bytes: 32)
        let device = Device(
            id: "dev_" + SecureRandom.hex(bytes: 8), name: deviceName, tokenHash: Self.hash(token),
            pairedAt: now(), viewport: nil)
        byId[device.id] = device
        idByHash[device.tokenHash] = device.id
        order.append(device.id)
        try persist()
        return PairedDevice(deviceId: device.id, token: token)
    }

    /// The device ID for a valid token, or `nil`.
    public func verify(_ token: String) -> String? {
        guard !token.isEmpty else { return nil }
        return idByHash[Self.hash(token)]
    }

    /// Returns whether a device was removed.
    @discardableResult
    public func revoke(_ deviceId: String) throws -> Bool {
        guard let device = byId.removeValue(forKey: deviceId) else { return false }
        idByHash.removeValue(forKey: device.tokenHash)
        order.removeAll { $0 == deviceId }
        try persist()
        return true
    }

    public func setViewport(_ viewport: Viewport, for deviceId: String) throws {
        guard var device = byId[deviceId], device.viewport != viewport else { return }
        device.viewport = viewport
        byId[deviceId] = device
        try persist()
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func pruneExpiredCodes() {
        let current = now()
        codes = codes.filter { $0.value > current }
    }

    private func persist() throws {
        try store.save(devices)
    }
}
