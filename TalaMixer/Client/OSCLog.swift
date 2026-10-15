//
//  OSCLog.swift
//  TalaMixer
//
//  A bounded ring of recent OSC traffic, behind the OSC Inspector. Handy for
//  confirming the handful of addresses that aren't publicly documented.
//

import Foundation
import Observation

@MainActor
@Observable
final class OSCLog {
    enum Direction: String {
        case inbound = "IN"
        case outbound = "OUT"
    }

    struct Entry: Identifiable {
        let id = UUID()
        var direction: Direction
        var address: String
        var summary: String
        var timestamp: Date

        var timeText: String {
            Entry.formatter.string(from: timestamp)
        }

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()
    }

    /// Logging is off by default — it allocates on every message, and the desk
    /// is chatty.
    var isEnabled = false

    /// Newest first.
    private(set) var entries: [Entry] = []

    private let limit = 400

    func record(_ direction: Direction, _ message: OSCMessage) {
        guard isEnabled else { return }

        let summary = message.values.map(Self.describe).joined(separator: "  ")
        entries.insert(Entry(direction: direction,
                             address: message.address,
                             summary: summary,
                             timestamp: Date()), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    func clear() { entries.removeAll() }

    private static func describe(_ value: OSCValue) -> String {
        switch value {
        case .int(let i): return "\(i)"
        case .float(let f): return String(format: "%.4f", f)
        case .string(let s): return "\"\(s)\""
        case .blob(let d): return "<blob \(d.count) bytes>"
        }
    }
}
