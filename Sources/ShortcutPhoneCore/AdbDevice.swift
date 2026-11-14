/// An Android device as listed by `adb devices -l`. Used for the USB connection: the agent runs
/// `adb reverse` so the phone reaches it at `http://localhost:<port>` over the cable, which
/// works when a VPN blocks the local network.
public struct AdbDevice: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// USB debugging allowed; `adb reverse` will work.
        case ready
        /// The phone hasn't accepted this Mac's USB debugging key yet.
        case unauthorized
        case offline
        case other(String)
    }

    public let serial: String
    public let state: State
    /// From `model:Pixel_5`, with underscores as spaces.
    public let model: String?

    public init(serial: String, state: State, model: String?) {
        self.serial = serial
        self.state = state
        self.model = model
    }

    /// Parses `adb devices -l` output. Daemon start-up chatter and the header are skipped.
    public static func parseList(_ output: String) -> [AdbDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, !line.hasPrefix("*"), !line.hasPrefix("List of devices")
            else { return nil }
            let state: State =
                switch fields[1] {
                case "device": .ready
                case "unauthorized": .unauthorized
                case "offline": .offline
                default: .other(fields[1])
                }
            let model = fields.dropFirst(2).first { $0.hasPrefix("model:") }
                .map { $0.dropFirst("model:".count).replacingOccurrences(of: "_", with: " ") }
            return AdbDevice(serial: fields[0], state: state, model: model)
        }
    }

    /// `adb` arguments that forward the phone's `localhost:<port>` to this Mac's same port.
    public static func reverseArguments(serial: String, port: Int) -> [String] {
        ["-s", serial, "reverse", "tcp:\(port)", "tcp:\(port)"]
    }
}

/// What the menu shows about the USB connection.
public enum UsbStatus: Equatable, Sendable {
    case noPhone
    case needsAuthorization
    case connected(name: String)

    public init(devices: [AdbDevice]) {
        if let ready = devices.first(where: { $0.state == .ready }) {
            self = .connected(name: ready.model ?? ready.serial)
        } else if devices.contains(where: { $0.state == .unauthorized }) {
            self = .needsAuthorization
        } else {
            self = .noPhone
        }
    }
}
