import Foundation

/// Сетевые данные Mac, нужные для адреса веб-пульта.
enum NetworkInfo {
    /// Локальный IPv4-адрес; интерфейсы `en*` (Wi-Fi/Ethernet) в приоритете.
    static func localIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var best: String?
        var bestPriority = 0
        var cursor = ifaddr
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr
            if (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0,
               addr?.pointee.sa_family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if let addr, getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: ptr.pointee.ifa_name)
                    let priority = name.hasPrefix("en") ? 2 : 1
                    if priority > bestPriority {
                        bestPriority = priority
                        best = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }
        freeifaddrs(ifaddr)
        return best
    }
}
