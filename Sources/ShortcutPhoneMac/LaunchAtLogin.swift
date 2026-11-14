import ServiceManagement

/// Starts the app at login via `SMAppService.mainApp` (a login item that points at this bundle).
public enum LaunchAtLogin {
    public enum State: Equatable, Sendable {
        case on
        case off
        /// Registered, but switched off in System Settings › General › Login Items.
        case needsApproval
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    public static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
