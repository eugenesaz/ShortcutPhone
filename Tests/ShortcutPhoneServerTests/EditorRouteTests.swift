import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

private struct DeviceBody: Decodable {
    let id: String
    let name: String
    let pairedAt: String
    let viewport: Viewport?
    let connected: Bool
}

private struct StatusBody: Decodable {
    let errors: [ConfigIssue]?
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct EditorRouteTests {
        @Test func appsListsTheAdapterApps() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/apps", method: .get, headers: .editor) {
                    response in
                    #expect(response.status == .ok)
                    let apps = try JSONDecoder().decode(
                        [InstalledApp].self, from: Data(buffer: response.body))
                    #expect(apps.map(\.bundleId) == ["com.apple.Notes", "com.apple.Safari"])
                    #expect(apps.first?.running == true)
                }
            }
        }

        @Test(arguments: ["/api/apps", "/api/devices", "/api/config/status"])
        func editorRoutesAre403FromTheLAN(_ path: String) async throws {
            let agent = try TestAgent(loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: path, method: .get, headers: .editor) {
                    #expect($0.status == .forbidden)
                }
            }
        }

        @Test func deleteFromTheLANIs403AndKeepsTheDevice() async throws {
            let agent = try TestAgent(loopback: false)
            let paired = try await agent.pair()
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/devices/\(paired.deviceId)", method: .delete, headers: .editor
                ) {
                    #expect($0.status == .forbidden)
                }
            }
            #expect(await agent.pairing.verify(paired.token) == paired.deviceId)
        }

        @Test func devicesListHidesTheTokenHash() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair(name: "Pixel 5")
            try await agent.pairing.setViewport(Capacity.pixel5, for: paired.deviceId)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/devices", method: .get, headers: .editor) {
                    response in
                    #expect(response.status == .ok)
                    let text = String(buffer: response.body)
                    #expect(!text.contains("tokenHash"))
                    let devices = try JSONDecoder().decode(
                        [DeviceBody].self, from: Data(buffer: response.body))
                    #expect(devices.map(\.id) == [paired.deviceId])
                    #expect(devices.first?.name == "Pixel 5")
                    #expect(devices.first?.viewport == Capacity.pixel5)
                    #expect(devices.first?.connected == false)
                }
            }
        }

        @Test func devicesListMarksConnectedPhones() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: paired.token) { messages, _ in
                    _ = try await messages.nextServerMessage()  // state: now authenticated
                    try await client.execute(uri: "/api/devices", method: .get, headers: .editor) {
                        response in
                        let devices = try JSONDecoder().decode(
                            [DeviceBody].self, from: Data(buffer: response.body))
                        #expect(devices.first?.connected == true)
                    }
                }
            }
        }

        @Test func deleteRevokesAndClosesTheSocket() async throws {
            let agent = try TestAgent()
            let paired = try await agent.pair()
            let deviceId = paired.deviceId
            try await agent.server.application().test(.live) { client in
                let close = try await client.authedWS(token: paired.token) { messages, _ in
                    _ = try await messages.nextServerMessage()
                    try await client.execute(
                        uri: "/api/devices/\(deviceId)", method: .delete, headers: .editor
                    ) {
                        #expect($0.status == .noContent)
                    }
                    while try await messages.next() != nil {}
                }
                guard case .unknown(let code)? = close?.closeCode else {
                    Issue.record("expected a 4401 close")
                    return
                }
                #expect(code == WebSocketHub.unauthorizedCode)
            }
            #expect(await agent.pairing.verify(paired.token) == nil)
            #expect(await agent.pairing.devices.isEmpty)
        }

        @Test func deleteUnknownDeviceIs404() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(
                    uri: "/api/devices/dev_nope", method: .delete, headers: .editor
                ) {
                    #expect($0.status == .notFound)
                }
            }
        }

        @Test func statusIsEmptyForAValidFile() async throws {
            let agent = try TestAgent()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/config/status", method: .get, headers: .editor)
                { response in
                    #expect(response.status == .ok)
                    let body = try JSONDecoder().decode(
                        StatusBody.self, from: Data(buffer: response.body))
                    #expect(body.errors == nil)
                }
            }
        }

        @Test func statusReportsAnInvalidFile() async throws {
            let agent = try TestAgent()
            try Data("{".utf8).write(to: await agent.configStore.url)
            // Make sure the modification date differs from the one seen at load.
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(5)],
                ofItemAtPath: await agent.configStore.url.path)
            await agent.configStore.reloadIfModified()
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/api/config/status", method: .get, headers: .editor)
                { response in
                    let body = try JSONDecoder().decode(
                        StatusBody.self, from: Data(buffer: response.body))
                    #expect(body.errors?.isEmpty == false)
                }
            }
        }
    }
}
