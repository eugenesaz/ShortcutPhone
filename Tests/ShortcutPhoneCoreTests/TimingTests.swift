import Foundation
import Testing

@testable import ShortcutPhoneCore

/// Keeps every recorded sample.
final class RecordingTiming: TimingLog, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(TimingEvent, Duration)] = []

    var events: [TimingEvent] { lock.withLock { recorded.map(\.0) } }
    var samples: [(TimingEvent, Duration)] { lock.withLock { recorded } }

    func record(_ event: TimingEvent, _ elapsed: Duration) {
        lock.withLock { recorded.append((event, elapsed)) }
    }
}

@Suite struct LatencySamplesTests {
    @Test func emptyHasNoPercentile() {
        #expect(LatencySamples().percentile(95) == nil)
    }

    @Test func nearestRankP95() {
        var samples = LatencySamples()
        for ms in 1...100 { samples.add(.milliseconds(ms)) }
        #expect(samples.percentile(95) == .milliseconds(95))
        #expect(samples.percentile(100) == .milliseconds(100))
        #expect(samples.percentile(0) == .milliseconds(1))
    }

    @Test func keepsOnlyTheLastSamples() {
        var samples = LatencySamples(capacity: 3)
        for ms in [500, 500, 500, 1, 2, 3] { samples.add(.milliseconds(ms)) }
        #expect(samples.count == 3)
        #expect(samples.percentile(100) == .milliseconds(3))
    }

    @Test func durationInMilliseconds() {
        #expect(Duration.milliseconds(1500).milliseconds == 1500)
        #expect(abs(Duration.microseconds(250).milliseconds - 0.25) < 1e-9)
    }
}

@Suite struct PressTimingTests {
    let config: Config
    let slack = AppRef(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")

    init() throws {
        config = try Config.decode(Fixtures.data("config/spec-example.json"))
    }

    func run(_ buttonId: String, os: FakeOS, timing: RecordingTiming) async {
        let dispatcher = PressDispatcher(
            launcher: os, typer: os, accessibility: os, frontmost: os, timing: timing)
        try? await dispatcher.handle(buttonId: buttonId, config: config, receivedAt: .now)
    }

    @Test func recordsPressToActionWhenTheActionStarts() async {
        let timing = RecordingTiming()
        await run("btn_3", os: FakeOS(frontmost: slack), timing: timing)
        #expect(timing.events == [.pressToAction])
        #expect(timing.samples.first.map { $0.1 >= .zero && $0.1 < .seconds(1) } == true)
    }

    @Test func recordsNothingWhenThePressIsRefused() async {
        let timing = RecordingTiming()
        await run("btn_3", os: FakeOS(frontmost: nil), timing: timing)  // wrong app
        let untrusted = FakeOS(frontmost: slack)
        await untrusted.set(trusted: false)
        await run("btn_4", os: untrusted, timing: timing)
        #expect(timing.events.isEmpty)
    }

    @Test func recordsNothingWithoutAReceiveTime() async {
        let timing = RecordingTiming()
        let os = FakeOS(frontmost: slack)
        let dispatcher = PressDispatcher(
            launcher: os, typer: os, accessibility: os, frontmost: os, timing: timing)
        try? await dispatcher.handle(buttonId: "btn_1", config: config)
        #expect(timing.events.isEmpty)
    }
}
