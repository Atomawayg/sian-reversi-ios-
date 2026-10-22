import Foundation

/// Darwin notifications work between an app and its extension without any
/// shared container, so they tell the app the screen reader is alive.
enum Signal {
    static let started = "com.atomawayg.sian.started"
    static let frame = "com.atomawayg.sian.frame"
    static let stopped = "com.atomawayg.sian.stopped"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Plain BSD UDP socket on 127.0.0.1 (second transport next to Network.framework).
enum RawUDP {
    static let port: UInt16 = 52742

    static func send(_ data: Data) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

/// Sends a whole board as a burst of Darwin notifications: one name per cell value, then a commit.
enum DarwinBoard {
    static let prefix = "com.atomawayg.sian.b."
    static func names() -> [String] {
        var n: [String] = []
        for i in 0..<JK.count { for v in 0..<14 { n.append(prefix + "c\(i)v\(v)") } }
        for g in 0..<5 { n.append(prefix + "g\(g)") }
        for v in 0..<3 { n.append(prefix + "me\(v)") }
        n += [prefix + "turn0", prefix + "turn1", prefix + "valid0", prefix + "valid1", prefix + "commit"]
        return n
    }
    static func send(_ m: BoardMessage) {
        Signal.post(prefix + "valid\(m.valid ? 1 : 0)")
        Signal.post(prefix + "g\(m.game.rawValue)")
        if m.cells.count <= JK.count { for (i, v) in m.cells.enumerated() { Signal.post(prefix + "c\(i)v\(v)") } }
        Signal.post(prefix + "me\(m.me)")
        Signal.post(prefix + "turn\(m.myTurn ? 1 : 0)")
        Signal.post(prefix + "commit")
    }
}
