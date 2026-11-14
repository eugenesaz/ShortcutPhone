import Foundation
import OSLog
import ShortcutPhoneCore

/// Logs each latency sample with the rolling p95, at debug level. Debug messages aren't stored
/// unless someone is streaming them, so this costs nothing in normal use. To watch:
///
///     log stream --level debug --predicate 'subsystem == "io.github.eugenesaz.shortcutphone"'
public final class OSLogTiming: TimingLog, @unchecked Sendable {
    private let logger = Logger(subsystem: "io.github.eugenesaz.shortcutphone", category: "timing")
    private let lock = NSLock()
    private var samples: [TimingEvent: LatencySamples] = [:]

    public init() {}

    public func record(_ event: TimingEvent, _ elapsed: Duration) {
        let p95: Duration? = lock.withLock {
            var stats = samples[event] ?? LatencySamples()
            stats.add(elapsed)
            samples[event] = stats
            return stats.percentile(95)
        }
        let ms = elapsed.milliseconds
        let p95ms = p95?.milliseconds ?? ms
        logger.debug(
            "\(event.rawValue, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms (p95 \(p95ms, format: .fixed(precision: 1), privacy: .public) ms)"
        )
    }
}
