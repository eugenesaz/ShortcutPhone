import Foundation
import ShortcutPhoneCore
import ShortcutPhoneMac
import ShortcutPhoneServer

enum PairingMode: Hashable {
    case wifi
    case usb
}

/// Starts the server and feeds it the frontmost app. Shown in the menu.
@MainActor
@Observable
final class AgentModel {
    private(set) var serverURL: String?
    private(set) var serverError: String?
    private(set) var configError: String?
    /// The current one-time pairing code; `pairingURL` turns it into a link for `pairingMode`.
    private(set) var pairingCode: String?
    private(set) var pairingExpiresAt: Date?
    var pairingMode = PairingMode.wifi
    /// nil when `adb` isn't installed: the menu then only offers Wi-Fi.
    private(set) var usbStatus: UsbStatus?
    private(set) var lanAddress: String?
    /// Polled, because macOS sends no notification when the permission changes.
    private(set) var accessibilityGranted = AccessibilityStatus.isTrusted
    /// Phones with an authenticated socket right now.
    private(set) var phoneCount = 0
    private(set) var launchAtLogin = LaunchAtLogin.state
    private(set) var launchAtLoginError: String?
    private var port = Config.defaultPort
    /// The server's per-launch editor key, passed to the editor in the URL fragment.
    private var editorKey: String?

    private let hub: WebSocketHub
    private let configStore = ConfigStore(
        starter: Bundle.main.url(forResource: "starter-config", withExtension: "json"))
    private(set) var pairing: PairingService?
    private let monitor = FrontmostAppMonitor()

    init() {
        let (config, error) = configStore.loadedAtStart
        configError = error.map { Self.describe($0, keptLastGood: false) }
        let appNames = AppNames()
        hub = WebSocketHub(config: config, frontmost: nil, appName: { appNames.name(for: $0) })

        let pairing: PairingService
        do {
            pairing = try PairingService(store: DeviceFileStore())
        } catch {
            // Never start with an empty device list: the next save would overwrite the file.
            serverError = "Cannot read devices.json: \(error.localizedDescription)"
            return
        }
        self.pairing = pairing

        let port = config.server.port
        self.port = port
        lanAddress = NetworkAddress.lanIPv4()
        serverURL = lanAddress.map { "http://\($0):\(port)" }
        let timing = OSLogTiming()
        let dispatcher = PressDispatcher(
            launcher: WorkspaceAppLauncher(), typer: MacTextTyper(),
            accessibility: SystemAccessibility(), frontmost: monitor, timing: timing)
        let server = AgentServer(
            hub: hub, pairing: pairing, configStore: configStore, dispatcher: dispatcher,
            icons: IconRenderer(), apps: WorkspaceInstalledApps(),
            webRoot: Self.webRoot(), port: port, timing: timing)
        editorKey = server.editorKey
        Task.detached { [weak self] in
            do {
                try await server.application().runService(gracefulShutdownSignals: [])
            } catch {
                await self?.serverFailed(error)
            }
        }
        Task { [weak self, hub] in
            for await count in await hub.connectionCounts() {
                self?.phoneCount = count
            }
        }
        Task { [hub, monitor] in
            for await app in monitor.changes() {
                await hub.setFrontmost(app, changedAt: .now)
            }
        }
        // Saves from the editor and external edits of config.json reach phones and the menu.
        Task { [weak self, hub, configStore] in
            let events = await configStore.events()
            Task.detached { await configStore.watch() }
            for await event in events {
                switch event {
                case .loaded(let config):
                    await hub.setConfig(config)
                    self?.configError = nil
                case .invalid(let error):
                    self?.configError = Self.describe(error, keptLastGood: true)
                }
            }
        }
        Task { [weak self] in
            while let self {
                self.accessibilityGranted = AccessibilityStatus.isTrusted
                self.launchAtLogin = LaunchAtLogin.state
                try? await Task.sleep(for: .seconds(2))
            }
        }
        Task { [weak self] in
            while let self {
                await self.refreshUsb()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Re-runs `adb reverse` for every ready phone each time: a phone reboot, a replug or an adb
    /// server restart all drop the forward, and repeating it is harmless.
    private func refreshUsb() async {
        guard let adb = AdbBridge.find() else {
            usbStatus = nil
            return
        }
        let devices = await adb.devices()
        for device in devices where device.state == .ready {
            await adb.reverse(serial: device.serial, port: port)
        }
        usbStatus = UsbStatus(devices: devices)
    }

    var pairingURL: String? {
        guard let pairingCode else { return nil }
        let host: String? =
            switch pairingMode {
            case .wifi: lanAddress
            case .usb: "localhost"
            }
        return host.map { "http://\($0):\(port)/pair?code=\(pairingCode)" }
    }

    var usbURL: String { "http://localhost:\(port)" }

    /// The editor, on loopback only (the agent refuses it from the LAN). The key goes in the
    /// fragment, which the browser never sends to the server.
    var editorURL: URL? {
        editorKey.flatMap { URL(string: "http://127.0.0.1:\(port)/editor#key=\($0)") }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at Login failed: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAtLogin.state
    }

    /// Makes a fresh one-time code (the old one stays valid until it expires).
    func newPairingCode() {
        guard let pairing else { return }
        lanAddress = NetworkAddress.lanIPv4()
        Task {
            let code = await pairing.createCode()
            pairingExpiresAt = code.expiresAt
            pairingCode = code.value
        }
    }

    private func serverFailed(_ error: any Error) {
        serverError = "Server stopped: \(error)"
    }

    /// The built web UI: inside the app bundle, or `SHORTCUTPHONE_WEB_ROOT` during development.
    private static func webRoot() -> String? {
        if let override = ProcessInfo.processInfo.environment["SHORTCUTPHONE_WEB_ROOT"] {
            return override
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("web"),
            FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path)
        else { return nil }
        return url.path
    }

    private static func describe(_ error: ConfigError, keptLastGood: Bool) -> String {
        (keptLastGood
            ? "config.json is invalid; the last good config stays active:\n"
            : "config.json is invalid:\n")
            + error.issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
    }
}
