import Foundation
import Hummingbird
import ShortcutPhoneCore

/// Body of a rejected `PUT /api/config`.
struct ConfigErrorResponse: Encodable {
    let errors: [ConfigIssue]
}

extension AgentServer {
    static let maxConfigSize = 1 << 20

    /// `GET/PUT /api/config`, loopback-only (see `RoutePolicy`). PUT checks the same rules as
    /// loading plus capacity against every paired phone, then saves and pushes `state`.
    func addConfigRoutes(to router: Router<AgentRequestContext>) {
        router.get("/api/config") { [configStore] _, _ -> Response in
            try Self.json(.ok, await configStore.config.encoded())
        }
        router.put("/api/config") { [configStore, pairing, hub] request, _ -> Response in
            let data: Data
            do {
                data = Data(buffer: try await request.body.collect(upTo: Self.maxConfigSize))
            } catch {
                throw HTTPError(.contentTooLarge)
            }
            let config: Config
            do {
                config = try Config.decode(data)
            } catch {
                let issues = (error as? ConfigError)?.issues
                return try Self.rejected(issues ?? [ConfigIssue(path: "", message: "invalid")])
            }
            let capacity = EffectiveCapacity(devices: await pairing.devices)
            let issues = capacity.issues(in: config)
            guard issues.isEmpty else { return try Self.rejected(issues) }
            do {
                try await configStore.save(config)
            } catch {
                throw HTTPError(.internalServerError, message: "could not write config.json")
            }
            await hub.setConfig(config)
            return try Self.json(.ok, config.encoded())
        }
    }

    private static func rejected(_ issues: [ConfigIssue]) throws -> Response {
        try json(.unprocessableContent, JSONEncoder().encode(ConfigErrorResponse(errors: issues)))
    }

    static func json(_ status: HTTPResponse.Status, _ data: Data) -> Response {
        Response(
            status: status, headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}
