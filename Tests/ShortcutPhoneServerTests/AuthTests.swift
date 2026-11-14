import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing
import WSClient

@testable import ShortcutPhoneServer

struct PairResponseBody: Decodable {
    let token: String
    let deviceId: String
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct PairRouteTests {
        @Test func redeemsCodeFromTheLAN() async throws {
            let agent = try TestAgent(loopback: false)
            let code = await agent.pairing.createCode().value
            let pairing = agent.pairing
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/pair", method: .post,
                    body: ByteBuffer(string: #"{"code":"\#(code)"}"#)
                ) { response in
                    #expect(response.status == .ok)
                    let body = try JSONDecoder().decode(
                        PairResponseBody.self, from: Data(buffer: response.body))
                    #expect(await pairing.verify(body.token) == body.deviceId)
                }
            }
        }

        @Test func rejectsReusedCode() async throws {
            let agent = try TestAgent(loopback: false)
            let code = await agent.pairing.createCode().value
            try await agent.server.application().test(.router) { client in
                let body = ByteBuffer(string: #"{"code":"\#(code)"}"#)
                try await client.execute(uri: "/api/pair", method: .post, body: body) {
                    #expect($0.status == .ok)
                }
                try await client.execute(uri: "/api/pair", method: .post, body: body) {
                    #expect($0.status == .badRequest)
                }
            }
        }

        @Test func rejectsMalformedBody() async throws {
            let agent = try TestAgent(loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/pair", method: .post, body: ByteBuffer(string: "nope")
                ) {
                    #expect($0.status == .badRequest)
                }
            }
        }
    }
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct TokenAuthTests {
        @Test func apiWithoutTokenIs401() async throws {
            let agent = try TestAgent(loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/anything", method: .get) {
                    #expect($0.status == .unauthorized)
                }
            }
        }

        @Test func apiWithBadTokenIs401() async throws {
            let agent = try TestAgent(loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/anything", method: .get,
                    headers: [.authorization: "Bearer \(String(repeating: "0", count: 64))"]
                ) {
                    #expect($0.status == .unauthorized)
                }
            }
        }

        @Test func apiWithValidTokenPassesAuth() async throws {
            let agent = try TestAgent(loopback: false)
            let token = try await agent.pair().token
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/anything", method: .get, headers: [.authorization: "Bearer \(token)"]
                ) {
                    #expect($0.status == .notFound)
                }
            }
        }
    }
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct LoopbackGuardTests {
        static let editorPaths = [
            "/editor", "/editor.html", "/EDITOR.html", "/%65ditor.html", "//editor.html",
            "/assets/../editor.html", "/./editor", "/api/config", "/api/apps", "/api/devices",
            "/api/devices/dev_1", "/API/Config",
        ]

        @Test(arguments: editorPaths)
        func editorRoutesAre403FromTheLAN(_ path: String) async throws {
            let web = try WebRoot()
            let agent = try TestAgent(webRoot: web.path, loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: path, method: .get) { response in
                    #expect(response.status == .forbidden, "\(path)")
                }
            }
        }

        @Test func editorAPINeedsNoDeviceTokenOnlyTheEditorKey() async throws {
            let agent = try TestAgent(loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/config", method: .get, headers: .editor) {
                    #expect($0.status == .ok)
                }
            }
        }

        /// Over USB (`adb reverse`) a phone's requests arrive from loopback with a `localhost`
        /// Host, so any app on the phone passes the loopback checks. The key is what stops it.
        @Test(arguments: [
            "/api/config", "/api/apps", "/api/devices", "/api/config/status", "/API/Config",
        ])
        func editorAPIWithoutTheKeyIs401FromLoopback(_ path: String) async throws {
            let agent = try TestAgent(loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: path, method: .get) {
                    #expect($0.status == .unauthorized, "\(path)")
                }
            }
        }

        @Test func editorAPIWithAWrongKeyIs401() async throws {
            let agent = try TestAgent(loopback: true)
            let config = try TestFixtures.config().encoded()
            try await agent.server.application().test(.router) { client in
                let wrong: HTTPFields = [.shortcutPhoneEditorKey: "test-editor-kez"]
                try await client.execute(
                    uri: "/api/config", method: .put, headers: wrong,
                    body: ByteBuffer(bytes: config)
                ) {
                    #expect($0.status == .unauthorized)
                }
            }
        }

        @Test func deleteWithoutTheKeyKeepsTheDevice() async throws {
            let agent = try TestAgent(loopback: true)
            let paired = try await agent.pair()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/devices/\(paired.deviceId)", method: .delete) {
                    #expect($0.status == .unauthorized)
                }
            }
            #expect(await agent.pairing.verify(paired.token) == paired.deviceId)
        }

        /// The page itself is static; the key reaches it in the URL fragment, never the request.
        @Test func editorPageLoadsWithoutTheKey() async throws {
            let web = try WebRoot()
            let agent = try TestAgent(webRoot: web.path, loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/editor", method: .get) {
                    #expect($0.status == .ok)
                }
            }
        }

        @Test func loopbackWithForeignOriginIs403() async throws {
            let agent = try TestAgent(loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/config", method: .get,
                    headers: [
                        .origin: "http://evil.example",
                        .shortcutPhoneEditorKey: TestAgent.editorKey,
                    ]
                ) {
                    #expect($0.status == .forbidden)
                }
            }
        }

        @Test func loopbackWithOwnOriginIsAllowed() async throws {
            let agent = try TestAgent(loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/config", method: .get,
                    headers: [
                        .origin: "http://localhost:8765",
                        .shortcutPhoneEditorKey: TestAgent.editorKey,
                    ]
                ) {
                    #expect($0.status == .ok)
                }
            }
        }
    }
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct WebSocketAuthTests {
        func closeCode(_ frame: WebSocketCloseFrame?) -> UInt16? {
            guard case .unknown(let code)? = frame?.closeCode else { return nil }
            return code
        }

        @Test func noAuthMessageClosesWith4401() async throws {
            let agent = try TestAgent(authTimeout: .milliseconds(200))
            try await agent.server.application().test(.live) { client in
                let frame = try await client.ws("/ws") { inbound, _, _ in
                    for try await _ in inbound {}
                }
                #expect(closeCode(frame) == 4401)
            }
        }

        @Test func badTokenClosesWith4401() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.live) { client in
                let frame = try await client.authedWS(token: "nope") { messages, _ in
                    while try await messages.next() != nil {}
                }
                #expect(closeCode(frame) == 4401)
            }
        }

        @Test func firstMessageMustBeAuth() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.live) { client in
                let frame = try await client.ws("/ws") { inbound, outbound, _ in
                    try await outbound.send(.press(pressId: "p", buttonId: "btn_1"))
                    for try await _ in inbound {}
                }
                #expect(closeCode(frame) == 4401)
            }
        }

        @Test func revokeClosesTheSocketWith4401() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            let server = agent.server
            try await server.application().test(.live) { client in
                let frame = try await client.authedWS(token: paired.token) { messages, _ in
                    _ = try await messages.nextServerMessage()
                    #expect(try await server.revoke(deviceId: paired.deviceId))
                    while try await messages.next() != nil {}
                }
                #expect(closeCode(frame) == 4401)
            }
            #expect(await agent.pairing.verify(paired.token) == nil)
        }

        @Test func pairOverHTTPThenConnect() async throws {
            let agent = try TestAgent(frontmost: slack)
            let code = await agent.pairing.createCode().value
            try await agent.server.application().test(.live) { client in
                let token = try await client.execute(
                    uri: "/api/pair", method: .post,
                    body: ByteBuffer(string: #"{"code":"\#(code)"}"#)
                ) { response in
                    try JSONDecoder().decode(
                        PairResponseBody.self, from: Data(buffer: response.body)
                    )
                    .token
                }
                try await client.authedWS(token: token) { messages, _ in
                    guard case .state(let state) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(state.frontmost == slack)
                }
            }
        }
    }
}
