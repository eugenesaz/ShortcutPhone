import Testing

@testable import ShortcutPhoneMac

@Suite struct InstalledAppsTests {
    @Test func findsSystemAppsAndRunningFinder() async throws {
        let apps = await WorkspaceInstalledApps().apps()
        let notes = try #require(apps.first { $0.bundleId == "com.apple.Notes" })
        #expect(notes.name == "Notes")
        #expect(notes.path.hasSuffix("Notes.app"))
        // Finder lives outside the Applications folders but always runs.
        #expect(apps.first { $0.bundleId == "com.apple.finder" }?.running == true)
    }

    @Test func listsEachBundleOnceSortedByName() async {
        let apps = await WorkspaceInstalledApps().apps()
        #expect(Set(apps.map(\.bundleId)).count == apps.count)
        let names = apps.map(\.name)
        #expect(
            names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
