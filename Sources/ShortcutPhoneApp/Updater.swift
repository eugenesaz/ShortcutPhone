import Foundation
import Sparkle

/// Automatic updates through Sparkle: a daily check of the appcast published with each GitHub
/// release, plus "Check for Updates…" in the menu. Updates are verified with the EdDSA public
/// key in Info.plist (`SUPublicEDKey`) and must be signed with the same certificate as this
/// app, so the Accessibility permission carries over.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    /// nil when not running from a bundle set up for updates (e.g. `swift run`).
    init?(bundle: Bundle = .main) {
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil,
            bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        else { return nil }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
