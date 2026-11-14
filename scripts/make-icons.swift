// Draws the ShortcutPhone icon: a 3×3 grid of colored keys on a dark tile.
// Writes web/public/pwa/*.png (PWA) and Resources/AppIcon.icns (Mac app).
// Run: ./scripts/make-icons.sh
import AppKit

let colors: [NSColor] = [
    .init(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),  // blue
    .init(srgbRed: 0.18, green: 0.75, blue: 0.44, alpha: 1),  // green
    .init(srgbRed: 0.98, green: 0.62, blue: 0.16, alpha: 1),  // orange
    .init(srgbRed: 0.66, green: 0.40, blue: 0.95, alpha: 1),  // purple
    .init(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1),  // red
    .init(srgbRed: 0.13, green: 0.73, blue: 0.80, alpha: 1),  // teal
]
let background = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)

/// - Parameters:
///   - inset: Margin around the dark tile, as a fraction of the size (macOS icons have one).
///   - content: Fraction of the dark tile the key grid covers (smaller for maskable icons).
///   - corner: Corner radius of the dark tile as a fraction of its edge; 0 = full bleed.
func render(size: Int, inset: CGFloat, content: CGFloat, corner: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let tile = NSRect(
        x: s * inset, y: s * inset, width: s * (1 - 2 * inset), height: s * (1 - 2 * inset))
    background.setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * corner, yRadius: tile.width * corner)
        .fill()

    let grid = tile.width * content
    let gap = grid * 0.07
    let key = (grid - 2 * gap) / 3
    let origin = CGPoint(x: tile.midX - grid / 2, y: tile.midY - grid / 2)
    for row in 0..<3 {
        for col in 0..<3 {
            let rect = NSRect(
                x: origin.x + CGFloat(col) * (key + gap),
                y: origin.y + CGFloat(2 - row) * (key + gap),
                width: key, height: key)
            colors[(row * 3 + col) % colors.count].setFill()
            NSBezierPath(roundedRect: rect, xRadius: key * 0.22, yRadius: key * 0.22).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let web = root.appendingPathComponent("web/public/pwa")
try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
for size in [192, 512] {
    try render(size: size, inset: 0, content: 0.72, corner: 0.18)
        .write(to: web.appendingPathComponent("icon-\(size).png"))
}
// Maskable: full bleed, keys inside the central safe zone (radius 40%).
try render(size: 512, inset: 0, content: 0.56, corner: 0)
    .write(to: web.appendingPathComponent("icon-maskable-512.png"))

let iconset = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: base * scale, inset: 0.1, content: 0.72, corner: 0.225)
            .write(to: iconset.appendingPathComponent(name))
    }
}
