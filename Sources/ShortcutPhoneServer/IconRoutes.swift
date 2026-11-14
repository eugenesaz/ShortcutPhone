import Foundation
import Hummingbird
import ShortcutPhoneCore

extension AgentServer {
    static let iconSizes = 16...512
    static let defaultIconSize = 128

    /// `GET /icons/<bundleId>.png?size=128`. Public: `<img>` can't send a token, and app icons
    /// aren't secret.
    func addIconRoutes(to router: Router<AgentRequestContext>) {
        router.get("/icons/:file") { [icons] request, context -> Response in
            let file = try context.parameters.require("file")
            guard file.hasSuffix(".png") else { throw HTTPError(.notFound) }
            let bundleId = String(file.dropLast(4))
            guard ConfigValidator.isBundleID(bundleId) else { throw HTTPError(.notFound) }
            let requested = request.uri.queryParameters.get("size", as: Int.self)
            let size = min(
                max(requested ?? Self.defaultIconSize, Self.iconSizes.lowerBound),
                Self.iconSizes.upperBound)
            guard let png = await icons.pngIcon(bundleId: bundleId, size: size) else {
                throw HTTPError(.notFound)
            }
            return Response(
                status: .ok,
                headers: [.contentType: "image/png", .cacheControl: "max-age=86400"],
                body: .init(byteBuffer: ByteBuffer(bytes: png)))
        }
    }
}
