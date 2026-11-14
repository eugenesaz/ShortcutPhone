import Foundation

/// Semantic checks on a decoded config. Capacity is checked separately, because it depends
/// on the paired devices' screen sizes.
public enum ConfigValidator {
    static func issues(in config: Config) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []
        func add(_ path: String, _ message: String) {
            issues.append(ConfigIssue(path: path, message: message))
        }

        if !(1...65535).contains(config.server.port) {
            add("server.port", "must be between 1 and 65535")
        }

        var seenIds = Set<String>()
        func check(_ button: Button, at path: String, globalStrip: Bool) {
            if button.id.isEmpty {
                add("\(path).id", "is required")
            } else if !seenIds.insert(button.id).inserted {
                add("\(path).id", "duplicate id \(button.id)")
            }
            if let color = button.color, !isHexColor(color) {
                add("\(path).color", "must look like #RRGGBB")
            }
            switch button.action {
            case .app(let bundleId):
                if !isBundleID(bundleId) { add("\(path).bundleId", "is not a valid bundle ID") }
            case .url(let url):
                if globalStrip { add("\(path).type", "global buttons must be app buttons") }
                if !isWebURL(url) {
                    add("\(path).url", "must be a web address starting with https:// or http://")
                }
            case .text(let text):
                if globalStrip { add("\(path).type", "global buttons must be app buttons") }
                if text.isEmpty { add("\(path).text", "is required") }
                if !hasFace(button) { add("\(path).label", "needs a label or an emoji") }
            case .keys(let keys):
                if globalStrip { add("\(path).type", "global buttons must be app buttons") }
                if keys.trimmingCharacters(in: .whitespaces).isEmpty {
                    add("\(path).keys", "is required")
                } else if KeyCombo.parse(keys) == nil {
                    add("\(path).keys", "is not a key combo like cmd+shift+p, 1, f5 or space")
                }
                if !hasFace(button) { add("\(path).label", "needs a label or an emoji") }
            }
        }

        for (index, button) in config.global.enumerated() {
            check(button, at: "global[\(index)]", globalStrip: true)
        }

        var seenPages = Set<String>()
        for (pageIndex, page) in config.pages.enumerated() {
            let path = "pages[\(pageIndex)]"
            if !isBundleID(page.bundleId) {
                add("\(path).bundleId", "is not a valid bundle ID")
            } else if !seenPages.insert(page.bundleId).inserted {
                add("\(path).bundleId", "duplicate page for \(page.bundleId)")
            }
            if let columns = page.columns, !(1...8).contains(columns) {
                add("\(path).columns", "must be between 1 and 8")
            }
            for (index, button) in page.buttons.enumerated() {
                check(button, at: "\(path).buttons[\(index)]", globalStrip: false)
            }
        }
        return issues
    }

    private static func hasFace(_ button: Button) -> Bool {
        !(button.label ?? "").isEmpty || !(button.emoji ?? "").isEmpty
    }

    /// Reverse-DNS style: letters, digits, `.`, `-`, `_`; at least one dot.
    public static func isBundleID(_ value: String) -> Bool {
        guard value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
                    || scalar == "." || scalar == "-" || scalar == "_")
        }
    }

    /// An absolute `http`/`https` URL with a host.
    public static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty
        else { return false }
        return true
    }

    /// `#RRGGBB` with ASCII hex digits, matching the editor's `/^#[0-9A-Fa-f]{6}$/`.
    /// (`Character.isHexDigit` would also accept full-width digits such as `Ａ`.)
    static func isHexColor(_ value: String) -> Bool {
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
