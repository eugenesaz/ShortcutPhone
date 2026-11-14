import Testing

@testable import ShortcutPhoneCore

struct SecureRandomTests {
    @Test func hexHasTwoLowercaseDigitsPerByte() {
        let value = SecureRandom.hex(bytes: 32)
        #expect(value.count == 64)
        #expect(value.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func hexDiffersEachCall() {
        #expect(SecureRandom.hex(bytes: 16) != SecureRandom.hex(bytes: 16))
    }

    @Test func constantTimeEquals() {
        #expect(SecureRandom.constantTimeEquals("abc123", "abc123"))
        #expect(!SecureRandom.constantTimeEquals("abc123", "abc124"))
        #expect(!SecureRandom.constantTimeEquals("abc", "abc123"))
        #expect(SecureRandom.constantTimeEquals("", ""))
    }
}
