import ShortcutPhoneMac
import SwiftUI

@main
struct ShortcutPhoneApp: App {
    private let agent = AgentModel()
    private let pairingWindow = PairingWindow()

    var body: some Scene {
        MenuBarExtra("ShortcutPhone", systemImage: "iphone") {
            AgentMenu(agent: agent)
            Button("Open Editor…") {
                if let url = agent.editorURL { NSWorkspace.shared.open(url) }
            }
            .disabled(agent.pairing == nil)
            Button("Pair Phone…") { pairingWindow.show(agent: agent) }
                .disabled(agent.pairing == nil)
            Divider()
            LoginItemMenu(agent: agent)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

struct AgentMenu: View {
    let agent: AgentModel

    private var phonesText: String {
        switch agent.phoneCount {
        case 0: "No phones connected"
        case 1: "1 phone connected"
        default: "\(agent.phoneCount) phones connected"
        }
    }

    var body: some View {
        if let error = agent.serverError {
            Text(error)
        } else if let url = agent.serverURL {
            Text("Wi-Fi: \(url)")
        } else {
            Text("Wi-Fi: no network address found")
        }
        switch agent.usbStatus {
        case .connected(let name): Text("USB: \(name) — \(agent.usbURL)")
        case .needsAuthorization: Text("USB: allow USB debugging on the phone")
        case .noPhone: Text("USB: no phone connected")
        case nil: EmptyView()
        }
        Text(phonesText)
        if let error = agent.configError {
            Text(error)
        }
        if agent.accessibilityGranted {
            Text("Accessibility: granted")
        } else {
            Button("Accessibility: not granted — Open Settings…") {
                AccessibilityStatus.openSettings()
            }
        }
    }
}

struct LoginItemMenu: View {
    let agent: AgentModel

    var body: some View {
        Toggle("Launch at Login", isOn: launchAtLogin)
        if agent.launchAtLogin == .needsApproval {
            Button("Launch at Login: allow in Login Items settings…") {
                LaunchAtLogin.openSettings()
            }
        }
        if let error = agent.launchAtLoginError {
            Text(error)
        }
    }

    /// No `@State`/`@Bindable` macros with these Command Line Tools, so bind by hand.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { agent.launchAtLogin != .off }, set: { agent.setLaunchAtLogin($0) })
    }
}
