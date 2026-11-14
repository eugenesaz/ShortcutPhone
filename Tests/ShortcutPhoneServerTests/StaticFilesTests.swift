import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

/// A temporary web root with phone and editor pages.
struct WebRoot: ~Copyable {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("<h1>phone</h1>".utf8).write(to: url.appendingPathComponent("index.html"))
        try Data("<h1>editor</h1>".utf8).write(to: url.appendingPathComponent("editor.html"))
        path = url.path
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct StaticFilesTests {
        @Test func servesManifestAndPWAIconsToAnyone() async throws {
            let web = try WebRoot()
            let root = URL(fileURLWithPath: web.path)
            try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.webmanifest"))
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("pwa"), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: root.appendingPathComponent("pwa/icon-192.png"))
            let agent = try TestAgent(webRoot: web.path, loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/manifest.webmanifest", method: .get) { response in
                    #expect(response.status == .ok)
                    #expect(response.headers[.contentType] == "application/manifest+json")
                }
                try await client.execute(uri: "/pwa/icon-192.png", method: .get) { response in
                    #expect(response.status == .ok)
                    #expect(response.headers[.contentType] == "image/png")
                }
            }
        }

        @Test func servesPhoneIndexToAnyone() async throws {
            let web = try WebRoot()
            let agent = try TestAgent(webRoot: web.path, loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/", method: .get) { response in
                    #expect(response.status == .ok)
                    #expect(String(buffer: response.body) == "<h1>phone</h1>")
                }
            }
        }

        @Test func servesEditorAtSlashEditorToLoopback() async throws {
            let web = try WebRoot()
            let agent = try TestAgent(webRoot: web.path, loopback: true)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/editor", method: .get) { response in
                    #expect(response.status == .ok)
                    #expect(String(buffer: response.body) == "<h1>editor</h1>")
                }
            }
        }

        @Test func servesPhonePageAtSlashPairToAnyone() async throws {
            let web = try WebRoot()
            let agent = try TestAgent(webRoot: web.path, loopback: false)
            try await agent.server.application().test(.router) { client in
                try await client.execute(uri: "/pair?code=abc", method: .get) { response in
                    #expect(response.status == .ok)
                    #expect(String(buffer: response.body) == "<h1>phone</h1>")
                }
            }
        }
    }
}
