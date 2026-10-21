import Foundation
import Network

/// Listens on localhost for board readings from the screen-recording extension.
final class Receiver {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "sian.recv")
    var onMessage: ((BoardMessage) -> Void)?
    var onStatus: ((String) -> Void)?
    private var rawFD: Int32 = -1

    func start() {
        startRaw()
        let params = NWParameters.udp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Link.port), let l = try? NWListener(using: params, on: port) else { return }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .main)
            self?.receive(on: conn)
        }
        l.stateUpdateHandler = { [weak self] state in
            self?.onStatus?("\(state)")
            if case .failed = state {
                self?.listener?.cancel()
                self?.queue.asyncAfter(deadline: .now() + 1) { self?.start() }
            }
        }
        l.start(queue: queue)
        listener = l
    }

    /// BSD socket listener on 127.0.0.1:52742, read on a background thread.
    private func startRaw() {
        guard rawFD < 0 else { return }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { onStatus?("raw socket failed"); return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = RawUDP.port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { onStatus?("raw bind failed \(errno)"); close(fd); return }
        rawFD = fd
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = recv(fd, &buf, buf.count, 0)
                if n <= 0 { continue }
                if let m = try? JSONDecoder().decode(BoardMessage.self, from: Data(buf[0..<n])) { self?.onMessage?(m) }
            }
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, let m = try? JSONDecoder().decode(BoardMessage.self, from: data) { self?.onMessage?(m) }
            if error == nil { self?.receive(on: conn) }
        }
    }
}
