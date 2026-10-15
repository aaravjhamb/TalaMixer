//
//  StripSettings.swift
//  TalaMixer
//
//  A portable bundle of one strip's processing — the machinery behind
//  copy/paste between channels, channel presets, and channel safes during
//  snapshot recall.
//
//  Deliberately excludes identity (name, colour), analogue gain and phantom
//  power: pasting a channel should move its *sound*, not its wiring.
//

import Foundation

// MARK: - Settings bundle

struct StripSettings: Codable, Equatable {
    /// Which sections a paste can carry.
    struct Sections: OptionSet, Codable {
        let rawValue: Int
        static let eq = Sections(rawValue: 1 << 0)
        static let gate = Sections(rawValue: 1 << 1)
        static let dynamics = Sections(rawValue: 1 << 2)
        static let sends = Sections(rawValue: 1 << 3)
        static let mix = Sections(rawValue: 1 << 4)
        static let all: Sections = [.eq, .gate, .dynamics, .sends, .mix]
    }

    struct Band: Codable, Equatable {
        var type: Int
        var frequency: Double
        var gain: Double
        var q: Double
    }

    // EQ
    var eqOn = false
    var eqBands: [Band] = []

    // Gate
    var gateOn = false
    var gateMode = 0
    var gateThreshold = 0.5
    var gateRange = 0.5
    var gateAttack = 0.1
    var gateHold = 0.5
    var gateRelease = 0.5
    var gateFilterOn = false
    var gateFilterType = 4
    var gateFilterFrequency = 0.5

    // Dynamics
    var dynOn = false
    var dynMode = 0
    var dynDetection = 1
    var dynEnvelope = 1
    var dynThreshold = 1.0
    var dynRatio = 3
    var dynKnee = 0.5
    var dynMakeup = 0.0
    var dynAttack = 0.1
    var dynHold = 0.5
    var dynRelease = 0.5
    var dynMix = 1.0
    var dynAuto = false
    var dynFilterOn = false
    var dynFilterType = 4
    var dynFilterFrequency = 0.5

    // Sends and mix
    var sends: [Double] = []
    var fader = 0.0
    var pan = 0.5
    var on = true
    var assignedToMain = true

    // MARK: Capture

    @MainActor
    static func capture(from strip: StripState) -> StripSettings {
        var s = StripSettings()
        s.eqOn = strip.eq.on
        s.eqBands = strip.eq.bands.map {
            Band(type: $0.type.rawValue, frequency: $0.frequencyWire,
                 gain: $0.gainWire, q: $0.qWire)
        }

        s.gateOn = strip.gate.on
        s.gateMode = strip.gate.mode.rawValue
        s.gateThreshold = strip.gate.thresholdWire
        s.gateRange = strip.gate.rangeWire
        s.gateAttack = strip.gate.attackWire
        s.gateHold = strip.gate.holdWire
        s.gateRelease = strip.gate.releaseWire
        s.gateFilterOn = strip.gate.filter.on
        s.gateFilterType = strip.gate.filter.type.rawValue
        s.gateFilterFrequency = strip.gate.filter.frequencyWire

        s.dynOn = strip.dynamics.on
        s.dynMode = strip.dynamics.mode.rawValue
        s.dynDetection = strip.dynamics.detection.rawValue
        s.dynEnvelope = strip.dynamics.envelope.rawValue
        s.dynThreshold = strip.dynamics.thresholdWire
        s.dynRatio = strip.dynamics.ratioIndex
        s.dynKnee = strip.dynamics.kneeWire
        s.dynMakeup = strip.dynamics.makeupWire
        s.dynAttack = strip.dynamics.attackWire
        s.dynHold = strip.dynamics.holdWire
        s.dynRelease = strip.dynamics.releaseWire
        s.dynMix = strip.dynamics.mixWire
        s.dynAuto = strip.dynamics.autoTime
        s.dynFilterOn = strip.dynamics.filter.on
        s.dynFilterType = strip.dynamics.filter.type.rawValue
        s.dynFilterFrequency = strip.dynamics.filter.frequencyWire

        s.sends = strip.sendWires
        s.fader = strip.faderWire
        s.pan = strip.panWire
        s.on = strip.on
        s.assignedToMain = strip.assignedToMain
        return s
    }
}

// MARK: - Apply

