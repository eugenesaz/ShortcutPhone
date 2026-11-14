import Testing

@testable import ShortcutPhoneCore

@Suite struct AdbDevicesTests {
    @Test func parsesReadyUnauthorizedAndOfflineDevices() {
        let output = """
            * daemon not running; starting now at tcp:5037
            * daemon started successfully
            List of devices attached
            0A1B2C3D               device usb:1-1 product:redfin model:Pixel_5 device:redfin transport_id:3
            ZY22                   unauthorized usb:1-2 transport_id:4
            emulator-5554          offline transport_id:5

            """
        #expect(
            AdbDevice.parseList(output) == [
                AdbDevice(serial: "0A1B2C3D", state: .ready, model: "Pixel 5"),
                AdbDevice(serial: "ZY22", state: .unauthorized, model: nil),
                AdbDevice(serial: "emulator-5554", state: .offline, model: nil),
            ])
    }

    @Test func emptyListHasNoDevices() {
        #expect(AdbDevice.parseList("List of devices attached\n\n").isEmpty)
        #expect(AdbDevice.parseList("").isEmpty)
    }

    @Test func unknownStateIsKept() {
        #expect(
            AdbDevice.parseList("List of devices attached\nX1\tsideload\n")
                == [AdbDevice(serial: "X1", state: .other("sideload"), model: nil)])
    }

    @Test func reverseArgumentsForwardSamePort() {
        #expect(
            AdbDevice.reverseArguments(serial: "0A1B", port: 8765)
                == ["-s", "0A1B", "reverse", "tcp:8765", "tcp:8765"])
    }

    @Test func usbStatusSummarizesDevices() {
        let ready = AdbDevice(serial: "A", state: .ready, model: "Pixel 5")
        let locked = AdbDevice(serial: "B", state: .unauthorized, model: nil)
        #expect(UsbStatus(devices: []) == .noPhone)
        #expect(UsbStatus(devices: [locked]) == .needsAuthorization)
        #expect(UsbStatus(devices: [locked, ready]) == .connected(name: "Pixel 5"))
        #expect(
            UsbStatus(devices: [AdbDevice(serial: "C", state: .ready, model: nil)])
                == .connected(name: "C"))
    }
}
