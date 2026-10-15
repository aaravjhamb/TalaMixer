//
//  XAirEnums.swift
//  TalaMixer
//
//  The one-of-N parameter vocabularies. Index order matters — it is what goes
//  on the wire — so anything not independently confirmed is marked as such.
//

import SwiftUI

// MARK: - Strip colour

/// The 16 strip colours. Indices 8...15 are the "inverted" (filled) variants,
/// which the desk draws as a solid tile with dark text.
enum XAirColor: Int, CaseIterable, Identifiable {
    case off = 0, red, green, yellow, blue, magenta, cyan, white
    case offInverted, redInverted, greenInverted, yellowInverted
    case blueInverted, magentaInverted, cyanInverted, whiteInverted

    var id: Int { rawValue }

    var isInverted: Bool { rawValue >= 8 }

    /// The base hue, ignoring inversion.
    var tint: Color {
        switch rawValue % 8 {
        case 1: return Color(red: 0.98, green: 0.29, blue: 0.35)
        case 2: return Color(red: 0.31, green: 0.86, blue: 0.49)
        case 3: return Color(red: 0.99, green: 0.81, blue: 0.28)
        case 4: return Color(red: 0.33, green: 0.60, blue: 0.99)
        case 5: return Color(red: 0.85, green: 0.42, blue: 0.95)
        case 6: return Color(red: 0.30, green: 0.85, blue: 0.90)
        case 7: return Color(red: 0.94, green: 0.95, blue: 0.97)
        default: return Color(red: 0.45, green: 0.48, blue: 0.55)
        }
    }

    var label: String {
        switch rawValue % 8 {
        case 1: return "Red"
        case 2: return "Green"
        case 3: return "Yellow"
        case 4: return "Blue"
        case 5: return "Magenta"
        case 6: return "Cyan"
        case 7: return "White"
        default: return "Off"
        }
    }

    var displayName: String { isInverted ? "\(label) (filled)" : label }
}

// MARK: - EQ

enum XAirEQBandType: Int, CaseIterable, Identifiable {
    case lowCut = 0, lowShelf, peaking, vintage, highShelf, highCut

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .lowCut: return "LCut"
        case .lowShelf: return "LShv"
        case .peaking: return "PEQ"
        case .vintage: return "VEQ"
        case .highShelf: return "HShv"
        case .highCut: return "HCut"
        }
    }

    /// A shelf or cut has no meaningful gain-and-Q "bell"; the curve renderer
    /// needs to know which shape to draw.
    var isBell: Bool { self == .peaking || self == .vintage }
    var usesGain: Bool { self != .lowCut && self != .highCut }
}

enum XAirEQMode: Int, CaseIterable, Identifiable {
    case peq = 0, geq, teq
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .peq: return "PEQ"
        case .geq: return "GEQ"
        case .teq: return "TEQ"
        }
    }
}

// MARK: - Gate

enum XAirGateMode: Int, CaseIterable, Identifiable {
    case exp2 = 0, exp3, exp4, gate, duck
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .exp2: return "EXP 2:1"
        case .exp3: return "EXP 3:1"
        case .exp4: return "EXP 4:1"
        case .gate: return "GATE"
        case .duck: return "DUCKER"
        }
    }
}

// MARK: - Dynamics

enum XAirDynMode: Int, CaseIterable, Identifiable {
    case compressor = 0, expander
    var id: Int { rawValue }
    var displayName: String { self == .compressor ? "COMP" : "EXP" }
}

enum XAirDynDetection: Int, CaseIterable, Identifiable {
    case peak = 0, rms
    var id: Int { rawValue }
    var displayName: String { self == .peak ? "PEAK" : "RMS" }
}

enum XAirDynEnvelope: Int, CaseIterable, Identifiable {
    case linear = 0, logarithmic
    var id: Int { rawValue }
    var displayName: String { self == .linear ? "LIN" : "LOG" }
}

/// Compressor ratio is an index into a fixed table, not a continuous value.
enum XAirDynRatio {
    static let values: [Double] = [1.1, 1.3, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 7.0, 10, 20, 100]

