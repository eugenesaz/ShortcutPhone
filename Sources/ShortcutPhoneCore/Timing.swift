/// Latency measurements for the success criteria (focus follow ≤ 300 ms, tap → action
/// ≤ 150 ms p95). Recorded through `TimingLog`; the app logs them at debug level only.
public enum TimingEvent: String, Sendable, CaseIterable {
    /// The Mac reported a new frontmost app → its `state` was written to a phone socket.
    case focusToState = "focus→state"
    /// A `press` arrived on the socket → the action's OS call started.
    case pressToAction = "press→action"
}

public protocol TimingLog: Sendable {
    func record(_ event: TimingEvent, _ elapsed: Duration)
}

/// Records nothing (the default, and in tests).
public struct NoTiming: TimingLog {
    public init() {}
    public func record(_ event: TimingEvent, _ elapsed: Duration) {}
}

/// The last `capacity` samples of one event, for a rolling p95.
public struct LatencySamples: Sendable {
    public let capacity: Int
    private var samples: [Duration] = []
    private var next = 0

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { samples.count }

    public mutating func add(_ sample: Duration) {
        if samples.count < capacity {
            samples.append(sample)
        } else {
            samples[next] = sample
        }
        next = (next + 1) % capacity
    }

    /// Nearest-rank percentile, `p` in 0...100; `nil` with no samples.
    public func percentile(_ p: Double) -> Duration? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

extension Duration {
    /// Milliseconds as a `Double`, for logs.
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
