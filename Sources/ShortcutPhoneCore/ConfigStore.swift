import Foundation

/// Owns `config.json`: loads it, keeps the last good config when the file turns invalid,
/// notices external edits, and writes saves atomically.
public actor ConfigStore {
    public enum Event: Equatable, Sendable {
        /// A new valid config is active (saved, or edited on disk).
        case loaded(Config)
        /// The file on disk is invalid; the previous config stays active.
        case invalid(ConfigError)
    }

    public let url: URL
    /// The config and error from `init`, readable without awaiting (for app startup).
    public nonisolated let loadedAtStart: (config: Config, error: ConfigError?)
    public private(set) var config: Config
    /// Set while the file on disk is invalid.
    public private(set) var error: ConfigError?
    private var modified: Date?
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    /// Loads `url`. A missing file gives the empty config; an invalid one gives the empty
    /// config plus `error`, since there is no last good config yet.
    /// - Parameter starter: Written to `url` first if no config exists yet and it is valid, so a
    ///   first launch has example buttons to try.
    public init(url: URL = ConfigFile.configURL, starter: URL? = nil) {
        self.url = url
        if let starter { Self.install(starter, at: url) }
        modified = Self.modificationDate(url)
        var loaded = Config.empty
        var loadError: ConfigError?
        do {
            loaded = try ConfigFile.load(from: url)
        } catch {
            loadError = error
        }
        config = loaded
        error = loadError
        loadedAtStart = (loaded, loadError)
    }

    /// Writes `config` atomically and makes it active. Validation is the caller's job.
    public func save(_ newConfig: Config) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try newConfig.encoded().write(to: url, options: .atomic)
        modified = Self.modificationDate(url)
        config = newConfig
        error = nil
        emit(.loaded(newConfig))
    }

    /// Re-reads the file if it changed on disk. A deleted file is ignored, since some editors
    /// delete and recreate when saving.
    @discardableResult
    public func reloadIfModified() -> Event? {
        guard let date = Self.modificationDate(url), date != modified else { return nil }
        modified = date
        let event: Event
        do {
            let loaded = try ConfigFile.load(from: url)
            let wasInvalid = error != nil
            error = nil
            guard loaded != config || wasInvalid else { return nil }
            config = loaded
            event = .loaded(loaded)
        } catch {
            guard error != self.error else { return nil }
            self.error = error
            event = .invalid(error)
        }
        emit(event)
        return event
    }

    /// Polls the file until the calling task is cancelled.
    public func watch(every interval: Duration = .milliseconds(250)) async {
        while !Task.isCancelled {
            reloadIfModified()
            try? await Task.sleep(for: interval)
        }
    }

    /// Every event from now on.
    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func emit(_ event: Event) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private static func install(_ starter: URL, at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: starter), (try? Config.decode(data)) != nil
        else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