    static func label(at index: Int) -> String {
        guard values.indices.contains(index) else { return "—" }
        let v = values[index]
        if v == 100 { return "∞:1" }
        // Decimal only where there is one — otherwise 2.5 and 2.0 both print "2:1".
        return v == v.rounded()
            ? String(format: "%.0f:1", v)
            : String(format: "%.1f:1", v)
    }
}

// MARK: - Sidechain filter

enum XAirFilterType: Int, CaseIterable, Identifiable {
    case lc6 = 0, lc12, hc6, hc12, band1, band2, band3, band5, band10
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .lc6: return "LC6"
        case .lc12: return "LC12"
        case .hc6: return "HC6"
        case .hc12: return "HC12"
        case .band1: return "1.0"
        case .band2: return "2.0"
        case .band3: return "3.0"
        case .band5: return "5.0"
        case .band10: return "10.0"
        }
    }
}

// MARK: - Graphic EQ

enum XAirGEQ {
    /// The 31 ISO third-octave centres, in the order the desk indexes them.
    /// Wire addresses use the desk's own spelling, e.g. `/bus/1/geq/31.5`.
    static let bands: [(address: String, label: String)] = [
        ("20", "20"), ("25", "25"), ("31.5", "31.5"), ("40", "40"), ("50", "50"),
        ("63", "63"), ("80", "80"), ("100", "100"), ("125", "125"), ("160", "160"),
        ("200", "200"), ("250", "250"), ("315", "315"), ("400", "400"), ("500", "500"),
        ("630", "630"), ("800", "800"), ("1k", "1k"), ("1k25", "1k25"), ("1k6", "1k6"),
        ("2k", "2k"), ("2k5", "2k5"), ("3k15", "3k15"), ("4k", "4k"), ("5k", "5k"),
        ("6k3", "6k3"), ("8k", "8k"), ("10k", "10k"), ("12k5", "12k5"), ("16k", "16k"),
        ("20k", "20k"),
    ]
}

// MARK: - Effects

/// Effect engine names.
///
/// **Unverified ordering.** The X-Air firmware does not publish its FX enum, and
/// the index order could not be confirmed from a primary source. The FX view
/// therefore always shows the raw index next to the name so a mismatch is
/// obvious, and `name(for:)` degrades to "FX type N" outside this table.
/// Correct any wrong entries here — nothing else depends on the ordering.
enum XAirFXCatalog {
    static let unverifiedNames: [String] = [
        "Hall Reverb", "Ambience", "Rich Plate", "Room Reverb", "Chamber Reverb",
        "Plate Reverb", "Vintage Reverb", "Vintage Room", "Gated Reverb", "Reverse Reverb",
        "Stereo Delay", "3-Tap Delay", "4-Tap Delay", "Tape Delay", "Modulation Delay",
        "Chorus + Delay", "Flanger + Delay", "Delay + Reverb", "Chorus + Reverb", "Flanger + Reverb",
        "Modulator", "Chorus", "Flanger", "Phaser", "Tremolo",
        "Rotary Speaker", "Stereo Enhancer", "Exciter", "Stereo Imager", "Sub Octaver",
        "Auto-Pan", "Dual Pitch", "Graphic EQ", "Dual Graphic EQ", "True EQ",
        "Dual True EQ", "Stereo Compressor", "Dual Compressor", "Precision Limiter", "Guitar Amp",
        "Fair Compressor", "Leisure Compressor", "Ultimo Compressor", "Wave Designer", "De-Esser",
        "Dual De-Esser", "Combinator", "Edison EX1", "Sound Maxer", "Mood Filter",
    ]

    static let count = 64

    static func name(for index: Int) -> String {
        guard unverifiedNames.indices.contains(index) else { return "FX type \(index)" }
        return unverifiedNames[index]
    }

