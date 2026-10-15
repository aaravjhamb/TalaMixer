//
//  XAirScale.swift
//  TalaMixer
//
//  Every X-Air parameter travels the wire as a float in 0...1 (or a small int
//  index). These are the curves that map wire values to the numbers printed on
//  the desk, and back.
//

import Foundation

/// The mapping between a parameter's wire value (0...1) and its real-world value.
enum XAirScale: Equatable {
    /// Straight interpolation between two bounds.
    case linear(Double, Double)
    /// Exponential interpolation — used for anything measured in Hz or ms.
    case logarithmic(Double, Double)
    /// The X-Air fader/send law: a five-segment curve spanning -90...+10 dB.
    case fader
    /// A one-of-N index (EQ type, gate mode, …). Wire value is an int.
    case index(Int)
    /// Pan, presented as -100 (L) ... +100 (R) with 0.5 at centre.
    case pan

    /// Converts a wire value into the displayed value.
    func value(fromWire wire: Double) -> Double {
        switch self {
        case .linear(let lo, let hi):
            return lo + (hi - lo) * wire
        case .logarithmic(let lo, let hi):
            guard lo > 0, hi > 0 else { return lo }
            return lo * exp(log(hi / lo) * wire)
        case .fader:
            return XAirScale.faderDecibels(fromWire: wire)
        case .index:
            return wire
        case .pan:
            return (wire - 0.5) * 200
        }
    }

    /// Converts a displayed value back into a wire value.
    func wire(fromValue value: Double) -> Double {
        switch self {
        case .linear(let lo, let hi):
            guard hi != lo else { return 0 }
            return ((value - lo) / (hi - lo)).clampedToUnit
        case .logarithmic(let lo, let hi):
            guard lo > 0, hi > 0, value > 0 else { return 0 }
            return (log(value / lo) / log(hi / lo)).clampedToUnit
        case .fader:
            return XAirScale.wire(fromFaderDecibels: value)
        case .index:
            return value
        case .pan:
            return (value / 200 + 0.5).clampedToUnit
        }
    }

    /// Inclusive bounds of the displayed value.
    var displayRange: ClosedRange<Double> {
        switch self {
        case .linear(let lo, let hi): return min(lo, hi)...max(lo, hi)
        case .logarithmic(let lo, let hi): return min(lo, hi)...max(lo, hi)
        case .fader: return -90...10
        case .index(let count): return 0...Double(max(0, count - 1))
        case .pan: return -100...100
        }
    }

    // MARK: - The fader law

    /// The X32/X-Air fader taper. Five linear segments in dB, which together
    /// give fine resolution near unity and coarse resolution at the bottom.
    static func faderDecibels(fromWire wire: Double) -> Double {
        if wire >= 1.0 { return 10 }
        if wire >= 0.5 { return wire * 40 - 30 }
        if wire >= 0.25 { return wire * 80 - 50 }
        if wire >= 0.0625 { return wire * 160 - 70 }
        if wire > 0 { return wire * 480 - 90 }
        return -Double.infinity
    }

    static func wire(fromFaderDecibels db: Double) -> Double {
        if db >= 10 { return 1 }
        if db >= -10 { return (db + 30) / 40 }
        if db >= -30 { return (db + 50) / 80 }
        if db >= -60 { return (db + 70) / 160 }
        if db >= -90 { return (db + 90) / 480 }
        return 0
    }

    /// The wire value for unity gain (0 dB) — where a fader "detents".
    static let unityWire: Double = wire(fromFaderDecibels: 0)
}

// MARK: - Formatting

enum XAirFormat {
    /// Formats a fader/send level. `-inf` at the bottom of travel, matching the desk.
    static func decibels(_ db: Double) -> String {
        if db <= -90 || db == -Double.infinity { return "-∞" }
        if abs(db) < 0.05 { return "0.0" }
        return String(format: "%+.1f", db)
    }

    static func decibelsWithUnit(_ db: Double) -> String {
        db <= -90 ? "-∞ dB" : decibels(db) + " dB"
    }

    /// Frequencies read as "80 Hz" / "3.15 kHz" the way the desk prints them.
    static func frequency(_ hz: Double) -> String {
        if hz >= 10_000 { return String(format: "%.0fk", hz / 1000) }
        if hz >= 1000 { return String(format: "%.2fk", hz / 1000) }
        if hz >= 100 { return String(format: "%.0f", hz) }
        return String(format: "%.1f", hz)
    }

    static func frequencyWithUnit(_ hz: Double) -> String {
        hz >= 1000 ? frequency(hz) + "Hz" : frequency(hz) + " Hz"
    }

    /// Times span 0.02 ms to 4000 ms, so the precision has to slide.
    static func milliseconds(_ ms: Double) -> String {
        if ms >= 100 { return String(format: "%.0f ms", ms) }
        if ms >= 10 { return String(format: "%.1f ms", ms) }
        return String(format: "%.2f ms", ms)
    }

    static func gain(_ db: Double) -> String {
        String(format: "%+.1f dB", db)
    }

    static func q(_ q: Double) -> String {
        String(format: "%.1f", q)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func pan(_ value: Double) -> String {
        if abs(value) < 1 { return "C" }
        return value < 0 ? String(format: "L%.0f", -value) : String(format: "R%.0f", value)
    }
}

extension Double {
    var clampedToUnit: Double { Swift.min(1, Swift.max(0, self)) }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
