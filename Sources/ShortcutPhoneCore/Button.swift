/// What a button does when pressed.
public enum ButtonAction: Equatable, Sendable {
    /// Launch the app, or bring it to the front if it is running.
    case app(bundleId: String)
    /// Paste the text into the frontmost app, then press Return.
    case text(String)
    /// Send a key combo such as `cmd+shift+p` or a single key such as `1`.
    case keys(String)
    /// Open a web page in the page's app (a browser). Page buttons only.
    case url(String)
    /// A group of buttons the phone opens in place of the page grid. Page buttons only, and
    /// never nested. Pressing the folder itself does nothing on the Mac.
    case folder(Folder)
}

/// What the phone does after a button in a folder is tapped.
public enum AfterPress: String, Codable, Equatable, Sendable {
    /// Return to the page grid.
    case back
    /// Keep the folder open.
    case stay
}

public struct Folder: Equatable, Sendable {
    public var afterPress: AfterPress
    /// Optional fixed column count (1–8). `nil` lets the phone pick.
    public var columns: Int?
    public var buttons: [Button]

    public init(afterPress: AfterPress = .back, columns: Int? = nil, buttons: [Button] = []) {
        self.afterPress = afterPress
        self.columns = columns
        self.buttons = buttons
    }
}

public struct Button: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String?
    public var emoji: String?
    /// `#RRGGBB`.
    public var color: String?
    /// Global strip only: shown before the unpinned apps. Written to JSON only when true.
    public var pinned: Bool
    public var action: ButtonAction

    public init(
        id: String, label: String? = nil, emoji: String? = nil, color: String? = nil,
        pinned: Bool = false, action: ButtonAction
    ) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.color = color
        self.pinned = pinned
        self.action = action
    }
}

extension Button: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, type, label, emoji, color, pinned, bundleId, text, keys, url
        case afterPress, columns, buttons
    }

    private enum Kind: String, Codable {
        case app, text, keys, url, folder
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        switch try c.decode(Kind.self, forKey: .type) {
        case .app: action = .app(bundleId: try c.decode(String.self, forKey: .bundleId))
        case .text: action = .text(try c.decode(String.self, forKey: .text))
        case .keys: action = .keys(try c.decode(String.self, forKey: .keys))
        case .url: action = .url(try c.decode(String.self, forKey: .url))
        case .folder:
            action = .folder(
                Folder(
                    afterPress: try c.decodeIfPresent(AfterPress.self, forKey: .afterPress)
                        ?? .back,
                    columns: try c.decodeIfPresent(Int.self, forKey: .columns),
                    buttons: try c.decode([Button].self, forKey: .buttons)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch action {
        case .app(let bundleId):
            try c.encode(Kind.app, forKey: .type)
            try c.encode(bundleId, forKey: .bundleId)
        case .text(let text):
            try c.encode(Kind.text, forKey: .type)
            try c.encode(text, forKey: .text)
        case .keys(let keys):
            try c.encode(Kind.keys, forKey: .type)
            try c.encode(keys, forKey: .keys)
        case .url(let url):
            try c.encode(Kind.url, forKey: .type)
            try c.encode(url, forKey: .url)
        case .folder(let folder):
            try c.encode(Kind.folder, forKey: .type)
            try c.encode(folder.afterPress, forKey: .afterPress)
            try c.encode(folder.columns, forKey: .columns)  // explicit null, as on pages
            try c.encode(folder.buttons, forKey: .buttons)
        }
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(color, forKey: .color)
        if pinned { try c.encode(true, forKey: .pinned) }
    }
}

extension Button {
    /// The folder's contents, if this button is a folder.
    public var folder: Folder? {
        if case .folder(let folder) = action { return folder }
        return nil
    }
}