    /// Parameter names per engine, in `par/01…` order, taken from the X32
    /// effect layouts (the X-Air runs the same engines). Values still travel as
    /// raw 0–1 floats — the desk does its own internal mapping — so the UI
    /// shows names with percentages. Engines without an entry fall back to the
    /// raw parameter list.
    static func parameterNames(for index: Int) -> [String]? {
        let reverb = ["Pre Delay", "Decay", "Size", "Damping", "Diffusion",
                      "Level", "Lo Cut", "Hi Cut", "Bass Multiply", "Spread",
                      "Shape", "Mod Speed", "Tail Gain"]
        switch index {
        case 0...4:      // Hall, Ambience, Rich Plate, Room, Chamber
            return reverb
        case 5, 6, 7:    // Plate, Vintage Reverb, Vintage Room
            return reverb
        case 8:          // Gated Reverb
            return ["Pre Delay", "Decay", "Attack", "Density", "Spread",
                    "Lo Cut", "Hi Cut", "Hi Shelf", "Diffusion", "Level"]
        case 9:          // Reverse Reverb
            return ["Pre Delay", "Decay", "Rise", "Diffusion", "Spread",
                    "Lo Cut", "Hi Cut", "Hi Shelf", "Level"]
        case 10:         // Stereo Delay
            return ["Time", "Pattern", "Feedback", "Feedback Hi Cut",
                    "Feedback Lo Cut", "Offset L/R", "Mix"]
        case 11, 12:     // 3-Tap / 4-Tap Delay
            return ["Time", "Gain Base", "Feedback", "Lo Cut", "Hi Cut",
                    "Tap 2 Gain", "Tap 3 Gain", "Tap 4 Gain", "Pan Spread"]
        case 13:         // Tape Delay
            return ["Time", "Feedback", "Wow & Flutter", "Saturation",
                    "Lo Cut", "Hi Cut", "Mix"]
        case 14:         // Modulation Delay
            return ["Time", "Pattern", "Feedback", "Mod Speed", "Mod Depth",
                    "Lo Cut", "Hi Cut", "Mix"]
        case 15...19:    // Chorus/Flanger/Delay + Reverb combos
            return ["Time", "Feedback", "Lo Cut", "Hi Cut", "Mod Speed",
                    "Mod Depth", "Balance", "Level"]
        case 21:         // Chorus
            return ["Speed", "Depth", "Delay L", "Delay R", "Phase",
                    "Wave", "Spread", "Lo Cut", "Hi Cut"]
        case 22:         // Flanger
            return ["Speed", "Depth", "Delay L", "Delay R", "Phase",
                    "Feedback", "Feed Lo Cut", "Feed Hi Cut", "Mix"]
        case 23:         // Phaser
            return ["Speed", "Depth", "Resonance", "Base", "Stages",
                    "Wave", "Phase", "Mix"]
        case 24:         // Tremolo
            return ["Speed", "Depth", "Wave", "Phase", "Lo Cut", "Hi Cut"]
        case 25:         // Rotary Speaker
            return ["Speed Slow", "Speed Fast", "Acceleration", "Distance",
                    "Balance", "Mix"]
        case 26:         // Stereo Enhancer
            return ["Bass Gain", "Bass Freq", "Mid Gain", "Mid Q",
                    "Hi Gain", "Hi Freq", "Out Gain", "Spread"]
        case 27:         // Exciter
            return ["Tune", "Peak", "Zero Fill", "Timbre", "Harmonics", "Mix"]
        case 29:         // Sub Octaver
            return ["Range", "Direct", "Octave 1", "Octave 2"]
        case 30:         // Auto-Pan
            return ["Speed", "Phase", "Wave", "Depth", "Env Speed", "Env Depth"]
        case 31:         // Dual Pitch
            return ["Semitones A", "Cents A", "Delay A", "Level A",
                    "Semitones B", "Cents B", "Delay B", "Level B"]
        default:
            return nil
        }
    }
}

// MARK: - USB recorder transport

/// `/-stat/tape/state`. **Needs hardware confirmation** — implemented from the
/// X32 convention, which the X-Air is believed to share.
enum XAirTapeState: Int, CaseIterable, Identifiable {
    case stop = 0, pausePlay, play, pauseRecord, record, fastForward, rewind
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .stop: return "Stopped"
        case .pausePlay: return "Paused"
        case .play: return "Playing"
        case .pauseRecord: return "Record ready"
        case .record: return "Recording"
        case .fastForward: return "Forward"
        case .rewind: return "Rewind"
        }
    }
    var isRecording: Bool { self == .record || self == .pauseRecord }
}
