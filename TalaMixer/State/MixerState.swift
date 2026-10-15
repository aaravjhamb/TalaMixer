//
//  MixerState.swift
//  TalaMixer
//
//  The app's mirror of the desk, plus the router that turns inbound OSC into
//  state changes.
//

import Foundation
import Observation

// MARK: - Supporting state

struct DeskInfo: Equatable {
    var ip: String = ""
    var name: String = ""
    var model: String = ""
    var firmware: String = ""

    var isEmpty: Bool { model.isEmpty && name.isEmpty }
}

struct HeadampState: Equatable, Identifiable {
    var index: Int
    var gainWire: Double = 0
    var phantom: Bool = false

    var id: Int { index }
    var gainDB: Double { P.headampGain.value(fromWire: gainWire) }
}

struct FXSlotState: Equatable, Identifiable {
    var slot: Int
    var typeIndex: Int = 0
    /// The desk exposes up to 64 generic parameters per slot; their meaning
    /// depends on the loaded engine.
    var parameters: [Double] = Array(repeating: 0, count: 64)

    var id: Int { slot }
    var typeName: String { XAirFXCatalog.name(for: typeIndex) }
}

struct MonitorState: Equatable {
    var levelWire: Double = 0
    var source: Int = 0
    var trimWire: Double = 0.5
    var dim: Bool = false
    var dimAttenuationWire: Double = 0.5
    var mono: Bool = false
    var mute: Bool = false
    var dimFollowsPFL: Bool = false
    var channelMode: Bool = false
    var busMode: Bool = false

    var levelDB: Double { P.monitorLevel.value(fromWire: levelWire) }
    var trimDB: Double { P.monitorTrim.value(fromWire: trimWire) }
    var dimAttenuationDB: Double { P.dimAttenuation.value(fromWire: dimAttenuationWire) }
}

struct LinkState: Equatable {
    var channelLinks: [Int: Bool] = [:]     // keyed by odd channel index
    var busLinks: [Int: Bool] = [:]
    var linksEQ = false
    var linksDynamics = false
    var linksFaderAndMute = false
}

struct TapeState: Equatable {
    var state = XAirTapeState.stop
    var file = ""
    var elapsed = ""
    var remaining = ""
}

// MARK: - Mixer

@MainActor
@Observable
final class MixerState {

    // MARK: Topology

    private(set) var model: XAirModel = .xr18
    private(set) var strips: [StripID: StripState] = [:]
    private(set) var stripOrder: [StripID] = []

    private var stripIDByAddress: [String: StripID] = [:]
    private var stripIDBySoloIndex: [Int: StripID] = [:]

    // MARK: Desk-wide state

    var info = DeskInfo()
    var muteGroups: [Bool] = Array(repeating: false, count: 4)
    var headamps: [HeadampState] = []
    var fx: [FXSlotState] = []
    var monitor = MonitorState()
    var links = LinkState()
    var tape = TapeState()

    var automixEnabled = false
    var automixLocked = false

    /// 1-based; 0 means "nothing recalled yet".
    var currentSnapshot = 0
    var snapshotNames: [Int: String] = [:]

    /// Meter data lives outside observation — see `MeterStore`.
    let meters = MeterStore()

    init(model: XAirModel = .xr18) {
        configure(model: model)
    }

    // MARK: Configuration

    func configure(model: XAirModel) {
        self.model = model

        var built: [StripID: StripState] = [:]
        var order: [StripID] = []
        var byAddress: [String: StripID] = [:]
        var bySolo: [Int: StripID] = [:]

        func add(_ id: StripID) {
            let strip = StripState(id: id, sendCount: model.sendCount)
            built[id] = strip
            order.append(id)
            byAddress[id.address] = id
            if let solo = XAirAddress.soloIndex(for: id, model: model) {
                bySolo[solo] = id
            }
        }

        for n in 1...model.channelCount { add(.channel(n)) }
        add(.auxReturn)
        for n in 1...model.fxCount { add(.fxReturn(n)) }
        for n in 1...model.busCount { add(.bus(n)) }
        for n in 1...model.fxCount { add(.fxSend(n)) }
        for n in 1...model.dcaCount { add(.dca(n)) }
        add(.main)

        strips = built
        stripOrder = order
        stripIDByAddress = byAddress
        stripIDBySoloIndex = bySolo

        headamps = (1...model.channelCount).map { HeadampState(index: $0) }
        fx = (1...model.fxCount).map { FXSlotState(slot: $0) }
        muteGroups = Array(repeating: false, count: model.muteGroupCount)
    }

