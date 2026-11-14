import HTTPTypes
import Hummingbird
import NIOCore
import ShortcutPhoneCore

extension HTTPField.Name {
    /// The per-launch secret the editor sends on every editor API call.
    public static let shortcutPhoneEditorKey = Self("X-ShortcutPhone-Editor-Key")!
}

/// Editor routes: loopback clients only, with a loopback `Host` and a same-origin `Origin`.
/// Editor API calls must also carry the editor key, because loopback isn't proof of being this
/// Mac: a USB phone's requests arrive through `adb reverse` from loopback too.
struct LocalOnlyMiddleware<Context: RemoteAddressRequestContext>: RouterMiddleware {
    let isLoopbackClient: @Sendable (SocketAddress?) -> Bool
    let editorKey: String

    func handle(
        _ request: Request, context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard RoutePolicy.isLocalOnly(request.uri.path) else {
            return try await next(request, context)
        }
        guard isLoopbackClient(context.remoteAddress),
            RoutePolicy.isLoopbackHost(request.head.authority),
            RoutePolicy.isAllowedOrigin(request.headers[.origin])
        else {
            throw HTTPError(.forbidden)
        }
        if RoutePolicy.needsEditorKey(request.uri.path) {
            let sent = request.headers[.shortcutPhoneEditorKey] ?? ""
            guard !sent.isEmpty, SecureRandom.constantTimeEquals(sent, editorKey) else {
                throw HTTPError(.unauthorized, message: "reopen the editor from the menu")
            }
        }
        return try await next(request, context)
    }
}

/// Phone API routes need `Authorization: Bearer <device token>`.
struct DeviceTokenMiddleware<Context: RequestContext>: RouterMiddleware {
    let pairing: PairingService

    func handle(
        _ request: Request, context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard RoutePolicy.needsDeviceToken(request.uri.path) else {
            return try await next(request, context)
        }
        let header = request.headers[.authorization] ?? ""
        let prefix = "Bearer "
        guard header.hasPrefix(prefix),
            await pairing.verify(String(header.dropFirst(prefix.count))) != nil
        else {
            throw HTTPError(.unauthorized)
        }
        return try await next(request, context)
    }
}
