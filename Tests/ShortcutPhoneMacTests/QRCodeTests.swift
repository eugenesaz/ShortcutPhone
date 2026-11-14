import CoreImage
import Testing

@testable import ShortcutPhoneMac

@Suite struct QRCodeTests {
    @Test func encodesThePairingURL() throws {
        let url = "http://192.168.1.20:8765/pair?code=0123456789abcdef0123456789abcdef"
        let image = try #require(QRCode.image(for: url))
        #expect(image.width >= 250)
        #expect(image.width == image.height)

        let detector = try #require(
            CIDetector(
                ofType: CIDetectorTypeQRCode, context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image))
        let decoded = (features.first as? CIQRCodeFeature)?.messageString
        #expect(decoded == url)
    }
}
