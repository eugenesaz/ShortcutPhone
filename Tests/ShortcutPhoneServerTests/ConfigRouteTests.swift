import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

private struct ErrorBody: Decodable {
    let errors: [ConfigIssue]
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct ConfigRouteTests {
        static func body(_ config: Config) throws -> ByteBuffer {
            ByteBuffer(bytes: try config.encoded())
        }

        static func errorPaths(_ response: TestResponse) throws -> [String] {
            try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body)).errors
                .map(\.path)
        }

        /// The spec example with page 0 grown to `count` text buttons.
        static func config(pageButtons count: Int, columns: Int? = nil) throws -> Config {
            var config = try TestFixtures.config()
            config.pages[0].columns = columns
            config.pages[0].buttons = (0..<count).map {
                Button(id: "many_\($0)", label: "b\($0)", action: .text("t"))
            }
            return config
        }

        @Test func getReturnsTheCurrentConfig() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .get, headers: .editor)
                #expect(response.status == .ok)
                #expect(
                    try Config.decode(Data(buffer: response.body))
                        == (try TestFixtures.config()))
            }
        }

        @Test func validPutSavesAndUpdatesTheHub() async throws {
            let agent = try TestAgent()
            let config = try Self.config(pageButtons: 55)
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .ok)
            }
            let written = try Data(contentsOf: await agent.configStore.url)
            #expect(try Config.decode(written) == config)
            #expect(await agent.hub.currentConfig == config)
        }

        @Test func validPutPushesStateToPhones() async throws {
            let agent = try TestAgent(frontmost: slack)
            let token = try await agent.pair().token
            var config = try TestFixtures.config()
            config.pages[0].buttons.removeLast()
            let body = try Self.body(config)
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    _ = try await messages.nextServerMessage()
                    try await client.execute(
                        uri: "/api/config", method: .put, headers: .editor, body: body
                    ) {
                        #expect($0.status == .ok)
                    }
                    guard case .state(let state) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(state.page?.buttons.count == 1)
                }
            }
        }

        @Test func overCapacityPageIs422OnItsButtons() async throws {
            let agent = try TestAgent()
            let config = try Self.config(pageButtons: 56)
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .unprocessableContent)
                #expect(try Self.errorPaths(response) == ["pages[0].buttons"])
            }
            #expect(await agent.hub.currentConfig == (try TestFixtures.config()))
        }

        @Test func tooNarrowColumnsIs422OnColumns() async throws {
            let agent = try TestAgent()
            let config = try Self.config(pageButtons: 3, columns: 7)
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .unprocessableContent)
                #expect(try Self.errorPaths(response) == ["pages[0].columns"])
            }
        }

        @Test func globalStripHasNoLimit() async throws {
            let agent = try TestAgent()
            var config = try TestFixtures.config()
            config.global = (0..<30).map {
                Button(id: "g\($0)", pinned: $0 < 2, action: .app(bundleId: "com.apple.Notes"))
            }
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .ok)
            }
            #expect(await agent.hub.currentConfig.global.count == 30)
        }

        @Test func capacityUsesTheSmallestPairedPhone() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            let small = Viewport(
                portrait: OrientationLayout(page: Size(w: 248, h: 248), strip: Size(w: 400, h: 72)),
                landscape: OrientationLayout(
                    page: Size(w: 248, h: 248), strip: Size(w: 72, h: 400)))
            try await agent.pairing.setViewport(small, for: paired.deviceId)
            let config = try Self.config(pageButtons: 17)  // 4 × 4 = 16 fit
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .unprocessableContent)
                #expect(try Self.errorPaths(response) == ["pages[0].buttons"])
            }
        }

        @Test func invalidConfigIs422WithFieldPaths() async throws {
            let agent = try TestAgent()
            var config = try TestFixtures.config()
            config.pages[0].buttons[0].action = .text("")
            let body = try Self.body(config)
            try await agent.server.application().test(.router) { client in
                let response = try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body)
                #expect(response.status == .unprocessableContent)
                #expect(try Self.errorPaths(response) == ["pages[0].buttons[0].text"])
            }
        }

        @Test func malformedJSONIs422() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor,
                    body: ByteBuffer(string: "{")
                ) { response in
                    #expect(response.status == .unprocessableContent)
                }
            }
        }

        @Test func putFromTheLANIs403() async throws {
            let agent = try TestAgent(loopback: false)
            let body = try Self.body(try TestFixtures.config())
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/config", method: .put, headers: .editor, body: body
                ) {
                    #expect($0.status == .forbidden)
                }
            }
        }
    }
}
