import Foundation
import Testing

@testable import ShortcutPhoneCore

@Suite struct ConfigStoreTests {
    let dir: URL
    let url: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
    }

    func sample() throws -> Config { try Config.decode(Fixtures.data("config/spec-example.json")) }

    /// Writes as an external editor would, with a modification date that differs for sure.
    func writeExternally(_ data: Data, offset: TimeInterval = 5) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(offset)], ofItemAtPath: url.path)
    }

    @Test func missingFileGivesEmptyConfig() async {
        let store = ConfigStore(url: url)
        #expect(await store.config == .empty)
        #expect(await store.error == nil)
    }

    @Test func missingFileInstallsTheStarter() async throws {
        let starter = dir.appendingPathComponent("starter.json")
        try Fixtures.data("config/spec-example.json").write(to: starter)
        let store = ConfigStore(url: url, starter: starter)
        #expect(await store.config == (try sample()))
        #expect(await store.error == nil)
        #expect(try Config.decode(Data(contentsOf: url)) == (try sample()))
    }

    @Test func existingFileIsNotReplacedByTheStarter() async throws {
        let starter = dir.appendingPathComponent("starter.json")
        try Fixtures.data("config/spec-example.json").write(to: starter)
        try Config.empty.encoded().write(to: url)
        let store = ConfigStore(url: url, starter: starter)
        #expect(await store.config == .empty)
    }

    @Test func invalidStarterIsNotInstalled() async throws {
        let starter = dir.appendingPathComponent("starter.json")
        try Data("{".utf8).write(to: starter)
        let store = ConfigStore(url: url, starter: starter)
        #expect(await store.config == .empty)
        #expect(await store.error == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func loadsValidFile() async throws {
        try Fixtures.data("config/spec-example.json").write(to: url)
        let store = ConfigStore(url: url)
        #expect(await store.config == (try sample()))
    }

    @Test func invalidFileAtStartGivesEmptyConfigAndError() async throws {
        try Data("{".utf8).write(to: url)
        let store = ConfigStore(url: url)
        #expect(await store.config == .empty)
        #expect(await store.error != nil)
    }

    @Test func saveWritesAtomicallyAndRoundTrips() async throws {
        let store = ConfigStore(url: dir.appendingPathComponent("new/config.json"))
        let config = try sample()
        try await store.save(config)
        let written = try Data(contentsOf: dir.appendingPathComponent("new/config.json"))
        #expect(try Config.decode(written) == config)
        #expect(await store.config == config)
    }

    @Test func saveEmitsLoaded() async throws {
        let store = ConfigStore(url: url)
        var events = await store.events().makeAsyncIterator()
        let config = try sample()
        try await store.save(config)
        #expect(await events.next() == .loaded(config))
    }

    @Test func ownSaveIsNotReportedAsExternalEdit() async throws {
        let store = ConfigStore(url: url)
        try await store.save(try sample())
        #expect(await store.reloadIfModified() == nil)
    }

    @Test func externalValidEditIsLoaded() async throws {
        let store = ConfigStore(url: url)
        try writeExternally(Fixtures.data("config/spec-example.json"))
        #expect(await store.reloadIfModified() == .loaded(try sample()))
        #expect(await store.config == (try sample()))
    }

    @Test func externalInvalidEditKeepsLastGoodConfig() async throws {
        let store = ConfigStore(url: url)
        let good = try sample()
        try await store.save(good)
        try writeExternally(Data(#"{"version": 1, "global": "nope"}"#.utf8))
        guard case .invalid(let error)? = await store.reloadIfModified() else {
            Issue.record("expected .invalid")
            return
        }
        #expect(!error.issues.isEmpty)
        #expect(await store.config == good)
        #expect(await store.error == error)

        // Fixing the file clears the error, even though the config is unchanged.
        try writeExternally(good.encoded(), offset: 10)
        #expect(await store.reloadIfModified() == .loaded(good))
        #expect(await store.error == nil)
    }

    @Test func deletedFileKeepsConfig() async throws {
        let store = ConfigStore(url: url)
        try await store.save(try sample())
        try FileManager.default.removeItem(at: url)
        #expect(await store.reloadIfModified() == nil)
        #expect(await store.config == (try sample()))
    }

    @Test func watchPicksUpExternalEditWithinASecond() async throws {
        let store = ConfigStore(url: url)
        var events = await store.events().makeAsyncIterator()
        let watcher = Task { await store.watch(every: .milliseconds(50)) }
        defer { watcher.cancel() }
        let start = ContinuousClock.now
        try writeExternally(Fixtures.data("config/spec-example.json"))
        #expect(await events.next() == .loaded(try sample()))
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}

@Suite struct CapacityIssueTests {
    func config(global: Int, pages: [(columns: Int?, count: Int)]) -> Config {
        let app = { (i: Int) in
            Button(
                id: "g\(i)", label: nil, emoji: nil, color: nil,
                action: .app(bundleId: "com.apple.Notes"))
        }
        let text = { (p: Int, i: Int) in
            Button(id: "p\(p)b\(i)", label: "b", emoji: nil, color: nil, action: .text("t"))
        }
        return Config(
            global: (0..<global).map(app),
            pages: pages.enumerated().map { p, spec in
                Page(
                    bundleId: "com.example.app\(p)", columns: spec.columns,
                    buttons: (0..<spec.count).map { text(p, $0) })
            })
    }

    let pixel5 = EffectiveCapacity(viewports: [])

    @Test func withinCapacityHasNoIssues() {
        #expect(pixel5.issues(in: config(global: 6, pages: [(nil, 55), (2, 10)])).isEmpty)
    }

    @Test func overfullPageIsReportedOnItsButtons() {
        let issues = pixel5.issues(in: config(global: 1, pages: [(nil, 1), (nil, 56)]))
        #expect(issues.map(\.path) == ["pages[1].buttons"])
        #expect(issues.first?.message.contains("holds 55") == true)
    }

    @Test func globalStripHasNoLimit() {
        #expect(pixel5.issues(in: config(global: 40, pages: [])).isEmpty)
    }

    @Test func tooManyColumnsIsReportedOnColumns() {
        let issues = pixel5.issues(in: config(global: 0, pages: [(7, 3)]))
        #expect(issues.map(\.path) == ["pages[0].columns"])
    }

    @Test func columnsOverrideLowersCapacity() {
        let issues = pixel5.issues(in: config(global: 0, pages: [(2, 11)]))
        #expect(issues.map(\.path) == ["pages[0].buttons"])
    }
}