    // MARK: Lookup

    func strip(_ id: StripID) -> StripState {
        if let existing = strips[id] { return existing }
        // Should not happen, but a placeholder beats a crash mid-show.
        let placeholder = StripState(id: id, sendCount: model.sendCount)
        strips[id] = placeholder
        return placeholder
    }

    func strips(in family: StripID.Family) -> [StripState] {
        stripOrder.filter { $0.family == family }.map { strip($0) }
    }

    /// The strips shown on the main fader bank, in desk order.
    var bankStrips: [StripState] {
        stripOrder
            .filter { $0.family != .main }
            .map { strip($0) }
    }

    var mainStrip: StripState { strip(.main) }

    /// Label for send slot `index` (1-based): aux buses first, then FX sends.
    func sendLabel(_ index: Int) -> String {
        if index <= model.busCount {
            let bus = strip(.bus(index))
            return bus.name.isEmpty ? "Mix \(index)" : bus.displayName
        }
        let fxIndex = index - model.busCount
        return "FX \(fxIndex)"
    }

    func sendStripID(_ index: Int) -> StripID {
        index <= model.busCount ? .bus(index) : .fxSend(index - model.busCount)
    }

    // MARK: - Inbound routing

    func apply(_ message: OSCMessage) {
        // Meters are by far the highest-volume traffic; check for them first.
        if message.address.hasPrefix("/meters/") {
            applyMeters(message)
            return
        }
        if let (strip, remainder) = resolveStrip(message.address) {
            applyStrip(strip, remainder, message.values)
            return
        }
        applyGlobal(message.address, message.values)
    }

    private func applyMeters(_ message: OSCMessage) {
        let raw = message.address.dropFirst("/meters/".count)
        guard let id = Int(raw), let bank = XAirMeterBank(rawValue: id),
              let frame = MeterFrame(message: message) else { return }
        meters.ingest(frame, bank: bank)
    }

    private func resolveStrip(_ address: String) -> (StripState, String)? {
        let parts = address.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }

