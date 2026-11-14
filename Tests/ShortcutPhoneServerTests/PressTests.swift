import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct PressTests {
        @Test func appPressRunsAndReportsOK() async throws {
            let agent = try TestAgent()
            let token = try await agent.pair().token
            let os = agent.os
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    try await outbound.send(.press(pressId: "p-1", buttonId: "btn_1"))
                    #expect(
                        try await messages.nextServerMessage()
                            == .result(pressId: "p-1", error: nil))
                }
            }
            #expect(await os.launched == ["com.apple.Safari"])
        }

        @Test func wrongAppPressReportsError() async throws {
            let agent = try TestAgent(os: FakeOS(frontmost: finder))
            let token = try await agent.pair().token
            let os = agent.os
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    try await outbound.send(.press(pressId: "p-2", buttonId: "btn_3"))
                    #expect(
                        try await messages.nextServerMessage()
                            == .result(pressId: "p-2", error: .wrongApp))
                }
            }
            #expect(await os.pasted.isEmpty)
        }

        @Test func unknownButtonReportsError() async throws {
            let agent = try TestAgent()
            let token = try await agent.pair().token
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    try await outbound.send(.press(pressId: "p-3", buttonId: "nope"))
                    #expect(
                        try await messages.nextServerMessage()
                            == .result(pressId: "p-3", error: .unknownButton))
                }
            }
        }

        @Test func pressesUseTheLatestConfig() async throws {
            let agent = try TestAgent(os: FakeOS(frontmost: slack))
            let token = try await agent.pair().token
            let hub = agent.hub
            let os = agent.os
            var config = try TestFixtures.config()
            config.pages[0].buttons[0].action = .text("changed")
            let changed = config
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, outbound in
                    _ = try await messages.nextServerMessage()
                    await hub.setConfig(changed)
                    _ = try await messages.nextServerMessage()  // the pushed state
                    try await outbound.send(.press(pressId: "p-4", buttonId: "btn_3"))
                    _ = try await messages.nextServerMessage()
                }
            }
            #expect(await os.pasted == ["changed"])
        }
    }
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct IconRouteTests {
        @Test func servesIconPNGToAnyone() async throws {
            let agent = try TestAgent(loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/icons/com.apple.Safari.png?size=64", method: .get) {
                    #expect($0.status == .ok)
                    #expect($0.headers[.contentType] == "image/png")
                    #expect(String(buffer: $0.body) == "png:64")
                }
            }
        }

        @Test func defaultsAndClampsSize() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/icons/com.apple.Safari.png", method: .get) {
                    #expect(String(buffer: $0.body) == "png:128")
                }
                try await client.execute(
                    uri: "/icons/com.apple.Safari.png?size=99999", method: .get
                ) {
                    #expect(String(buffer: $0.body) == "png:512")
                }
            }
        }

        @Test(arguments: [
            "/icons/com.unknown.App.png", "/icons/not-a-bundle.png", "/icons/com.apple.Safari",
        ])
        func unknownOrMalformedIsNotFound(_ uri: String) async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: uri, method: .get) {
                    #expect($0.status == .notFound)
                }
            }
        }
    }
}
