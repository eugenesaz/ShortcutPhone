import Foundation
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

@Suite(.timeLimit(.minutes(1))) struct AppNameTests {
    @Test func pushedStateNamesUnlabeledAppButtons() async throws {
        let config = Config(global: [Button(id: "g", action: .app(bundleId: "com.apple.mail"))])
        let hub = WebSocketHub(
            config: config, frontmost: nil,
            appName: { $0 == "com.apple.mail" ? "Mail" : nil })
        let socket = await hub.open()
        await hub.authenticate(socket.id, deviceId: "dev_a")
        var outputs = socket.outputs.makeAsyncIterator()
        guard case .message(.state(let state), _)? = await outputs.next() else {
            Issue.record("expected state")
            return
        }
        #expect(state.global.first?.label == "Mail")
    }
}
