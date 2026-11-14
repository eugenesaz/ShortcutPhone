/// The buttons shown while one app is frontmost.
public struct Page: Equatable, Sendable {
    public var bundleId: String
    /// Optional fixed column count (1–8). `nil` lets the phone pick.
    public var columns: Int?
    public var buttons: [Button]

    public init(bundleId: String, columns: Int? = nil, buttons: [Button] = []) {
        self.bundleId = bundleId
        self.columns = columns
        self.buttons = buttons
    }
}

extension Page: Codable {
    private enum CodingKeys: String, CodingKey {
        case bundleId, columns, buttons
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
        buttons = try c.decode([Button].self, forKey: .buttons)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleId, forKey: .bundleId)
        try c.encode(columns, forKey: .columns)  // explicit null, as in the spec
        try c.encode(buttons, forKey: .buttons)
    }
}
