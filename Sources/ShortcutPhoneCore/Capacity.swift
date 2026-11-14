import Foundation

/// How many buttons fit on a phone without scrolling. Mirrors web/src/shared/capacity.ts;
/// both are checked against Tests/Fixtures/capacity.json.
public enum Capacity {
    /// Smallest tile edge, CSS px.
    public static let minTile: Double = 56
    /// Gap between tiles, CSS px.
    public static let gap: Double = 8

    /// Used until a phone reports its own size: Pixel 5, 393×851 CSS px.
    public static let pixel5 = Viewport(
        portrait: OrientationLayout(page: Size(w: 393, h: 700), strip: Size(w: 393, h: 72)),
        landscape: OrientationLayout(page: Size(w: 700, h: 345), strip: Size(w: 72, h: 393)))

    /// Minimum-size tiles that fit along one edge.
    public static func tiles(along length: Double) -> Int {
        max(0, Int(((length + gap) / (minTile + gap)).rounded(.down)))
    }

    /// Whether `columns` tiles of at least `minTile` fit side by side in `width`.
    public static func columnsFit(_ columns: Int, width: Double) -> Bool {
        columns >= 1 && (width - gap * Double(columns - 1)) / Double(columns) >= minTile
    }

    /// Page capacity of one page area, or `nil` if the `columns` override doesn't fit.
    public static func page(_ size: Size, columns: Int?) -> Int? {
        let rows = tiles(along: size.h)
        guard let columns else { return tiles(along: size.w) * rows }
        return columnsFit(columns, width: size.w) ? columns * rows : nil
    }

    /// Page capacity of one device: the smaller orientation, `nil` if `columns` fails either.
    public static func page(_ viewport: Viewport, columns: Int?) -> Int? {
        guard let portrait = page(viewport.portrait.page, columns: columns),
            let landscape = page(viewport.landscape.page, columns: columns)
        else { return nil }
        return min(portrait, landscape)
    }

    /// Global-strip capacity of one device: one row in portrait, one column in landscape.
    public static func strip(_ viewport: Viewport) -> Int {
        let row = viewport.portrait.strip
        let column = viewport.landscape.strip
        let inRow = tiles(along: row.h) > 0 ? tiles(along: row.w) : 0
        let inColumn = tiles(along: column.w) > 0 ? tiles(along: column.h) : 0
        return min(inRow, inColumn)
    }
}

/// The smallest capacity across all paired devices and both orientations.
public struct EffectiveCapacity: Equatable, Sendable {
    public let viewports: [Viewport]

    /// Falls back to the Pixel 5 profile when no device has reported a size.
    public init(viewports: [Viewport]) {
        self.viewports = viewports.isEmpty ? [Capacity.pixel5] : viewports
    }

    public init(devices: [Device]) {
        self.init(viewports: devices.compactMap(\.viewport))
    }

    /// Max buttons on a page with this `columns` override; `nil` if the override doesn't fit.
    public func page(columns: Int?) -> Int? {
        var result = Int.max
        for viewport in viewports {
            guard let value = Capacity.page(viewport, columns: columns) else { return nil }
            result = min(result, value)
        }
        return result
    }

    /// Global-strip apps that fit without scrolling. Informational: the strip scrolls.
    public var strip: Int {
        viewports.map(Capacity.strip).min() ?? 0
    }
}

extension Viewport {
    /// Every size is finite and between 0 and 10 000 CSS px; anything else is ignored.
    public var isPlausible: Bool {
        [portrait.page, portrait.strip, landscape.page, landscape.strip].allSatisfy { size in
            [size.w, size.h].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 10_000 }
        }
    }
}

extension EffectiveCapacity {
    /// Field-level problems that would hide page buttons or shrink tiles below 56 px. The
    /// global strip has no limit: it scrolls.
    public func issues(in config: Config) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []
        for (index, page) in config.pages.enumerated() {
            guard let max = self.page(columns: page.columns) else {
                issues.append(
                    ConfigIssue(
                        path: "pages[\(index)].columns",
                        message: "\(page.columns ?? 0) columns make tiles smaller than "
                            + "\(Int(Capacity.minTile)) px on a paired phone"))
                continue
            }
            if page.buttons.count > max {
                issues.append(
                    ConfigIssue(
                        path: "pages[\(index)].buttons",
                        message: "\(page.buttons.count) buttons, but the page holds \(max)"))
            }
        }
        return issues
    }
}
