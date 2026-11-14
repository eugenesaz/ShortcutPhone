import Foundation
import Hummingbird
import ShortcutPhoneCore

/// One paired phone as the editor sees it. The token hash stays on the agent.
struct DeviceInfo: Encodable {
    let id: String
    let name: String
    let pairedAt: Date
    let viewport: Viewport?
    let connected: Bool
}

/// `GET /api/config/status`: the problem with `config.json` on disk, if any.
struct ConfigStatus: Encodable {
    let errors: [ConfigIssue]?
}

extension AgentServer {
    /// Editor-only routes besides the config itself. All are loopback-only (see `RoutePolicy`).
    func addEditorRoutes(to router: Router<AgentRequestContext>) {
        router.get("/api/apps") { [apps] _, _ -> Response in
            try Self.json(.ok, Self.encoder.encode(await apps.apps()))
        }
        router.get("/api/config/status") { [configStore] _, _ -> Response in
            let errors = await configStore.error?.issues
            return try Self.json(.ok, Self.encoder.encode(ConfigStatus(errors: errors)))
        }
        router.get("/api/devices") { [pairing, hub] _, _ -> Response in
            let connected = await hub.connectedDeviceIds
            let devices = await pairing.devices.map {
                DeviceInfo(
                    id: $0.id, name: $0.name, pairedAt: $0.pairedAt, viewport: $0.viewport,
                    connected: connected.contains($0.id))
            }
            return try Self.json(.ok, Self.encoder.encode(devices))
        }
        router.delete("/api/devices/:id") { request, context -> Response in
            let id = try context.parameters.require("id")
            let removed: Bool
            do {
                removed = try await revoke(deviceId: id)
            } catch {
                throw HTTPError(.internalServerError, message: "could not write devices.json")
            }
            guard removed else { throw HTTPError(.notFound) }
            return Response(status: .noContent)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
