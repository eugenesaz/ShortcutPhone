import AppKit
import ShortcutPhoneMac
import SwiftUI

/// "Pair Phone…": a QR code with the one-time pairing link.
@MainActor
final class PairingWindow {
    private var window: NSWindow?

    func show(agent: AgentModel) {
        if case .connected = agent.usbStatus { agent.pairingMode = .usb }
        agent.newPairingCode()
        let window = self.window ?? makeWindow(agent: agent)
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(agent: AgentModel) -> NSWindow {
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: PairingView(agent: agent)))
        window.title = "Pair Phone"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}

struct PairingView: View {
    let agent: AgentModel

    var body: some View {
        VStack(spacing: 16) {
            Picker("Connection", selection: mode) {
                Text("Wi-Fi").tag(PairingMode.wifi)
                Text("USB").tag(PairingMode.usb)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if agent.pairingMode == .usb {
                Text(usbHint).font(.caption).foregroundStyle(.secondary)
            }
            if let url = agent.pairingURL, let qr = QRCode.image(for: url) {
                Image(decorative: qr, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 260, height: 260)
                Text("Scan with the phone's camera, then open the link in Chrome.")
                    .font(.callout)
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if let expires = agent.pairingExpiresAt {
                    Text("Code expires at \(expires.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if agent.pairingMode == .wifi, agent.lanAddress == nil {
                Text("No network address found. Connect this Mac to Wi-Fi or Ethernet.")
            } else {
                ProgressView()
            }
            Button("New Code") { agent.newPairingCode() }
        }
        .padding(24)
        .frame(width: 360)
    }

    /// No `@State`/`@Bindable` macros with these Command Line Tools, so bind by hand.
    private var mode: Binding<PairingMode> {
        Binding(get: { agent.pairingMode }, set: { agent.pairingMode = $0 })
    }

    private var usbHint: String {
        switch agent.usbStatus {
        case .connected(let name): "\(name) is connected over USB."
        case .needsAuthorization: "Allow USB debugging on the phone, then wait a few seconds."
        case .noPhone: "Connect the phone by USB with USB debugging on."
        case nil: "Install adb for USB: brew install --cask android-platform-tools"
        }
    }
}