@MainActor
extension XAirClient {
    /// Writes the chosen sections of a settings bundle to a strip. Sections the
    /// target doesn't support (a gate on a mix, say) are skipped quietly.
    func apply(_ settings: StripSettings, to id: StripID, sections: StripSettings.Sections) {
        if sections.contains(.eq), id.eqBandCount > 0 {
            setEQOn(id, settings.eqOn)
            // Band counts differ between inputs (4) and mixes (6); apply what fits.
            for (i, band) in settings.eqBands.enumerated() where i < id.eqBandCount {
                let number = i + 1
                if let type = XAirEQBandType(rawValue: band.type) {
                    setEQBandType(id, band: number, type)
                }
                setEQFrequency(id, band: number, wire: band.frequency)
                setEQGain(id, band: number, wire: band.gain)
                // qWire is already a wire value; route through the raw writer.
                writeNow(id.eqAddress(band: number, "q"), .float(Float(band.q)))
                state.strip(id).eq[number]?.qWire = band.q
            }
        }

        if sections.contains(.gate), id.hasGate {
            setGateOn(id, settings.gateOn)
            if let mode = XAirGateMode(rawValue: settings.gateMode) { setGateMode(id, mode) }
            setGateParameter(id, .threshold, wire: settings.gateThreshold)
            setGateParameter(id, .range, wire: settings.gateRange)
            setGateParameter(id, .attack, wire: settings.gateAttack)
            setGateParameter(id, .hold, wire: settings.gateHold)
            setGateParameter(id, .release, wire: settings.gateRelease)
            setGateFilterOn(id, settings.gateFilterOn)
            if let type = XAirFilterType(rawValue: settings.gateFilterType) {
                setGateFilterType(id, type)
            }
            setGateFilterFrequency(id, wire: settings.gateFilterFrequency)
        }

        if sections.contains(.dynamics), id.hasDynamics {
            setDynamicsOn(id, settings.dynOn)
            if let mode = XAirDynMode(rawValue: settings.dynMode) { setDynamicsMode(id, mode) }
            if let det = XAirDynDetection(rawValue: settings.dynDetection) { setDynamicsDetection(id, det) }
            if let env = XAirDynEnvelope(rawValue: settings.dynEnvelope) { setDynamicsEnvelope(id, env) }
            setDynamicsParameter(id, .threshold, wire: settings.dynThreshold)
            setDynamicsRatio(id, index: settings.dynRatio)
            setDynamicsParameter(id, .knee, wire: settings.dynKnee)
            setDynamicsParameter(id, .makeup, wire: settings.dynMakeup)
            setDynamicsParameter(id, .attack, wire: settings.dynAttack)
            setDynamicsParameter(id, .hold, wire: settings.dynHold)
            setDynamicsParameter(id, .release, wire: settings.dynRelease)
            setDynamicsParameter(id, .mix, wire: settings.dynMix)
            setDynamicsAutoTime(id, settings.dynAuto)
            setDynamicsFilterOn(id, settings.dynFilterOn)
            if let type = XAirFilterType(rawValue: settings.dynFilterType) {
                setDynamicsFilterType(id, type)
            }
            setDynamicsFilterFrequency(id, wire: settings.dynFilterFrequency)
        }

        if sections.contains(.sends), id.hasSends {
            for (i, wire) in settings.sends.enumerated() where i < state.model.sendCount {
                setSendLevel(id, slot: i + 1, wire: wire)
            }
        }

        if sections.contains(.mix) {
            setFader(id, wire: settings.fader)
            if id.hasPan { setPan(id, wire: settings.pan) }
            setMuted(id, !settings.on)
            if id.hasMainAssign { setMainAssign(id, settings.assignedToMain) }
        }
    }
}

// MARK: - Clipboard

/// One copied channel, app-wide.
@MainActor
@Observable
final class ChannelClipboard {
    private(set) var settings: StripSettings?
    private(set) var sourceName = ""

    var isEmpty: Bool { settings == nil }

    func copy(from strip: StripState) {
        settings = StripSettings.capture(from: strip)
        sourceName = strip.displayName
    }
}

// MARK: - Presets

/// Named channel presets — EQ, gate and compressor — kept in one JSON file.
@MainActor
@Observable
final class PresetStore {
    struct Preset: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var settings: StripSettings
    }

    private(set) var presets: [Preset] = []
    private let url: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask).first!
        url = documents.appendingPathComponent("ChannelPresets.json")
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = loaded
        }
    }

    func save(name: String, settings: StripSettings) {
        presets.insert(Preset(name: name, settings: settings), at: 0)
        persist()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
