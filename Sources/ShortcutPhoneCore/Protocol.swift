// WebSocket messages between the phone and the agent. Mirrors web/src/shared/protocol.ts;
// both sides are checked against Tests/Fixtures/protocol.

public struct AppRef: Equatable, Sendable, Codable {
    public var bundleId: String
    public var name: String

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}

/// CSS pixels.
public struct Size: Equatable, Sendable, Codable {
    public var w: Double
    public var h: Double

    public init(w: Double, h: Double) {
        self.w = w
        self.h = h
    }
}

/// Page-area and global-strip sizes for one orientation.
public struct OrientationLayout: Equatable, Sendable, Codable {
    public var page: Size
    public var strip: Size

    public init(page: Size, strip: Size) {
        self.page = page
        self.strip = strip
    }
}

public struct Viewport: Equatable, Sendable, Codable {
    public var portrait: OrientationLayout
    public var landscape: OrientationLayout

    public init(portrait: OrientationLayout, landscape: OrientationLayout) {
        self.portrait = portrait
        self.landscape = landscape
    }
}

public enum PressError: String, Equatable, Sendable, Codable {
    case wrongApp = "wrong_app"
    case noAccessibility = "no_accessibility"
    case launchFailed = "launch_failed"
    case unknownButton = "unknown_button"
}

/// Phone → agent.
public enum ClientMessage: Equatable, Sendable {
    case auth(token: String)
    case press(pressId: String, buttonId: String)
    case viewport(Viewport)
}

public struct StateMessage: Equatable, Sendable {
    public var frontmost: AppRef?
    public var global: [Button]
    public var page: Page?

    public init(frontmost: AppRef?, global: [Button], page: Page?) {
        self.frontmost = frontmost
        self.global = global
        self.page = page
    }
}

/// Agent → phone.
public enum ServerMessage: Equatable, Sendable {
    case state(StateMessage)
    /// `error == nil` means the press succeeded.
    case result(pressId: String, error: PressError?)
}

private enum MessageKeys: String, CodingKey {
    case type, token, pressId, buttonId, portrait, landscape, frontmost, global, page, ok, error
}

extension ClientMessage: Codable {
    private enum Kind: String, Codable {
        case auth, press, viewport
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: MessageKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .auth:
            self = .auth(token: try c.decode(String.self, forKey: .token))
        case .press:
            self = .press(
                pressId: try c.decode(String.self, forKey: .pressId),
                buttonId: try c.decode(String.self, forKey: .buttonId))
        case .viewport:
            self = .viewport(
                Viewport(
                    portrait: try c.decode(OrientationLayout.self, forKey: .portrait),
                    landscape: try c.decode(OrientationLayout.self, forKey: .landscape)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: MessageKeys.self)
        switch self {
        case .auth(let token):
            try c.encode(Kind.auth, forKey: .type)
            try c.encode(token, forKey: .token)
        case .press(let pressId, let buttonId):
            try c.encode(Kind.press, forKey: .type)
            try c.encode(pressId, forKey: .pressId)
            try c.encode(buttonId, forKey: .buttonId)
        case .viewport(let viewport):
            try c.encode(Kind.viewport, forKey: .type)
            try c.encode(viewport.portrait, forKey: .portrait)
            try c.encode(viewport.landscape, forKey: .landscape)
        }
    }
}

extension ServerMessage: Codable {
    private enum Kind: String, Codable {
        case state, result
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: MessageKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .state:
            self = .state(
                StateMessage(
                    frontmost: try c.decode(AppRef?.self, forKey: .frontmost),
                    global: try c.decode([Button].self, forKey: .global),
                    page: try c.decode(Page?.self, forKey: .page)))
        case .result:
            let pressId = try c.decode(String.self, forKey: .pressId)
            if try c.decode(Bool.self, forKey: .ok) {
                self = .result(pressId: pressId, error: nil)
            } else {
                self = .result(
                    pressId: pressId, error: try c.decode(PressError.self, forKey: .error))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: MessageKeys.self)
        switch self {
        case .state(let state):
            try c.encode(Kind.state, forKey: .type)
            try c.encode(state.frontmost, forKey: .frontmost)
            try c.encode(state.global, forKey: .global)
            try c.encode(state.page, forKey: .page)
        case .result(let pressId, let error):
            try c.encode(Kind.result, forKey: .type)
            try c.encode(pressId, forKey: .pressId)
            try c.encode(error == nil, forKey: .ok)
            try c.encodeIfPresent(error, forKey: .error)
        }
    }
}
