import Foundation
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct ViewportTests {
        static let reported = Viewport(
            portrait: OrientationLayout(page: Size(w: 360, h: 560), strip: Size(w: 344, h: 72)),
            landscape: OrientationLayout(page: Size(w: 560, h: 300), strip: Size(w: 64, h: 344)))

        @Test func viewportIsStoredForTheAuthenticatedDevice() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            let other = try await agent.pair(name: "other")
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: paired.token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    try await outbound.send(.viewport(Self.reported))
                    // A press round-trip proves the viewport message was handled first.
                    try await outbound.send(.press(pressId: "p", buttonId: "nope"))
                    _ = try await messages.nextServerMessage()
                }
            }
            let devices = await agent.pairing.devices
            #expect(devices.first { $0.id == paired.deviceId }?.viewport == Self.reported)
            #expect(devices.first { $0.id == other.deviceId }?.viewport == nil)
        }

        @Test func viewportBeforeAuthIsRejected() async throws {
            let agent = try TestAgent()
            _ = try await agent.pair()
            try await agent.server.application().test(.live) { client in
                let frame = try await client.ws("/ws") { inbound, outbound, _ in
                    try await outbound.send(.viewport(Self.reported))
                    for try await _ in inbound {}
                }
                guard case .unknown(let code)? = frame?.closeCode else {
                    Issue.record("expected a 4401 close")
                    return
                }
                #expect(code == 4401)
            }
            #expect(await agent.pairing.devices.allSatisfy { $0.viewport == nil })
        }

        @Test func implausibleViewportIsIgnored() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            var bad = Self.reported
            bad.portrait.page.w = -1
            let sent = bad
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: paired.token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    try await outbound.send(.viewport(sent))
                    try await outbound.send(.press(pressId: "p", buttonId: "nope"))
                    _ = try await messages.nextServerMessage()
                }
            }
            #expect(await agent.pairing.devices.first?.viewport == nil)
        }
    }
}
