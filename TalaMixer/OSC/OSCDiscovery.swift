//
//  OSCDiscovery.swift
//  TalaMixer
//
//  Finds X-Air mixers on the local network.
//
//  iOS refuses UDP broadcast for third-party apps (it's gated behind a special
//  multicast entitlement), so a `/xinfo` to 255.255.255.255 silently goes
//  nowhere. Instead this sweeps the local subnet with *unicast* `/xinfo`
//  probes — one small packet per address — which needs no entitlement and is
//  how the established mixer controllers do it. Every X-Air answers `/xinfo`
//  with four strings: IP, name, model, firmware.
//

import Darwin
import Foundation

final class OSCDiscovery {
    struct Found: Identifiable, Equatable {
        var ip: String
        var name: String
        var model: String
        var firmware: String
        var id: String { ip }
    }

    private let queue = DispatchQueue(label: "com.talamixer.discovery")
    private var socket: Int32 = -1
    private var source: DispatchSourceRead?
    private var sweepTimer: DispatchSourceTimer?
    private var probeTimer: DispatchSourceTimer?

    /// Called on the main queue each time a new mixer answers.
    var onFound: ((Found) -> Void)?

    private var seen: Set<String> = []
    private var targets: [UInt32] = []      // host-order IPv4 addresses to probe
    private var cursor = 0
    private var port: UInt16 = 10024

    /// Probes per tick. 24 every 40 ms sweeps a /24 in under half a second
    /// without stressing the Wi-Fi.
    private let probesPerTick = 24

    func start(port: UInt16 = 10024) {
        stop()
        seen = []
        self.port = port

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        socket = fd

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind an ephemeral port so replies come back to us.
        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = INADDR_ANY
        local.sin_port = 0
        let bound = withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { stop(); return }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in self?.drain() }
        readSource.resume()
        source = readSource

        // Re-plan and restart the sweep every few seconds while the panel is
        // open — Wi-Fi can come up, or the desk can boot, mid-search.
        let sweep = DispatchSource.makeTimerSource(queue: queue)
        sweep.schedule(deadline: .now(), repeating: .seconds(4))
        sweep.setEventHandler { [weak self] in self?.beginSweep() }
        sweep.resume()
        sweepTimer = sweep

        // Paced prober, driven from the target list the sweep builds.
        let probe = DispatchSource.makeTimerSource(queue: queue)
        probe.schedule(deadline: .now(), repeating: .milliseconds(40))
        probe.setEventHandler { [weak self] in self?.probeTick() }
        probe.resume()
        probeTimer = probe
    }

    func stop() {
        sweepTimer?.cancel(); sweepTimer = nil
        probeTimer?.cancel(); probeTimer = nil
        source?.cancel(); source = nil
        if socket >= 0 { close(socket); socket = -1 }
        targets = []
        cursor = 0
    }

    // MARK: Sweep planning

    /// Builds the list of addresses to probe from every usable IPv4 interface.
    private func beginSweep() {
        var planned: [UInt32] = []

        for interface in Self.localIPv4Interfaces() {
            let ip = interface.address
            var mask = interface.netmask

            // Cap enormous subnets at the /24 around our own address —
            // sweeping a /16 would be 65k packets for little gain.
            if mask.nonzeroBitCount < 24 {
                mask = 0xFFFF_FF00
            }

            let network = ip & mask
            let hostBits = ~mask
            guard hostBits > 0 else { continue }

            // Our own address is deliberately included — it costs one packet
            // and keeps the sweep honest in NAT/bridged setups.
            for host in 1..<hostBits {
                planned.append(network | host)
            }
        }

        guard !planned.isEmpty else { return }
        targets = planned
        cursor = 0
    }

    private func probeTick() {
        guard socket >= 0, cursor < targets.count else { return }
        let payload = [UInt8](OSCMessage("/xinfo").encoded())

        let end = min(cursor + probesPerTick, targets.count)
        for index in cursor..<end {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = targets[index].bigEndian

            _ = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(socket, payload, payload.count, 0, sa,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        cursor = end
    }

    // MARK: Replies

    private func drain() {
        guard socket >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let n = withUnsafeMutablePointer(to: &from) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(socket, &buffer, buffer.count, 0, sa, &fromLen)
            }
        }
        guard n > 0 else { return }

        // The socket address the reply physically came from — more trustworthy
        // than whatever IP string the firmware puts in the message.
        var addr = from.sin_addr
        var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &name, socklen_t(INET_ADDRSTRLEN))
        let sourceIP = String(cString: name)

        let data = Data(buffer[0..<n])
        for message in OSCMessage.decode(data) where message.address.hasSuffix("xinfo") {
            let strings = message.values.compactMap { $0.stringValue }
            guard strings.count >= 4 else { continue }
            let found = Found(ip: sourceIP.isEmpty ? strings[0] : sourceIP,
                              name: strings[1], model: strings[2], firmware: strings[3])
            guard !seen.contains(found.ip) else { continue }
            seen.insert(found.ip)
            DispatchQueue.main.async { self.onFound?(found) }
        }
    }

    // MARK: Interfaces

    private struct Interface {
        var address: UInt32     // host order
        var netmask: UInt32     // host order
    }

    /// IPv4 addresses of the device's non-loopback interfaces (Wi-Fi and wired
    /// adapters both matter — the desk might hang off a USB-C ethernet dongle).
    private static func localIPv4Interfaces() -> [Interface] {
        var results: [Interface] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return results }
        defer { freeifaddrs(list) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let sa = current.pointee.ifa_addr,
                  sa.pointee.sa_family == sa_family_t(AF_INET),
                  let maskSA = current.pointee.ifa_netmask else { continue }

            // Skip the awdl/llw peer-to-peer interfaces — they're never the LAN.
            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("awdl"), !name.hasPrefix("llw"),
                  !name.hasPrefix("utun"), !name.hasPrefix("pdp_ip") else { continue }

            let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let mask = maskSA.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            // 169.254.x.x link-local means no DHCP — probing it is noise.
            guard (ip >> 24) != 169 || ((ip >> 16) & 0xFF) != 254 else { continue }

            results.append(Interface(address: ip, netmask: mask))
        }
        return results
    }
}
