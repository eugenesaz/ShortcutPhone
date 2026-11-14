import Foundation
import ShortcutPhoneCore

/// Runs the Android `adb` tool so a USB-connected phone reaches the agent at
/// `http://localhost:<port>` (`adb reverse`). This works when a VPN blocks the local network.
public struct AdbBridge: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// The first `adb` found in the usual install locations (Homebrew, Android Studio).
    public static func find() -> AdbBridge? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { AdbBridge(executable: URL(fileURLWithPath: $0)) }
    }

    public func devices() async -> [AdbDevice] {
        let result = await run(["devices", "-l"])
        return result.status == 0 ? AdbDevice.parseList(result.output) : []
    }

    /// Forwards the phone's `localhost:<port>` to this Mac. Safe to repeat.
    @discardableResult
    public func reverse(serial: String, port: Int) async -> Bool {
        await run(AdbDevice.reverseArguments(serial: serial, port: port)).status == 0
    }

    private func run(_ arguments: [String]) async -> (status: Int32, output: String) {
        let executable = self.executable
        return await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return (-1, "")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