        if parts.count >= 2 {
            let key = "/\(parts[0])/\(parts[1])"
            if let id = stripIDByAddress[key] {
                return (strip(id), parts.dropFirst(2).joined(separator: "/"))
            }
        }
        if let id = stripIDByAddress["/\(parts[0])"] {
            return (strip(id), parts.dropFirst(1).joined(separator: "/"))
        }
        return nil
    }

    // MARK: Strip parameters

    private func applyStrip(_ strip: StripState, _ path: String, _ values: [OSCValue]) {
        strip.isSynced = true
        let first = values.first

        switch path {
        // Identity
        case "config/name":
            if let s = first?.stringValue { strip.name = s }
        case "config/color":
            if let i = first?.intValue { strip.colorIndex = i }
        case "config/insrc":
            if let i = first?.intValue { strip.inputSource = i }
        case "config/rtnsrc":
            if let i = first?.intValue { strip.usbReturnSource = i }

        // Mix — note DCAs use the bare forms
        case "mix/on", "on":
            if let b = first?.boolValue { strip.on = b }
        case "mix/fader", "fader":
            if let f = first?.floatValue { strip.faderWire = Double(f) }
        case "mix/pan":
            if let f = first?.floatValue { strip.panWire = Double(f) }
        case "mix/lr":
            if let b = first?.boolValue { strip.assignedToMain = b }

        // Grouping
        case "grp/dca":
            if let i = first?.intValue { strip.dcaMask = i }
        case "grp/mute":
            if let i = first?.intValue { strip.muteGroupMask = i }

        // EQ header
        case "eq/on":
            if let b = first?.boolValue { strip.eq.on = b }
        case "eq/mode":
            if let i = first?.intValue, let m = XAirEQMode(rawValue: i) { strip.eq.mode = m }

        // Insert
        case "insert/on":
            if let b = first?.boolValue { strip.insert.on = b }
        case "insert/sel":
            if let i = first?.intValue { strip.insert.selection = i }

        // Automix
        case "automix/group":
            if let i = first?.intValue { strip.automix.group = i }
        case "automix/weight":
            if let f = first?.floatValue { strip.automix.weightWire = Double(f) }

        default:
            applyStripPatterned(strip, path, values)
        }
    }

    private func applyStripPatterned(_ strip: StripState, _ path: String, _ values: [OSCValue]) {
        let first = values.first
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // Bus / FX sends:  mix/07/level
        if parts.count == 3, parts[0] == "mix", parts[2] == "level",
           let slot = Int(parts[1]), let f = first?.floatValue {
            let i = slot - 1
            if strip.sendWires.indices.contains(i) { strip.sendWires[i] = Double(f) }
            return
        }

        // Parametric EQ band:  eq/2/g
        if parts.count == 3, parts[0] == "eq", let band = Int(parts[1]),
           var state = strip.eq[band] {
            switch parts[2] {
            case "type":
                if let i = first?.intValue, let t = XAirEQBandType(rawValue: i) { state.type = t }
            case "f":
                if let f = first?.floatValue { state.frequencyWire = Double(f) }
            case "g":
                if let f = first?.floatValue { state.gainWire = Double(f) }
            case "q":
                if let f = first?.floatValue { state.qWire = Double(f) }
            default: return
            }
            strip.eq[band] = state
            return
        }

        // Graphic EQ:  geq/3k15
        if parts.count == 2, parts[0] == "geq", let f = first?.floatValue,
           let i = XAirGEQ.bands.firstIndex(where: { $0.address == parts[1] }) {
            if strip.graphicEQWires.indices.contains(i) { strip.graphicEQWires[i] = Double(f) }
            return
        }

        // Preamp
        if parts.count == 2, parts[0] == "preamp" {
            switch parts[1] {
            case "invert": if let b = first?.boolValue { strip.preamp.invert = b }
            case "hpon": if let b = first?.boolValue { strip.preamp.highPassOn = b }
            case "hpf": if let f = first?.floatValue { strip.preamp.highPassWire = Double(f) }
            case "rtntrim": if let f = first?.floatValue { strip.preamp.usbTrimWire = Double(f) }
            case "rtnsw": if let b = first?.boolValue { strip.preamp.usbInput = b }
            default: break
            }
            return
        }

        // Gate, including its sidechain filter
        if parts.first == "gate" {
            applyGate(strip, Array(parts.dropFirst()), first)
            return
        }

        // Compressor / expander
        if parts.first == "dyn" {
            applyDynamics(strip, Array(parts.dropFirst()), first)
            return
        }
    }

    private func applyGate(_ strip: StripState, _ parts: [String], _ first: OSCValue?) {
        if parts.count == 2, parts[0] == "filter" {
            switch parts[1] {
            case "on": if let b = first?.boolValue { strip.gate.filter.on = b }
            case "type":
                if let i = first?.intValue, let t = XAirFilterType(rawValue: i) { strip.gate.filter.type = t }
            case "f": if let f = first?.floatValue { strip.gate.filter.frequencyWire = Double(f) }
            default: break
            }
            return
        }
        guard parts.count == 1 else { return }
        switch parts[0] {
        case "on": if let b = first?.boolValue { strip.gate.on = b }
        case "mode":
            if let i = first?.intValue, let m = XAirGateMode(rawValue: i) { strip.gate.mode = m }
        case "thr": if let f = first?.floatValue { strip.gate.thresholdWire = Double(f) }
        case "range": if let f = first?.floatValue { strip.gate.rangeWire = Double(f) }
        case "attack": if let f = first?.floatValue { strip.gate.attackWire = Double(f) }
        case "hold": if let f = first?.floatValue { strip.gate.holdWire = Double(f) }
        case "release": if let f = first?.floatValue { strip.gate.releaseWire = Double(f) }
        case "keysrc": if let i = first?.intValue { strip.gate.keySource = i }
        default: break
        }
    }

    private func applyDynamics(_ strip: StripState, _ parts: [String], _ first: OSCValue?) {
        if parts.count == 2, parts[0] == "filter" {
            switch parts[1] {
            case "on": if let b = first?.boolValue { strip.dynamics.filter.on = b }
            case "type":
                if let i = first?.intValue, let t = XAirFilterType(rawValue: i) { strip.dynamics.filter.type = t }
            case "f": if let f = first?.floatValue { strip.dynamics.filter.frequencyWire = Double(f) }
            default: break
            }
            return
        }
        guard parts.count == 1 else { return }
        switch parts[0] {
        case "on": if let b = first?.boolValue { strip.dynamics.on = b }
        case "mode":
            if let i = first?.intValue, let m = XAirDynMode(rawValue: i) { strip.dynamics.mode = m }
        case "det":
            if let i = first?.intValue, let d = XAirDynDetection(rawValue: i) { strip.dynamics.detection = d }
        case "env":
            if let i = first?.intValue, let e = XAirDynEnvelope(rawValue: i) { strip.dynamics.envelope = e }
        case "thr": if let f = first?.floatValue { strip.dynamics.thresholdWire = Double(f) }
        case "ratio": if let i = first?.intValue { strip.dynamics.ratioIndex = i }
        case "knee": if let f = first?.floatValue { strip.dynamics.kneeWire = Double(f) }
        case "mgain": if let f = first?.floatValue { strip.dynamics.makeupWire = Double(f) }
        case "attack": if let f = first?.floatValue { strip.dynamics.attackWire = Double(f) }
        case "hold": if let f = first?.floatValue { strip.dynamics.holdWire = Double(f) }
        case "release": if let f = first?.floatValue { strip.dynamics.releaseWire = Double(f) }
        case "mix": if let f = first?.floatValue { strip.dynamics.mixWire = Double(f) }
        case "keysrc": if let i = first?.intValue { strip.dynamics.keySource = i }
        case "auto": if let b = first?.boolValue { strip.dynamics.autoTime = b }
        default: break
        }
    }

    // MARK: Desk-wide parameters

    private func applyGlobal(_ address: String, _ values: [OSCValue]) {
        let first = values.first

        switch address {
        case XAirAddress.xinfo, XAirAddress.info:
            let strings = values.compactMap { $0.stringValue }
            if strings.count >= 4 {
                info = DeskInfo(ip: strings[0], name: strings[1], model: strings[2], firmware: strings[3])
                let detected = XAirModel.named(strings[2])
                if detected.id != model.id { configure(model: detected) }
            }
            return

        case XAirAddress.automixEnable:
            if let b = first?.boolValue { automixEnabled = b }
            return
        case XAirAddress.automixLock:
            if let b = first?.boolValue { automixLocked = b }
            return

        // Monitor / solo bus
        case XAirAddress.soloLevel:
            if let f = first?.floatValue { monitor.levelWire = Double(f) }
            return
        case XAirAddress.soloSource:
            if let i = first?.intValue { monitor.source = i }
            return
        case XAirAddress.soloSourceTrim:
            if let f = first?.floatValue { monitor.trimWire = Double(f) }
            return
        case XAirAddress.soloDim:
            if let b = first?.boolValue { monitor.dim = b }
            return
        case XAirAddress.soloDimAttenuation:
            if let f = first?.floatValue { monitor.dimAttenuationWire = Double(f) }
            return
        case XAirAddress.soloMono:
            if let b = first?.boolValue { monitor.mono = b }
            return
        case XAirAddress.soloMute:
            if let b = first?.boolValue { monitor.mute = b }
            return
        case XAirAddress.soloDimFPL:
            if let b = first?.boolValue { monitor.dimFollowsPFL = b }
            return
        case XAirAddress.soloChannelMode:
            if let b = first?.boolValue { monitor.channelMode = b }
            return
        case XAirAddress.soloBusMode:
            if let b = first?.boolValue { monitor.busMode = b }
            return

        // Link configuration
        case XAirAddress.linkEQ:
            if let b = first?.boolValue { links.linksEQ = b }
            return
        case XAirAddress.linkDynamics:
            if let b = first?.boolValue { links.linksDynamics = b }
            return
        case XAirAddress.linkFaderMute:
            if let b = first?.boolValue { links.linksFaderAndMute = b }
            return

        // Snapshots
        case XAirAddress.snapshotIndex:
            if let i = first?.intValue { currentSnapshot = i }
            return

        // USB recorder
        case XAirAddress.tapeState:
            if let i = first?.intValue, let s = XAirTapeState(rawValue: i) { tape.state = s }
            return
        case XAirAddress.tapeFile:
            if let s = first?.stringValue { tape.file = s }
            return
        case XAirAddress.tapePosition:
            if let s = first?.stringValue { tape.elapsed = s }
            return
        case XAirAddress.tapeRemaining:
            if let s = first?.stringValue { tape.remaining = s }
            return

        default:
            break
        }

        applyGlobalPatterned(address, values)
    }

    private func applyGlobalPatterned(_ address: String, _ values: [OSCValue]) {
        let first = values.first
        let parts = address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // /config/mute/2
        if parts.count == 3, parts[0] == "config", parts[1] == "mute",
           let index = Int(parts[2]), let b = first?.boolValue {
            let i = index - 1
            if muteGroups.indices.contains(i) { muteGroups[i] = b }
            return
        }

        // /config/chlink/1-2  and  /config/buslink/3-4
        if parts.count == 3, parts[0] == "config",
           parts[1] == "chlink" || parts[1] == "buslink",
           let odd = Int(parts[2].split(separator: "-").first ?? ""),
           let b = first?.boolValue {
            if parts[1] == "chlink" { links.channelLinks[odd] = b } else { links.busLinks[odd] = b }
            return
        }

        // /headamp/03/gain
        if parts.count == 3, parts[0] == "headamp", let index = Int(parts[1]) {
            guard let i = headamps.firstIndex(where: { $0.index == index }) else { return }
            switch parts[2] {
            case "gain": if let f = first?.floatValue { headamps[i].gainWire = Double(f) }
            case "phantom": if let b = first?.boolValue { headamps[i].phantom = b }
            default: break
            }
            return
        }

        // /fx/2/type  and  /fx/2/par/05
        if parts.first == "fx", parts.count >= 3, let slot = Int(parts[1]),
           let i = fx.firstIndex(where: { $0.slot == slot }) {
            if parts.count == 3, parts[2] == "type", let t = first?.intValue {
                fx[i].typeIndex = t
                return
            }
            if parts.count == 4, parts[2] == "par", let p = Int(parts[3]),
               let f = first?.floatValue {
                let index = p - 1
                if fx[i].parameters.indices.contains(index) { fx[i].parameters[index] = Double(f) }
                return
            }
            return
        }

        // /-stat/solosw/07
        if parts.count == 3, parts[0] == "-stat", parts[1] == "solosw",
           let index = Int(parts[2]), let b = first?.boolValue {
            if let id = stripIDBySoloIndex[index] { strip(id).solo = b }
            return
        }

        // /-snap/12/name
        if parts.count == 3, parts[0] == "-snap", let index = Int(parts[1]),
           parts[2] == "name", let s = first?.stringValue {
            snapshotNames[index] = s
            return
        }
    }

    // MARK: Reset

    /// Clears mirrored values so a stale picture never survives a reconnect.
    func invalidate() {
        for id in stripOrder { strips[id]?.isSynced = false }
        meters.reset()
    }
}
