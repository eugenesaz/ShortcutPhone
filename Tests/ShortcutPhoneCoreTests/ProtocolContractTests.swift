import Foundation
import Testing

@testable import ShortcutPhoneCore

/// Every fixture in Tests/Fixtures/protocol, shared with the web test suite.
enum ProtocolFixtures {
    static func names(_ folder: String, prefix: String) -> [String] {
        let dir = Fixtures.root.appendingPathComponent("protocol/\(folder)")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.sorted()
    }

    static func data(_ folder: String, _ name: String) throws -> Data {
        try Fixtures.data("protocol/\(folder)/\(name)")
    }
}

/// JSON values compared structurally (numbers by value, key order ignored).
func sameJSON(_ a: Data, _ b: Data) throws -> Bool {
    let lhs = try JSONSerialization.jsonObject(with: a) as AnyObject
    let rhs = try JSONSerialization.jsonObject(with: b) as AnyObject
    return lhs.isEqual(rhs)
}

@Suite struct ProtocolContractTests {
    @Test func fixturesExist() {
        #expect(ProtocolFixtures.names("valid", prefix: "client-").count >= 3)
        #expect(ProtocolFixtures.names("valid", prefix: "server-").count >= 7)
        #expect(ProtocolFixtures.names("invalid", prefix: "").count >= 6)
    }

    @Test(arguments: ProtocolFixtures.names("valid", prefix: "client-"))
    func clientFixtureRoundTrips(_ name: String) throws {
        let data = try ProtocolFixtures.data("valid", name)
        let message = try JSONDecoder().decode(ClientMessage.self, from: data)
        #expect(try sameJSON(JSONEncoder().encode(message), data))
    }

    @Test(arguments: ProtocolFixtures.names("valid", prefix: "server-"))
    func serverFixtureRoundTrips(_ name: String) throws {
        let data = try ProtocolFixtures.data("valid", name)
        let message = try JSONDecoder().decode(ServerMessage.self, from: data)
        #expect(try sameJSON(JSONEncoder().encode(message), data))
    }

    @Test(arguments: ProtocolFixtures.names("invalid", prefix: "client-"))
    func invalidClientFixtureIsRejected(_ name: String) throws {
        let data = try ProtocolFixtures.data("invalid", name)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ClientMessage.self, from: data)
        }
    }

    @Test(arguments: ProtocolFixtures.names("invalid", prefix: "server-"))
    func invalidServerFixtureIsRejected(_ name: String) throws {
        let data = try ProtocolFixtures.data("invalid", name)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ServerMessage.self, from: data)
        }
    }

    @Test func decodesPressFields() throws {
        let data = try ProtocolFixtures.data("valid", "client-press.json")
        let message = try JSONDecoder().decode(ClientMessage.self, from: data)
        #expect(
            message == .press(pressId: "5b7e3c1a-2f4d-4e8a-9c6b-1d2e3f4a5b6c", buttonId: "btn_42"))
    }

    @Test func decodesViewportFields() throws {
        let data = try ProtocolFixtures.data("valid", "client-viewport.json")
        guard
            case .viewport(let viewport) = try JSONDecoder().decode(ClientMessage.self, from: data)
        else {
            Issue.record("not a viewport message")
            return
        }
        #expect(viewport.portrait.page == Size(w: 393, h: 700))
        #expect(viewport.landscape.page.w == 700.5)
    }

    @Test func decodesErrorResult() throws {
        let data = try ProtocolFixtures.data("valid", "server-result-wrong_app.json")
        let message = try JSONDecoder().decode(ServerMessage.self, from: data)
        #expect(message == .result(pressId: "p-1", error: .wrongApp))
    }

    @Test func encodesNullFrontmostAndPage() throws {
        let message = ServerMessage.state(StateMessage(frontmost: nil, global: [], page: nil))
        let json = try #require(String(data: JSONEncoder().encode(message), encoding: .utf8))
        #expect(json.contains("\"frontmost\":null"))
        #expect(json.contains("\"page\":null"))
    }
}
