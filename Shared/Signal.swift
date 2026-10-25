import Foundation

/// Darwin notifications work between an app and its extension without any
/// shared container, so they tell the app the screen reader is alive.
enum Signal {
    static let started = "com.atomawayg.sian.started"
    static let frame = "com.atomawayg.sian.frame"
    static let stopped = "com.atomawayg.sian.stopped"
    // clip recording: the app asks the screen reader to start / stop; the reader answers how it went
    static let clipStart = "com.atomawayg.sian.clip.start"
    static let clipStop = "com.atomawayg.sian.clip.stop"
    static let clipRecording = "com.atomawayg.sian.clip.recording"
    static let clipSaved = "com.atomawayg.sian.clip.saved"
    static let clipFailed = "com.atomawayg.sian.clip.failed"
    static let clipNoAccess = "com.atomawayg.sian.clip.noaccess"

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

/// Sends a whole board as a burst of Darwin notifications: begin, one name per cell value, a checksum, then a commit.
/// iOS may drop or reorder Darwin notifications, so the app only accepts a board when its checksum matches
/// (a broken burst is ignored; the extension re-sends the board at least once a second).
enum DarwinBoard {
    static let prefix = "com.atomawayg.sian.b."
    static let maxCells = max(JK.count, SK.count, PoolCodec.count)
    static let values = 14
    static func names() -> [String] {
        var n: [String] = []
        for i in 0..<maxCells { for v in 0..<values { n.append(prefix + "c\(i)v\(v)") } }
        for g in 0..<9 { n.append(prefix + "g\(g)") }
        for v in 0..<5 { n.append(prefix + "me\(v)") }
        for v in 0..<16 { n.append(prefix + "ha\(v)"); n.append(prefix + "hb\(v)") }
        n += [prefix + "turn0", prefix + "turn1", prefix + "valid0", prefix + "valid1", prefix + "begin", prefix + "commit"]
        return n
    }
    /// 8-bit checksum over everything in the message (same on both sides).
    static func checksum(valid: Bool, game: Int, cells: [Int], me: Int, turn: Bool) -> Int {
        var h: UInt32 = 2166136261
        func mix(_ v: Int) { h = (h ^ UInt32(truncatingIfNeeded: v & 0xff)) &* 16777619 }
        mix(valid ? 1 : 0); mix(game); mix(me); mix(turn ? 1 : 0); mix(cells.count)
        for (i, v) in cells.enumerated() { mix(i); mix(v) }
        return Int((h ^ (h >> 8) ^ (h >> 16) ^ (h >> 24)) & 0xff)
    }
    /// `since`: the board sent just before; only cells that changed are posted (the app keeps the rest).
    /// A lost notification fails the checksum and the next full send (at least once a second) repairs it.
    static func send(_ m: BoardMessage, since: BoardMessage? = nil) {
        let cells = m.valid && m.cells.count <= maxCells ? m.cells.map { max(0, min(values - 1, $0)) } : []
        let h = checksum(valid: m.valid, game: m.game.rawValue, cells: cells, me: m.me, turn: m.myTurn)
        var old: [Int]? = nil
        if let p = since, p.valid, m.valid, p.game == m.game, p.cells.count == m.cells.count { old = p.cells.map { max(0, min(values - 1, $0)) } }
        Signal.post(prefix + "begin")
        Signal.post(prefix + "valid\(m.valid ? 1 : 0)")
        Signal.post(prefix + "g\(m.game.rawValue)")
        for (i, v) in cells.enumerated() where old == nil || old![i] != v { Signal.post(prefix + "c\(i)v\(v)") }
        Signal.post(prefix + "me\(m.me)")
        Signal.post(prefix + "turn\(m.myTurn ? 1 : 0)")
        Signal.post(prefix + "ha\(h >> 4)")
        Signal.post(prefix + "hb\(h & 15)")
        Signal.post(prefix + "commit")
    }
}
