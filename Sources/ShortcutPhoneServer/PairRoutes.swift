import Foundation
import Hummingbird
import ShortcutPhoneCore

struct PairRequest: Decodable {
    let code: String
    let name: String?
}

struct PairResponse: ResponseEncodable {
    let token: String
    let deviceId: String
}

extension AgentServer {
    func addPairRoutes(to router: Router<AgentRequestContext>) {
        router.post(.init(RoutePolicy.pairPath)) { [pairing] request, context -> PairResponse in
            let body: PairRequest
            do {
                body = try await request.decode(as: PairRequest.self, context: context)
            } catch {
                throw HTTPError(.badRequest, message: "expected {\"code\": \"…\"}")
            }
            let name = body.name.map { String($0.prefix(64)) } ?? "Phone"
            do {
                let paired = try await pairing.redeem(body.code, deviceName: name)
                return PairResponse(token: paired.token, deviceId: paired.deviceId)
            } catch {
                throw HTTPError(.badRequest, message: "invalid or expired code")
            }
        }
    }
}
