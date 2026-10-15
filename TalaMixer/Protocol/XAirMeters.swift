//
//  XAirMeters.swift
//  TalaMixer
//
//  Decoding of the mixer's metering blobs.
//
//  A `/meters/N` reply carries one binary blob: a little-endian int32 count,
//  followed by `count` little-endian int16 samples, each of which is dBFS × 256.
//  (Note the mismatch with OSC itself, which is big-endian — the payload inside
//  the blob is little-endian.)
//

import Foundation

enum XAirMeterBank: Int {
    /// Everything, pre-fader: 40 values covering inputs, returns, buses, FX
    /// sends, the main bus and the monitor out. This is the one the mixer view uses.
    case all = 1
    /// All 36 physical/virtual inputs: 16 mic, 2 aux, 18 USB. Used by the
    /// preamp page, since these read ahead of the trim.
    case inputs = 2
    /// The RTA: 100 log-spaced spectrum bins, 20 Hz – 20 kHz, dBFS × 256.
    case rta = 4
}

/// One decoded metering frame, in dBFS.
struct MeterFrame {
    var values: [Double]

    /// Samples at or below this are silence as far as the desk is concerned.
    static let floorDB: Double = -84

    subscript(index: Int) -> Double {
        values.indices.contains(index) ? values[index] : MeterFrame.floorDB
    }

    /// Decodes the blob out of a `/meters/N` message.
    init?(message: OSCMessage) {
        guard let blob = message.values.compactMap({ $0.blobValue }).first else { return nil }
        self.init(blob: blob)
    }

    init?(blob: Data) {
        let bytes = [UInt8](blob)
        guard bytes.count >= 4 else { return nil }

        let count = Int(UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                        | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24))
        guard count > 0, count < 4096 else { return nil }

        let available = (bytes.count - 4) / 2
        let usable = min(count, available)
        guard usable > 0 else { return nil }

        var out = [Double](repeating: MeterFrame.floorDB, count: usable)
        for i in 0..<usable {
            let lo = UInt16(bytes[4 + i * 2])
            let hi = UInt16(bytes[5 + i * 2])
            let raw = Int16(bitPattern: lo | (hi << 8))
            out[i] = max(MeterFrame.floorDB, Double(raw) / 256.0)
        }
        self.values = out
    }
}

// MARK: - Bank layouts

/// Where each strip sits inside a metering frame.
///
/// Layout of `/meters/1` (40 values, all pre-fader except the main bus):
///   0–15  input channels 1–16
///   16–17 aux return L, R
///   18–25 FX returns 1L,1R … 4L,4R
///   26–31 buses 1–6
///   32–35 FX sends 1–4
///   36–37 main bus L, R (post-fader)
///   38–39 monitor out L, R
enum XAirMeterLayout {
    static func index(in bank: XAirMeterBank, for strip: StripID, model: XAirModel) -> Int? {
        switch bank {
        case .all:
            let channels = model.channelCount
            switch strip {
            case .channel(let n):
                return n >= 1 && n <= channels ? n - 1 : nil
            case .auxReturn:
                return channels
            case .fxReturn(let n):
                return channels + 2 + (n - 1) * 2       // left leg of the pair
            case .bus(let n):
                return channels + 2 + model.fxCount * 2 + (n - 1)
            case .fxSend(let n):
                return channels + 2 + model.fxCount * 2 + model.busCount + (n - 1)
            case .main:
                return channels + 2 + model.fxCount * 2 + model.busCount + model.fxCount
            case .dca:
                return nil                              // DCAs aren't metered
            }
        case .inputs:
            switch strip {
            case .channel(let n): return n - 1
            case .auxReturn: return model.channelCount
            default: return nil
            }
        case .rta:
            return nil      // spectrum bins, not per-strip levels
        }
    }

    /// The right leg of a stereo pair, when the strip has one.
    static func rightIndex(in bank: XAirMeterBank, for strip: StripID, model: XAirModel) -> Int? {
        guard bank == .all, let left = index(in: bank, for: strip, model: model) else { return nil }
        switch strip {
        case .auxReturn, .fxReturn, .main: return left + 1
        default: return nil
        }
    }

    /// Index of a USB/card return inside `/meters/2` (16 mic + 2 aux come first).
    static func usbInputIndex(_ n: Int, model: XAirModel) -> Int {
        model.channelCount + 2 + (n - 1)
    }
}

// MARK: - Display scaling

enum XAirMeterScale {
    /// Maps dBFS onto 0...1 of meter height.
    ///
    /// Deliberately not linear-in-dB: real desk meters give the top 20 dB about
    /// a third of the travel so you can actually see what's happening near clip.
    private static let stops: [(db: Double, position: Double)] = [
        (-84, 0.00), (-60, 0.16), (-50, 0.27), (-40, 0.40),
        (-30, 0.54), (-20, 0.68), (-10, 0.84), (-5, 0.92), (0, 1.00),
    ]

    static func position(forDB db: Double) -> Double {
        if db <= stops[0].db { return 0 }
        if db >= 0 { return 1 }
        for i in 1..<stops.count {
            let upper = stops[i]
            if db <= upper.db {
                let lower = stops[i - 1]
                let span = upper.db - lower.db
                let t = span == 0 ? 0 : (db - lower.db) / span
                return lower.position + (upper.position - lower.position) * t
            }
        }
        return 1
    }
}

// MARK: - Meter store

/// Holds the newest meter frame plus per-strip peak hold.
///
/// Kept outside `@Observable` state on purpose: meters arrive up to 50×/second
/// and must not drive SwiftUI invalidation of the whole mixer. Views read this
/// through a `TimelineView` instead.
final class MeterStore {
    private var levels: [Int: Double] = [:]
    private var peaks: [Int: (db: Double, at: Date)] = [:]
    private var inputLevels: [Int: Double] = [:]
    /// Latest RTA frame, dBFS per bin. Empty until the desk sends one.
    private(set) var rtaBins: [Double] = []

    /// How long a peak marker sits before it starts falling.
    private let peakHold: TimeInterval = 1.2
    /// Fall rate once it releases, in dB per second.
    private let peakDecay: Double = 28

    func ingest(_ frame: MeterFrame, bank: XAirMeterBank) {
        switch bank {
        case .all:
            let now = Date()
            for (i, db) in frame.values.enumerated() {
                levels[i] = db
                if let existing = peaks[i], existing.db > db {
                    let elapsed = now.timeIntervalSince(existing.at)
                    if elapsed > peakHold {
                        let decayed = existing.db - (elapsed - peakHold) * peakDecay
                        if decayed <= db { peaks[i] = (db, now) }
                    }
                } else {
                    peaks[i] = (db, now)
                }
            }
        case .inputs:
            for (i, db) in frame.values.enumerated() { inputLevels[i] = db }
        case .rta:
            rtaBins = frame.values
        }
    }

    func level(at index: Int?) -> Double {
        guard let index, let v = levels[index] else { return MeterFrame.floorDB }
        return v
    }

    func inputLevel(at index: Int) -> Double {
        inputLevels[index] ?? MeterFrame.floorDB
    }

    /// Current peak-hold value, already decayed to `now`.
    func peak(at index: Int?) -> Double {
        guard let index, let entry = peaks[index] else { return MeterFrame.floorDB }
        let elapsed = Date().timeIntervalSince(entry.at)
        guard elapsed > peakHold else { return entry.db }
        return max(level(at: index), entry.db - (elapsed - peakHold) * peakDecay)
    }

    func reset() {
        levels.removeAll()
        peaks.removeAll()
        inputLevels.removeAll()
        rtaBins = []
    }
}
