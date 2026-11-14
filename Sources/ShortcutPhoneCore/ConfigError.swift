/// One problem in a config, pinned to a field path like `pages[0].buttons[1].keys`.
public struct ConfigIssue: Equatable, Sendable, Codable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// A config that failed to decode or validate. Carries every issue found.
public struct ConfigError: Error, Equatable, Sendable {
    public let issues: [ConfigIssue]

    public init(_ issues: [ConfigIssue]) {
        self.issues = issues
    }
}
