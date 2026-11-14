import Foundation
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

@Suite(.timeLimit(.minutes(1))) struct ConnectionCountTests {
    @Test func countsOnlyAuthenticatedPhonesAndReportsChanges() async throws {
        let hub = WebSocketHub(config: Config(), frontmost: nil)
        var counts = await hub.connectionCounts().makeAsyncIterator()
        #expect(await counts.next() == 0)

        let first = await hub.open()
        let second = await hub.open()
        await hub.authenticate(first.id, deviceId: "dev_a")
        #expect(await counts.next() == 1)
        await hub.authenticate(second.id, deviceId: "dev_b")
        #expect(await counts.next() == 2)

        await hub.disconnect(first.id)
        #expect(await counts.next() == 1)
        await hub.disconnectDevice("dev_b")  // revoke
        #expect(await counts.next() == 0)
        #expect(await hub.connectionCount == 0)
    }

    @Test func unauthenticatedSocketsDontChangeTheCount() async throws {
        let hub = WebSocketHub(config: Config(), frontmost: nil)
        let socket = await hub.open()
        await hub.closeIfUnauthenticated(socket.id)
        let phone = await hub.open()
        await hub.authenticate(phone.id, deviceId: "dev_a")
        var counts = await hub.connectionCounts().makeAsyncIterator()
        #expect(await counts.next() == 1)
    }
}
