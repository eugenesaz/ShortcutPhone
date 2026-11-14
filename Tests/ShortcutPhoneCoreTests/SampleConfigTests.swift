import Foundation
import Testing

@testable import ShortcutPhoneCore

/// The config a first launch installs (copied into the app bundle by `scripts/bundle.sh`).
@Test func starterConfigIsValid() throws {
    let url = Fixtures.root.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/starter-config.json")
    let config = try Config.decode(Data(contentsOf: url))
    #expect(config.pages.count == 2)
}
