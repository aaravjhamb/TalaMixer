//
//  StripState.swift
//  TalaMixer
//
//  Mirrored state for one mixer strip.
//
//  Every level-type value is held as the raw 0...1 wire value rather than as
//  decibels or hertz. That keeps a round trip through the desk lossless, and
//  means the fader's travel matches the physical desk exactly.
//

import Foundation
import Observation

// MARK: - Processing blocks

struct PreampState: Equatable {
    var invert = false
    var highPassOn = false
    var highPassWire = 0.0
    var usbTrimWire = 0.5
    var usbInput = false

    var highPassHz: Double { P.highPassFilter.value(fromWire: highPassWire) }
    var usbTrimDB: Double { P.usbTrim.value(fromWire: usbTrimWire) }
}

struct SidechainFilterState: Equatable {
    var on = false
    var type = XAirFilterType.band2
    var frequencyWire = 0.5

    var frequencyHz: Double { P.sidechainFrequency.value(fromWire: frequencyWire) }
}

struct GateState: Equatable {
    var on = false
    var mode = XAirGateMode.gate
    var thresholdWire = 0.5
    var rangeWire = 0.5
    var attackWire = 0.1
    var holdWire = 0.5
    var releaseWire = 0.5
    var keySource = 0
    var filter = SidechainFilterState()

    var thresholdDB: Double { P.gateThreshold.value(fromWire: thresholdWire) }
    var rangeDB: Double { P.gateRange.value(fromWire: rangeWire) }
    var attackMS: Double { P.attack.value(fromWire: attackWire) }
    var holdMS: Double { P.hold.value(fromWire: holdWire) }
    var releaseMS: Double { P.release.value(fromWire: releaseWire) }
}

struct DynamicsState: Equatable {
    var on = false
    var mode = XAirDynMode.compressor
    var detection = XAirDynDetection.rms
    var envelope = XAirDynEnvelope.logarithmic
    var thresholdWire = 1.0
    var ratioIndex = 3
    var kneeWire = 0.5
    var makeupWire = 0.0
    var attackWire = 0.1
    var holdWire = 0.5
    var releaseWire = 0.5
    var mixWire = 1.0
    var keySource = 0
    var autoTime = false
    var filter = SidechainFilterState()

    var thresholdDB: Double { P.dynThreshold.value(fromWire: thresholdWire) }
    var ratio: Double {
        XAirDynRatio.values.indices.contains(ratioIndex) ? XAirDynRatio.values[ratioIndex] : 2
    }
    var knee: Double { P.knee.value(fromWire: kneeWire) }
    var makeupDB: Double { P.makeupGain.value(fromWire: makeupWire) }
    var attackMS: Double { P.attack.value(fromWire: attackWire) }
    var holdMS: Double { P.hold.value(fromWire: holdWire) }
    var releaseMS: Double { P.release.value(fromWire: releaseWire) }
    var mixPercent: Double { P.dryWetMix.value(fromWire: mixWire) }
}

struct EQBandState: Equatable, Identifiable {
    /// 1-based band number, as it appears in the address.
    var band: Int
    var type = XAirEQBandType.peaking
    var frequencyWire = 0.5
    var gainWire = 0.5
    var qWire = 0.5

    var id: Int { band }

    var frequencyHz: Double { P.eqFrequency.value(fromWire: frequencyWire) }
    var gainDB: Double { P.eqGain.value(fromWire: gainWire) }
    var q: Double { P.q(fromWire: qWire) }
}

struct EQState: Equatable {
    var on = false
    var mode = XAirEQMode.peq
    var bands: [EQBandState]

    init(bandCount: Int) {
        bands = (1...max(1, bandCount)).map { EQBandState(band: $0) }
    }

    subscript(band: Int) -> EQBandState? {
        get { bands.first { $0.band == band } }
        set {
            guard let newValue, let i = bands.firstIndex(where: { $0.band == band }) else { return }
            bands[i] = newValue
        }
    }
}

struct InsertState: Equatable {
    var on = false
    var selection = 0
}

struct AutomixState: Equatable {
    /// 0 = off, 1 = group X, 2 = group Y.
    var group = 0
    var weightWire = 0.5

    var weightDB: Double { P.automixWeight.value(fromWire: weightWire) }
}

// MARK: - Strip

@Observable
final class StripState: Identifiable {
    let id: StripID

    // Identity
    var name: String = ""
    var colorIndex: Int = 0
    var inputSource: Int = 0
    var usbReturnSource: Int = 0

    // Mix
    /// The desk's sense: `true` means the strip is passing audio.
    var on: Bool = true
    var faderWire: Double = 0
    var panWire: Double = 0.5
    var assignedToMain: Bool = true

    // Grouping (bitmasks)
    var dcaMask: Int = 0
    var muteGroupMask: Int = 0

    /// Bus + FX send levels, 1-based in the addresses but 0-based here.
    var sendWires: [Double]

    // Processing
    var preamp = PreampState()
    var gate = GateState()
    var dynamics = DynamicsState()
    var eq: EQState
    /// 31 graphic-EQ band wire values, buses and LR only.
    var graphicEQWires: [Double]
    var insert = InsertState()
    var automix = AutomixState()

    // Transient / status
    var solo: Bool = false
    /// True once we've heard anything at all back about this strip.
    var isSynced: Bool = false

    init(id: StripID, sendCount: Int) {
        self.id = id
        self.sendWires = Array(repeating: 0, count: max(0, sendCount))
        self.eq = EQState(bandCount: max(1, id.eqBandCount))
        self.graphicEQWires = id.hasGraphicEQ
            ? Array(repeating: 0.5, count: XAirGEQ.bands.count)
            : []
    }

    // MARK: Derived

    /// The name to show: the desk's own label, else a sensible default.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? id.defaultName : trimmed
    }

    var color: XAirColor { XAirColor(rawValue: colorIndex) ?? .off }

    var isMuted: Bool { !on }

    var faderDB: Double { P.fader.value(fromWire: faderWire) }

    var panValue: Double { P.pan.value(fromWire: panWire) }

    func sendWire(_ oneBasedIndex: Int) -> Double {
        let i = oneBasedIndex - 1
        return sendWires.indices.contains(i) ? sendWires[i] : 0
    }

    func sendDB(_ oneBasedIndex: Int) -> Double {
        P.sendLevel.value(fromWire: sendWire(oneBasedIndex))
    }

    func graphicEQWire(_ index: Int) -> Double {
        graphicEQWires.indices.contains(index) ? graphicEQWires[index] : 0.5
    }

    /// Whether any processing block is engaged — drives the little indicator
    /// dots on the fader strip.
    var hasActiveProcessing: Bool {
        gate.on || dynamics.on || eq.on || preamp.highPassOn
    }
}
