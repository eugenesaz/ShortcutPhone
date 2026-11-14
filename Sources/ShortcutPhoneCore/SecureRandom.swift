/// Random secrets: pairing codes, device tokens, the editor key.
public enum SecureRandom {
    /// `bytes` random bytes as lowercase hex.
    public static func hex(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()  // arc4random: cryptographically secure
        return (0..<count).map { _ in
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            return String(byte, radix: 16).leftPadded(to: 2)
        }
        .joined()
    }

    /// Compares secrets without returning early, so timing doesn't leak a matching prefix.
    public static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}
