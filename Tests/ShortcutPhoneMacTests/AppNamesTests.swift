import Testing

@testable import ShortcutPhoneMac

struct AppNamesTests {
    @Test func namesAnInstalledApp() {
        #expect(AppNames().name(for: "com.apple.finder") == "Finder")
    }

    @Test func unknownBundleIdHasNoName() {
        #expect(AppNames().name(for: "com.example.not-installed") == nil)
    }
}
