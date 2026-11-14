import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// QR codes via CoreImage's built-in generator (no dependency).
public enum QRCode {
    /// A crisp QR image for `text`, `scale` pixels per module.
    public static func image(for text: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
