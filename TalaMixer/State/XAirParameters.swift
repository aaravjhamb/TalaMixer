//
//  XAirParameters.swift
//  TalaMixer
//
//  One place where every parameter's scale is declared, so the code that applies
//  inbound values and the code that sends outbound values can never disagree.
//

import Foundation

enum P {
    // Preamp
    static let highPassFilter = XAirScale.logarithmic(20, 400)
    static let usbTrim = XAirScale.linear(-18, 18)
    static let headampGain = XAirScale.linear(-12, 60)
    /// Simple mode's gain knob, laid out like a Scarlett's: no useless low end,
    /// so the bottom of travel already passes signal and 12 o'clock lands near
    /// typical mic gain (~+35 dB). Drives the same /headamp gain.
    static let simpleHeadampGain = XAirScale.linear(10, 60)

    // Gate
    static let gateThreshold = XAirScale.linear(-80, 0)
    static let gateRange = XAirScale.linear(3, 60)

    // Shared dynamics timing
    static let attack = XAirScale.linear(0, 120)
    static let hold = XAirScale.logarithmic(0.02, 2000)
    static let release = XAirScale.logarithmic(5, 4000)
    static let sidechainFrequency = XAirScale.logarithmic(20, 20000)

    // Compressor
    static let dynThreshold = XAirScale.linear(-60, 0)
    static let knee = XAirScale.linear(0, 5)
    static let makeupGain = XAirScale.linear(0, 24)
    static let dryWetMix = XAirScale.linear(0, 100)

    // EQ
    static let eqFrequency = XAirScale.logarithmic(20, 20000)
    static let eqGain = XAirScale.linear(-15, 15)
    static let graphicEQGain = XAirScale.linear(-15, 15)

    /// Q is stored *inverted* on the wire: a wire value of 0 is the widest Q.
    /// Always go through these two helpers rather than a bare scale.
    private static let qScale = XAirScale.logarithmic(0.3, 10)
    static func q(fromWire wire: Double) -> Double { qScale.value(fromWire: 1 - wire) }
    static func qWire(fromQ q: Double) -> Double { 1 - qScale.wire(fromValue: q) }
    static let qRange: ClosedRange<Double> = 0.3...10

    // Levels
    static let fader = XAirScale.fader
    static let sendLevel = XAirScale.fader
    static let pan = XAirScale.pan

    // Automix
    static let automixWeight = XAirScale.linear(-12, 12)

    // Monitor bus
    static let monitorLevel = XAirScale.fader
    static let monitorTrim = XAirScale.linear(-18, 18)
    static let dimAttenuation = XAirScale.linear(-40, 0)
}

// MARK: - Bitmask helpers

/// `grp/dca` and `grp/mute` are integer bitmasks: bit 0 is group 1.
extension Int {
    func hasGroupBit(_ oneBasedIndex: Int) -> Bool {
        guard oneBasedIndex >= 1, oneBasedIndex <= 32 else { return false }
        return self & (1 << (oneBasedIndex - 1)) != 0
    }

    func settingGroupBit(_ oneBasedIndex: Int, to on: Bool) -> Int {
        guard oneBasedIndex >= 1, oneBasedIndex <= 32 else { return self }
        let mask = 1 << (oneBasedIndex - 1)
        return on ? (self | mask) : (self & ~mask)
    }

    /// The 1-based group numbers present in the mask.
    func groupBits(upTo count: Int) -> [Int] {
        // `Swift.max` — inside an `Int` extension, bare `max` is `Int.max`.
        (1...Swift.max(1, count)).filter { hasGroupBit($0) }
    }
}
