import Testing

@testable import ShortcutPhoneServer

@Suite(.timeLimit(.minutes(1))) struct RoutePolicyTests {
    @Test(arguments: [
        ("/editor", "/editor"), ("/EDITOR.html", "/editor.html"),
        ("/%65ditor.html", "/editor.html"),
        ("//a//b/", "/a/b"), ("/assets/../editor.html", "/editor.html"), ("/./x", "/x"),
        ("/../../etc", "/etc"), ("/", "/"),
    ])
    func normalizesPaths(_ raw: String, _ expected: String) {
        #expect(RoutePolicy.normalize(raw) == expected)
    }

    @Test(arguments: ["/api/config", "/api/devices/dev_1", "/editor", "/Editor.HTML"])
    func editorPathsAreLocalOnly(_ path: String) {
        #expect(RoutePolicy.isLocalOnly(path))
    }

    @Test(arguments: ["/", "/index.html", "/api/pair", "/api/configs", "/editorx", "/icons/a.png"])
    func otherPathsAreNotLocalOnly(_ path: String) {
        #expect(!RoutePolicy.isLocalOnly(path))
    }

    @Test func tokenIsNeededForPhoneAPIOnly() {
        #expect(RoutePolicy.needsDeviceToken("/api/anything"))
        #expect(RoutePolicy.needsDeviceToken("/API/anything"))
        #expect(!RoutePolicy.needsDeviceToken("/api/pair"))
        #expect(!RoutePolicy.needsDeviceToken("/api/config"))
        #expect(!RoutePolicy.needsDeviceToken("/"))
        #expect(!RoutePolicy.needsDeviceToken("/icons/com.apple.Safari.png"))
    }

    @Test(arguments: ["127.0.0.1", "127.0.0.1:8765", "localhost", "LOCALHOST:8765", "[::1]:8765"])
    func acceptsLoopbackHosts(_ host: String) {
        #expect(RoutePolicy.isLoopbackHost(host))
    }

    @Test(arguments: [
        "evil.example", "evil.example:8765", "192.168.1.10:8765", "localhost.evil.example", "",
        "127.0.0.1.evil.example",
    ])
    func rejectsForeignHosts(_ host: String) {
        #expect(!RoutePolicy.isLoopbackHost(host))
    }

    @Test func rejectsMissingHost() {
        #expect(!RoutePolicy.isLoopbackHost(nil))
    }

    @Test func origins() {
        #expect(RoutePolicy.isAllowedOrigin(nil))
        #expect(RoutePolicy.isAllowedOrigin("http://127.0.0.1:8765"))
        #expect(RoutePolicy.isAllowedOrigin("http://localhost:5173"))
        #expect(RoutePolicy.isAllowedOrigin("http://[::1]:8765"))
        #expect(!RoutePolicy.isAllowedOrigin("http://evil.example"))
        #expect(!RoutePolicy.isAllowedOrigin("https://localhost"))
        #expect(!RoutePolicy.isAllowedOrigin("null"))
    }
}
