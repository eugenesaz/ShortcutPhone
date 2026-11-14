import AppKit
import ShortcutPhoneCore

/// Renders app icons to PNG at the requested pixel size, cached in memory.
public actor IconRenderer: IconProvider {
    private var cache: [String: Data] = [:]

    public init() {}

    public func pngIcon(bundleId: String, size: Int) async -> Data? {
        let key = "\(bundleId)@\(size)"
        if let cached = cache[key] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
            let png = Self.render(NSWorkspace.shared.icon(forFile: url.path), size: size)
        else { return nil }
        cache[key] = png
        return png
    }

    private static func render(_ icon: NSImage, size: Int) -> Data? {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
