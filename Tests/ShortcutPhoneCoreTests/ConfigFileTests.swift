import Foundation
import Testing

@testable import ShortcutPhoneCore

@Suite struct ConfigFileTests {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConfigFileTests-\(UUID().uuidString)")

    @Test func missingFileGivesEmptyConfig() throws {
        #expect(try ConfigFile.load(from: dir.appendingPathComponent("config.json")) == .empty)
    }

    @Test func loadsExistingFile() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Fixtures.data("config/spec-example.json").write(to: url)
        #expect(try ConfigFile.load(from: url).pages.count == 1)
    }

    @Test func invalidFileThrows() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: url)
        #expect(throws: ConfigError.self) { try ConfigFile.load(from: url) }
    }
}
