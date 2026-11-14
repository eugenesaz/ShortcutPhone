import Foundation
import Testing

@testable import ShortcutPhoneCore

/// A clock the test moves by hand.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

final class MemoryDeviceStore: DeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Device] = []
    private(set) var saveCount = 0

    var devices: [Device] { lock.withLock { stored } }

    func load() throws -> [Device] { lock.withLock { stored } }

    func save(_ devices: [Device]) throws {
        lock.withLock {
            stored = devices
            saveCount += 1
        }
    }
}

@Suite struct PairingTests {
    let clock = FakeClock()
    let store = MemoryDeviceStore()

    func service() throws -> PairingService {
        try PairingService(store: store, now: { [clock] in clock.now })
    }

    @Test func codeIs128BitsAndExpiresInFiveMinutes() async throws {
        let pairing = try service()
        let code = await pairing.createCode()
        #expect(code.value.count == 32)  // 16 bytes, hex
        let isHex = code.value.allSatisfy { $0.isHexDigit }
        #expect(isHex)
        #expect(code.expiresAt == clock.now + 300)
    }

    @Test func codesAreRandom() async throws {
        let pairing = try service()
        let a = await pairing.createCode()
        let b = await pairing.createCode()
        #expect(a.value != b.value)
    }

    @Test func redeemReturns256BitTokenAndDevice() async throws {
        let pairing = try service()
        let code = await pairing.createCode()
        let paired = try await pairing.redeem(code.value, deviceName: "Pixel 5")
        #expect(paired.token.count == 64)  // 32 bytes, hex
        #expect(await pairing.verify(paired.token) == paired.deviceId)
        let device = try #require(store.devices.first)
        #expect(device.id == paired.deviceId)
        #expect(device.name == "Pixel 5")
        #expect(device.pairedAt == clock.now)
    }

    @Test func codeWorksOnlyOnce() async throws {
        let pairing = try service()
        let code = await pairing.createCode()
        _ = try await pairing.redeem(code.value, deviceName: "a")
        await #expect(throws: PairingError.invalidCode) {
            try await pairing.redeem(code.value, deviceName: "b")
        }
    }

    @Test func expiredCodeIsRejected() async throws {
        let pairing = try service()
        let code = await pairing.createCode()
        clock.advance(301)
        await #expect(throws: PairingError.invalidCode) {
            try await pairing.redeem(code.value, deviceName: "a")
        }
    }

    @Test func codeStillWorksJustBeforeExpiry() async throws {
        let pairing = try service()
        let code = await pairing.createCode()
        clock.advance(299)
        _ = try await pairing.redeem(code.value, deviceName: "a")
    }

    @Test func unknownCodeIsRejected() async throws {
        let pairing = try service()
        await #expect(throws: PairingError.invalidCode) {
            try await pairing.redeem("deadbeef", deviceName: "a")
        }
    }

    @Test func storeNeverHoldsTheRawToken() async throws {
        let pairing = try service()
        let paired = try await pairing.redeem(await pairing.createCode().value, deviceName: "a")
        let device = try #require(store.devices.first)
        #expect(device.tokenHash != paired.token)
        #expect(device.tokenHash == PairingService.hash(paired.token))
        #expect(device.tokenHash.count == 64)
    }

    @Test func wrongTokenIsRejected() async throws {
        let pairing = try service()
        _ = try await pairing.redeem(await pairing.createCode().value, deviceName: "a")
        #expect(await pairing.verify(String(repeating: "0", count: 64)) == nil)
        #expect(await pairing.verify("") == nil)
    }

    @Test func revokeRemovesDevice() async throws {
        let pairing = try service()
        let paired = try await pairing.redeem(await pairing.createCode().value, deviceName: "a")
        #expect(try await pairing.revoke(paired.deviceId))
        #expect(await pairing.verify(paired.token) == nil)
        #expect(store.devices.isEmpty)
        #expect(try await pairing.revoke(paired.deviceId) == false)
    }

    @Test func devicesSurviveRestart() async throws {
        let first = try service()
        let paired = try await first.redeem(await first.createCode().value, deviceName: "a")
        let second = try service()
        #expect(await second.verify(paired.token) == paired.deviceId)
        #expect(await second.devices.map(\.name) == ["a"])
    }

    @Test func recordsViewportPerDevice() async throws {
        let pairing = try service()
        let paired = try await pairing.redeem(await pairing.createCode().value, deviceName: "a")
        let viewport = Viewport(
            portrait: OrientationLayout(page: Size(w: 393, h: 700), strip: Size(w: 393, h: 72)),
            landscape: OrientationLayout(page: Size(w: 700, h: 345), strip: Size(w: 72, h: 393)))
        try await pairing.setViewport(viewport, for: paired.deviceId)
        #expect(store.devices.first?.viewport == viewport)
        let saves = store.saveCount
        try await pairing.setViewport(viewport, for: paired.deviceId)
        #expect(store.saveCount == saves)  // unchanged viewport is not rewritten
    }
}

@Suite struct DeviceFileStoreTests {
    @Test func roundTripsThroughDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceFileStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DeviceFileStore(url: dir.appendingPathComponent("devices.json"))
        #expect(try store.load().isEmpty)
        let device = Device(
            id: "d1", name: "Pixel", tokenHash: String(repeating: "a", count: 64),
            pairedAt: Date(timeIntervalSince1970: 1_800_000_000), viewport: nil)
        try store.save([device])
        #expect(try store.load() == [device])
    }
}
