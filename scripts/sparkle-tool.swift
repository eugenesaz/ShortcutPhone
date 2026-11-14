// Release-side helper for Sparkle updates, using CryptoKit's Ed25519 (the same signatures
// Sparkle verifies). Compiled and run by scripts/sparkle.sh.
//
//   generate-key <dir>     new key pair: <dir>/sparkle-private-key.txt (base64 seed, a secret),
//                          prints the public key for Info.plist's SUPublicEDKey
//   public-key             prints the public key for SPARKLE_PRIVATE_KEY
//   appcast <version> <zip> <download-url> <notes.md> <expected-public-key>
//                          prints appcast.xml for one release, signed with SPARKLE_PRIVATE_KEY.
//                          Fails if the key doesn't match <expected-public-key>, so a wrong
//                          secret can't publish updates that no installed app would accept.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sparkle-tool: \(message)\n".utf8))
    exit(1)
}

func privateKeyFromEnvironment() -> Curve25519.Signing.PrivateKey {
    guard let encoded = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
        let seed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("SPARKLE_PRIVATE_KEY is missing or not base64") }
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
        fail("SPARKLE_PRIVATE_KEY is not a 32-byte Ed25519 seed")
    }
    return key
}

func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// CHANGELOG bullets ("- text", continued on indented lines) as an HTML list.
func notesHTML(_ markdown: String) -> String {
    var items: [String] = []
    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            items.append(String(trimmed.dropFirst(2)))
        } else if !trimmed.isEmpty, let last = items.popLast() {
            items.append(last + " " + trimmed)
        } else if !trimmed.isEmpty {
            items.append(trimmed)
        }
    }
    guard !items.isEmpty else { return "<p>See the changelog.</p>" }
    return "<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "generate-key":
    guard args.count == 2 else { fail("usage: generate-key <dir>") }
    let key = Curve25519.Signing.PrivateKey()
    let dir = URL(fileURLWithPath: args[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("sparkle-private-key.txt")
    guard !FileManager.default.fileExists(atPath: file.path) else {
        fail("\(file.path) exists; refusing to overwrite a key")
    }
    FileManager.default.createFile(
        atPath: file.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "public-key":
    print(privateKeyFromEnvironment().publicKey.rawRepresentation.base64EncodedString())

case "appcast":
    guard args.count == 6 else {
        fail("usage: appcast <version> <zip> <download-url> <notes.md> <expected-public-key>")
    }
    let (version, zipPath, url, notesPath, expected) = (args[1], args[2], args[3], args[4], args[5])
    let key = privateKeyFromEnvironment()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    guard publicKey == expected else {
        fail(
            "SPARKLE_PRIVATE_KEY's public key \(publicKey) doesn't match SUPublicEDKey \(expected)")
    }
    guard let zip = FileManager.default.contents(atPath: zipPath) else {
        fail("can't read \(zipPath)")
    }
    let signature = try key.signature(for: zip)
    guard key.publicKey.isValidSignature(signature, for: zip) else {
        fail("signature check failed")
    }
    let notes = (try? String(contentsOfFile: notesPath, encoding: .utf8)) ?? ""
    let date = DateFormatter()
    date.locale = Locale(identifier: "en_US_POSIX")
    date.timeZone = TimeZone(identifier: "UTC")
    date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    print(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>ShortcutPhone</title>
            <item>
              <title>Version \(escape(version))</title>
              <pubDate>\(date.string(from: Date()))</pubDate>
              <sparkle:version>\(escape(version))</sparkle:version>
              <sparkle:shortVersionString>\(escape(version))</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
              <description><![CDATA[\(notesHTML(notes))]]></description>
              <enclosure url="\(escape(url))" length="\(zip.count)" type="application/octet-stream" sparkle:edSignature="\(signature.base64EncodedString())"/>
            </item>
          </channel>
        </rss>
        """)

default:
    fail("usage: generate-key <dir> | public-key | appcast …")
}
