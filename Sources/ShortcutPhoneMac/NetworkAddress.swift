import Darwin

/// This Mac's address on the local network.
public enum NetworkAddress {
    /// The first private IPv4 address, preferring Wi-Fi/Ethernet (`en*`) interfaces.
    public static func lanIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, address: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                    NI_NUMERICHOST) == 0
            else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
            guard !address.hasPrefix("169.254.") else { continue }
            candidates.append((String(cString: entry.pointee.ifa_name), address))
        }
        return (candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.address
    }
}
