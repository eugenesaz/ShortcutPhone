import Foundation
import Testing

@testable import ShortcutPhoneCore

/// Tests/Fixtures/capacity.json, shared with the web suite.
private struct CapacityFixtures: Decodable {
    struct Case: Decodable, CustomTestStringConvertible {
        struct Expect: Decodable {
            let page: Int?
            let strip: Int
        }
        let name: String
        let viewports: [Viewport]
        let columns: Int?
        let expect: Expect
        var testDescription: String { name }
    }
    let pixel5: Viewport
    let capacity: [Case]

    static func load() throws -> CapacityFixtures {
        try JSONDecoder().decode(Self.self, from: Fixtures.data("capacity.json"))
    }
}

@Suite struct CapacityTests {
    @Test(arguments: try CapacityFixtures.load().capacity)
    fileprivate func matchesFixture(_ fixture: CapacityFixtures.Case) {
        let capacity = EffectiveCapacity(viewports: fixture.viewports)
        #expect(capacity.page(columns: fixture.columns) == fixture.expect.page)
        #expect(capacity.strip == fixture.expect.strip)
    }

    @Test func pixel5ProfileMatchesFixture() throws {
        #expect(Capacity.pixel5 == (try CapacityFixtures.load().pixel5))
    }

    @Test func defaultProfileGivesAbout55PageAnd6Strip() {
        let capacity = EffectiveCapacity(viewports: [])
        #expect(capacity.page(columns: nil) == 55)
        #expect(capacity.strip == 6)
    }

    @Test func devicesWithoutViewportUseDefaultProfile() {
        let device = Device(
            id: "d1", name: "Pixel", tokenHash: "x", pairedAt: Date(), viewport: nil)
        #expect(EffectiveCapacity(devices: [device]) == EffectiveCapacity(viewports: []))
    }

    @Test func reportedViewportReplacesDefault() {
        let small = Viewport(
            portrait: OrientationLayout(page: Size(w: 120, h: 120), strip: Size(w: 120, h: 72)),
            landscape: OrientationLayout(page: Size(w: 120, h: 120), strip: Size(w: 72, h: 120)))
        let devices = [
            Device(id: "a", name: "A", tokenHash: "x", pairedAt: Date(), viewport: nil),
            Device(id: "b", name: "B", tokenHash: "y", pairedAt: Date(), viewport: small),
        ]
        #expect(EffectiveCapacity(devices: devices).page(columns: nil) == 4)
        #expect(EffectiveCapacity(devices: devices).strip == 2)
    }

    @Test func tileEdgeBoundaries() {
        #expect(Capacity.tiles(along: 55) == 0)
        #expect(Capacity.tiles(along: 56) == 1)
        #expect(Capacity.tiles(along: 119) == 1)
        #expect(Capacity.tiles(along: 120) == 2)
        #expect(Capacity.columnsFit(0, width: 400) == false)
        #expect(Capacity.columnsFit(2, width: 120) == true)
        #expect(Capacity.columnsFit(2, width: 119) == false)
    }
}
