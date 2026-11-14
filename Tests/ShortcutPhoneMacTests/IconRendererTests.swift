import AppKit
import Testing

@testable import ShortcutPhoneMac

@Suite struct IconRendererTests {
    @Test func rendersAnInstalledAppAtTheRequestedSize() async throws {
        let png = try #require(await IconRenderer().pngIcon(bundleId: "com.apple.finder", size: 64))
        let image = try #require(NSBitmapImageRep(data: png))
        #expect(image.pixelsWide == 64)
        #expect(image.pixelsHigh == 64)
    }

    @Test func unknownAppHasNoIcon() async {
        #expect(
            await IconRenderer().pngIcon(bundleId: "com.example.does-not-exist", size: 64) == nil)
    }
}
