import Foundation
import NIOCore

/// Which paths are editor-only (loopback) and which need a device token.
enum RoutePolicy {
    static let pairPath = "/api/pair"

    /// Lowercased, percent-decoded, with `.`/`..`/empty segments resolved, so that
    /// `/%65ditor.html`, `/EDITOR.html` or `/assets/../editor.html` can't slip past the guards
    /// (the file middleware decodes paths and macOS file names are case-insensitive).
    static func normalize(_ rawPath: String) -> String {
        let decoded = (rawPath.removingPercentEncoding ?? rawPath).lowercased()
        var parts: [Substring] = []
        for part in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    private static let localOnlyExact: Set<String> = ["/editor", "/editor.html"]
    private static let localOnlyPrefixes = ["/editor/", "/api/config", "/api/apps", "/api/devices"]

    static func isLocalOnly(_ rawPath: String) -> Bool {
        let path = normalize(rawPath)
        if localOnlyExact.contains(path) { return true }
        return localOnlyPrefixes.contains { prefix in
            path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
        }
    }

    /// Editor API routes, which also need the editor key. The `/editor` page itself doesn't:
    /// it's static, and the key reaches it in the URL fragment.
    static func needsEditorKey(_ rawPath: String) -> Bool {
        isLocalOnly(rawPath) && normalize(rawPath).hasPrefix("/api/")
    }

    /// Phone API routes: everything under `/api/` that isn't pairing or editor-only.
    static func needsDeviceToken(_ rawPath: String) -> Bool {
        let path = normalize(rawPath)
        return path.hasPrefix("/api/") && path != pairPath && !isLocalOnly(rawPath)
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]"]

    /// `Host` must name this machine, which defeats DNS rebinding against the editor.
    static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        let name: String
        if host.hasPrefix("[") {
            name = host.firstIndex(of: "]").map { String(host[...$0]) } ?? host
        } else {
            name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        }
        return loopbackHosts.contains(name)
    }

    /// A browser `Origin`, if sent, must be the editor itself.
    static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin else { return true }
        guard let url = URL(string: origin), url.scheme == "http" else { return false }
        return isLoopbackHost(url.host.map { $0.contains(":") ? "[\($0)]" : $0 })
    }

    static func isLoopbackAddress(_ address: SocketAddress?) -> Bool {
        guard let ip = address?.ipAddress else { return false }
        return ip == "127.0.0.1" || ip == "::1" || ip == "::ffff:127.0.0.1"
    }
}
