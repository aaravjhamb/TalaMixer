//
//  OSCTransport.swift
//  TalaMixer
//
//  UDP transport for OSC over Network.framework, plus a broadcast probe used to
//  find mixers on the local network.
//

import Foundation
import Network

/// The link state shared by the real transport and the offline demo desk.
enum OSCLinkState: Equatable {
    case idle
    case connecting
    case ready
    case failed(String)
}

/// Anything the client can talk OSC to: a real mixer, or the built-in demo desk.
protocol OSCLink: AnyObject {
    var onMessage: ((OSCMessage) -> Void)? { get set }
    var onState: ((OSCLinkState) -> Void)? { get set }

    func connect(host: String, port: UInt16)
    func disconnect()
    func send(_ message: OSCMessage)
}

/// A bidirectional UDP channel to one mixer.
///
/// The X-Air listens on port 10024 and replies to whatever source port we sent
/// from, so a single connected UDP socket is all we need.
final class OSCTransport: OSCLink {
    typealias State = OSCLinkState

    private let queue = DispatchQueue(label: "com.talamixer.osc", qos: .userInitiated)
    private var connection: NWConnection?

    /// Called on `queue` for every inbound message.
    var onMessage: ((OSCMessage) -> Void)?
    /// Called on `queue` whenever the link state changes.
    var onState: ((OSCLinkState) -> Void)?

    private(set) var host: String = ""
    private(set) var port: UInt16 = 0

    func connect(host: String, port: UInt16) {
        disconnect()
        self.host = host
        self.port = port

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            onState?(.failed("Invalid port \(port)"))
            return
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        // Mixers live on the LAN; never let this ride a cellular link.
        params.prohibitedInterfaceTypes = [.cellular]

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .setup, .preparing:
                self.onState?(.connecting)
            case .ready:
                self.onState?(.ready)
                self.receiveNext()
            case .waiting(let error):
                // UDP "waiting" usually means no route yet — surface it but keep trying.
                self.onState?(.failed(Self.describe(error)))
            case .failed(let error):
                self.onState?(.failed(Self.describe(error)))
            case .cancelled:
                self.onState?(.idle)
            @unknown default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    func send(_ message: OSCMessage) {
        guard let connection, connection.state == .ready else { return }
        connection.send(content: message.encoded(), completion: .idempotent)
    }

    private func receiveNext() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for message in OSCMessage.decode(data) {
                    self.onMessage?(message)
                }
            }
            if error == nil {
                self.receiveNext()
            }
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED:
            return "Connection refused"
        case .posix(let code) where code == .EHOSTUNREACH || code == .ENETUNREACH:
            return "Mixer unreachable — check Wi-Fi"
        case .posix(let code) where code == .ETIMEDOUT:
            return "Timed out"
        default:
            return error.localizedDescription
        }
    }
}
