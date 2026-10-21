import Foundation
import Network

/// Listens on localhost for board readings from the screen-recording extension.
final class Receiver {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "sian.recv")
    var onMessage: ((BoardMessage) -> Void)?

    func start() {
        let params = NWParameters.udp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Link.port), let l = try? NWListener(using: params, on: port) else { return }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .main)
            self?.receive(on: conn)
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.listener?.cancel()
                self?.queue.asyncAfter(deadline: .now() + 1) { self?.start() }
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, let m = try? JSONDecoder().decode(BoardMessage.self, from: data) { self?.onMessage?(m) }
            if error == nil { self?.receive(on: conn) }
        }
    }
}
