import Foundation
import Hummingbird
import ShortcutPhoneCore

extension AgentServer {
    /// The only sizes rendered. A request is rounded up to the next one (the largest above 512),
    /// so the public route can't fill the icon cache with every size from 16 to 512.
    static let iconSizes = [64, 128, 256, 512]
    static let defaultIconSize = 128

    static func iconSize(for requested: Int?) -> Int {
        let wanted = requested ?? defaultIconSize
        return iconSizes.first { $0 >= wanted } ?? iconSizes[iconSizes.count - 1]
    }

    /// `GET /icons/<bundleId>.png?size=128`. Public: `<img>` can't send a token, and app icons
    /// aren't secret.
    func addIconRoutes(to router: Router<AgentRequestContext>) {
        router.get("/icons/:file") { [icons] request, context -> Response in
            let file = try context.parameters.require("file")
            guard file.hasSuffix(".png") else { throw HTTPError(.notFound) }
            let bundleId = String(file.dropLast(4))
            guard ConfigValidator.isBundleID(bundleId) else { throw HTTPError(.notFound) }
            let size = Self.iconSize(for: request.uri.queryParameters.get("size", as: Int.self))
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
