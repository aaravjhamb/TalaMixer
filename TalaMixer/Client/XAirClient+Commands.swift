//
//  XAirClient+Commands.swift
//  TalaMixer
//
//  The typed write API the UI calls. Every setter updates the local mirror
//  first so controls track a finger with no round-trip latency, then puts the
//  value on the wire.
//

import Foundation
import SwiftUI

@MainActor
extension XAirClient {

    // MARK: - Levels and mix

    func setFader(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).faderWire = value
        write(id.faderAddress, .float(Float(value)))
    }

    func setFader(_ id: StripID, db: Double) {
        setFader(id, wire: P.fader.wire(fromValue: db))
    }

    func setSendLevel(_ id: StripID, slot: Int, wire: Double) {
        let value = wire.clampedToUnit
        let strip = state.strip(id)
        let index = slot - 1
        guard strip.sendWires.indices.contains(index) else { return }
        strip.sendWires[index] = value
        write(id.sendLevelAddress(slot), .float(Float(value)))
    }

    func setPan(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).panWire = value
        write(id.panAddress, .float(Float(value)))
    }

    func setMuted(_ id: StripID, _ muted: Bool) {
        state.strip(id).on = !muted
        writeNow(id.onAddress, .int(muted ? 0 : 1))
    }

    func toggleMute(_ id: StripID) {
        setMuted(id, !state.strip(id).isMuted)
    }

    func setMainAssign(_ id: StripID, _ assigned: Bool) {
        state.strip(id).assignedToMain = assigned
        writeNow(id.mainAssignAddress, .int(assigned ? 1 : 0))
    }

    /// Call when a continuous gesture finishes, so a change made on the desk
    /// during the drag isn't left hidden by echo suppression.
    ///
    /// The re-read waits a beat: any reply still in flight from the drag lands
    /// inside the suppression window instead of after it, where it would snap
    /// the control back to a stale value.
    func endGesture(_ address: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.resync(address)
        }
    }

    // MARK: - Identity

    func setName(_ id: StripID, _ name: String) {
        // The desk truncates to 12 characters; do it here so the UI agrees.
        let trimmed = String(name.prefix(12))
        state.strip(id).name = trimmed
        writeNow(id.nameAddress, .string(trimmed))
    }

    func setColor(_ id: StripID, _ color: XAirColor) {
        state.strip(id).colorIndex = color.rawValue
        writeNow(id.colorAddress, .int(Int32(color.rawValue)))
    }

    func setInputSource(_ id: StripID, _ source: Int) {
        state.strip(id).inputSource = source
        writeNow(id.inputSourceAddress, .int(Int32(source)))
    }

    func setUSBReturnSource(_ id: StripID, _ source: Int) {
        state.strip(id).usbReturnSource = source
        writeNow(id.usbReturnSourceAddress, .int(Int32(source)))
    }

    // MARK: - Solo and mute groups

    func setSolo(_ id: StripID, _ on: Bool) {
        guard let index = XAirAddress.soloIndex(for: id, model: state.model) else { return }
        state.strip(id).solo = on
        writeNow(XAirAddress.soloSwitch(index), .int(on ? 1 : 0))
    }

    func toggleSolo(_ id: StripID) {
        setSolo(id, !state.strip(id).solo)
    }

    func clearAllSolos() {
        for id in state.stripOrder where state.strip(id).solo {
            setSolo(id, false)
        }
        writeNow(XAirAddress.clearSolo, .int(1))
    }

    var hasAnySolo: Bool {
        state.stripOrder.contains { state.strip($0).solo }
    }

    func setMuteGroup(_ index: Int, _ on: Bool) {
        let i = index - 1
        guard state.muteGroups.indices.contains(i) else { return }
        state.muteGroups[i] = on
        writeNow(XAirAddress.muteGroup(index), .int(on ? 1 : 0))
    }

    func toggleMuteGroup(_ index: Int) {
        let i = index - 1
        guard state.muteGroups.indices.contains(i) else { return }
        setMuteGroup(index, !state.muteGroups[i])
    }

    // MARK: - Group assignment

    func setDCAAssignment(_ id: StripID, dca: Int, on: Bool) {
        let strip = state.strip(id)
        let mask = strip.dcaMask.settingGroupBit(dca, to: on)
        strip.dcaMask = mask
        writeNow(id.dcaAssignAddress, .int(Int32(mask)))
    }

    func setMuteGroupAssignment(_ id: StripID, group: Int, on: Bool) {
        let strip = state.strip(id)
        let mask = strip.muteGroupMask.settingGroupBit(group, to: on)
        strip.muteGroupMask = mask
        writeNow(id.muteGroupAssignAddress, .int(Int32(mask)))
    }

    // MARK: - Preamp

    func setPhaseInvert(_ id: StripID, _ on: Bool) {
        state.strip(id).preamp.invert = on
        writeNow(id.preampAddress("invert"), .int(on ? 1 : 0))
    }

    func setHighPassOn(_ id: StripID, _ on: Bool) {
        state.strip(id).preamp.highPassOn = on
        writeNow(id.preampAddress("hpon"), .int(on ? 1 : 0))
    }

    func setHighPass(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).preamp.highPassWire = value
        write(id.preampAddress("hpf"), .float(Float(value)))
    }

    func setUSBTrim(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).preamp.usbTrimWire = value
        write(id.preampAddress("rtntrim"), .float(Float(value)))
    }

    func setUSBInput(_ id: StripID, _ on: Bool) {
        state.strip(id).preamp.usbInput = on
        writeNow(id.preampAddress("rtnsw"), .int(on ? 1 : 0))
    }

    func setHeadampGain(_ index: Int, wire: Double) {
        let value = wire.clampedToUnit
        guard let i = state.headamps.firstIndex(where: { $0.index == index }) else { return }
        state.headamps[i].gainWire = value
        write(XAirAddress.headampGain(index), .float(Float(value)))
    }

    func setPhantom(_ index: Int, _ on: Bool) {
        guard let i = state.headamps.firstIndex(where: { $0.index == index }) else { return }
        state.headamps[i].phantom = on
        writeNow(XAirAddress.headampPhantom(index), .int(on ? 1 : 0))
    }

    // MARK: - Gate

    func setGateOn(_ id: StripID, _ on: Bool) {
        state.strip(id).gate.on = on
        writeNow(id.gateAddress("on"), .int(on ? 1 : 0))
    }

    func setGateMode(_ id: StripID, _ mode: XAirGateMode) {
        state.strip(id).gate.mode = mode
        writeNow(id.gateAddress("mode"), .int(Int32(mode.rawValue)))
    }

    func setGateParameter(_ id: StripID, _ parameter: GateParameter, wire: Double) {
        let value = wire.clampedToUnit
        let gate = state.strip(id).gate
        var updated = gate
        switch parameter {
        case .threshold: updated.thresholdWire = value
        case .range: updated.rangeWire = value
        case .attack: updated.attackWire = value
        case .hold: updated.holdWire = value
        case .release: updated.releaseWire = value
        }
        state.strip(id).gate = updated
        write(id.gateAddress(parameter.oscName), .float(Float(value)))
    }

    func setGateFilterOn(_ id: StripID, _ on: Bool) {
        state.strip(id).gate.filter.on = on
        writeNow(id.gateAddress("filter/on"), .int(on ? 1 : 0))
    }

    func setGateFilterType(_ id: StripID, _ type: XAirFilterType) {
        state.strip(id).gate.filter.type = type
        writeNow(id.gateAddress("filter/type"), .int(Int32(type.rawValue)))
    }

    func setGateFilterFrequency(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).gate.filter.frequencyWire = value
        write(id.gateAddress("filter/f"), .float(Float(value)))
    }

    func setGateKeySource(_ id: StripID, _ source: Int) {
        state.strip(id).gate.keySource = source
        writeNow(id.gateAddress("keysrc"), .int(Int32(source)))
    }

    // MARK: - Dynamics

    func setDynamicsOn(_ id: StripID, _ on: Bool) {
        state.strip(id).dynamics.on = on
        writeNow(id.dynAddress("on"), .int(on ? 1 : 0))
    }

    func setDynamicsMode(_ id: StripID, _ mode: XAirDynMode) {
        state.strip(id).dynamics.mode = mode
        writeNow(id.dynAddress("mode"), .int(Int32(mode.rawValue)))
    }

    func setDynamicsDetection(_ id: StripID, _ detection: XAirDynDetection) {
        state.strip(id).dynamics.detection = detection
        writeNow(id.dynAddress("det"), .int(Int32(detection.rawValue)))
    }

    func setDynamicsEnvelope(_ id: StripID, _ envelope: XAirDynEnvelope) {
        state.strip(id).dynamics.envelope = envelope
        writeNow(id.dynAddress("env"), .int(Int32(envelope.rawValue)))
    }

    func setDynamicsRatio(_ id: StripID, index: Int) {
        let clamped = min(max(0, index), XAirDynRatio.values.count - 1)
        state.strip(id).dynamics.ratioIndex = clamped
        writeNow(id.dynAddress("ratio"), .int(Int32(clamped)))
    }

    func setDynamicsAutoTime(_ id: StripID, _ on: Bool) {
        state.strip(id).dynamics.autoTime = on
        writeNow(id.dynAddress("auto"), .int(on ? 1 : 0))
    }

    func setDynamicsParameter(_ id: StripID, _ parameter: DynamicsParameter, wire: Double) {
        let value = wire.clampedToUnit
        var updated = state.strip(id).dynamics
        switch parameter {
        case .threshold: updated.thresholdWire = value
        case .knee: updated.kneeWire = value
        case .makeup: updated.makeupWire = value
        case .attack: updated.attackWire = value
        case .hold: updated.holdWire = value
        case .release: updated.releaseWire = value
        case .mix: updated.mixWire = value
        }
        state.strip(id).dynamics = updated
        write(id.dynAddress(parameter.oscName), .float(Float(value)))
    }

    func setDynamicsFilterOn(_ id: StripID, _ on: Bool) {
        state.strip(id).dynamics.filter.on = on
        writeNow(id.dynAddress("filter/on"), .int(on ? 1 : 0))
    }

    func setDynamicsFilterType(_ id: StripID, _ type: XAirFilterType) {
        state.strip(id).dynamics.filter.type = type
        writeNow(id.dynAddress("filter/type"), .int(Int32(type.rawValue)))
    }

    func setDynamicsFilterFrequency(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).dynamics.filter.frequencyWire = value
        write(id.dynAddress("filter/f"), .float(Float(value)))
    }

    func setDynamicsKeySource(_ id: StripID, _ source: Int) {
        state.strip(id).dynamics.keySource = source
        writeNow(id.dynAddress("keysrc"), .int(Int32(source)))
    }

    // MARK: - EQ

    func setEQOn(_ id: StripID, _ on: Bool) {
        state.strip(id).eq.on = on
        writeNow(id.eqOnAddress, .int(on ? 1 : 0))
    }

    func setEQMode(_ id: StripID, _ mode: XAirEQMode) {
        state.strip(id).eq.mode = mode
        writeNow(id.eqModeAddress, .int(Int32(mode.rawValue)))
    }

    func setEQBandType(_ id: StripID, band: Int, _ type: XAirEQBandType) {
        updateEQBand(id, band: band) { $0.type = type }
        writeNow(id.eqAddress(band: band, "type"), .int(Int32(type.rawValue)))
    }

    func setEQFrequency(_ id: StripID, band: Int, wire: Double) {
        let value = wire.clampedToUnit
        updateEQBand(id, band: band) { $0.frequencyWire = value }
        write(id.eqAddress(band: band, "f"), .float(Float(value)))
    }

    func setEQGain(_ id: StripID, band: Int, wire: Double) {
        let value = wire.clampedToUnit
        updateEQBand(id, band: band) { $0.gainWire = value }
        write(id.eqAddress(band: band, "g"), .float(Float(value)))
    }

    /// `q` is the displayed value (0.3 – 10); the inversion happens here.
    func setEQQ(_ id: StripID, band: Int, q: Double) {
        let wire = P.qWire(fromQ: q.clamped(to: P.qRange)).clampedToUnit
        updateEQBand(id, band: band) { $0.qWire = wire }
        write(id.eqAddress(band: band, "q"), .float(Float(wire)))
    }

    func resetEQBand(_ id: StripID, band: Int) {
        setEQGain(id, band: band, wire: P.eqGain.wire(fromValue: 0))
    }

    private func updateEQBand(_ id: StripID, band: Int, _ mutate: (inout EQBandState) -> Void) {
        let strip = state.strip(id)
        guard var state = strip.eq[band] else { return }
        mutate(&state)
        strip.eq[band] = state
    }

    // MARK: - Graphic EQ

    func setGraphicEQ(_ id: StripID, bandIndex: Int, wire: Double) {
        let value = wire.clampedToUnit
        let strip = state.strip(id)
        guard strip.graphicEQWires.indices.contains(bandIndex),
              XAirGEQ.bands.indices.contains(bandIndex) else { return }
        strip.graphicEQWires[bandIndex] = value
        write(id.graphicEQAddress(XAirGEQ.bands[bandIndex].address), .float(Float(value)))
    }

    func flattenGraphicEQ(_ id: StripID) {
        let flat = P.graphicEQGain.wire(fromValue: 0)
        for index in XAirGEQ.bands.indices {
            setGraphicEQ(id, bandIndex: index, wire: flat)
        }
    }

    // MARK: - Insert and automix

    func setInsertOn(_ id: StripID, _ on: Bool) {
        state.strip(id).insert.on = on
        writeNow(id.insertOnAddress, .int(on ? 1 : 0))
    }

    func setInsertSelection(_ id: StripID, _ selection: Int) {
        state.strip(id).insert.selection = selection
        writeNow(id.insertSelAddress, .int(Int32(selection)))
    }

    func setAutomixGroup(_ id: StripID, _ group: Int) {
        state.strip(id).automix.group = group
        writeNow(id.automixGroupAddress, .int(Int32(group)))
    }

    func setAutomixWeight(_ id: StripID, wire: Double) {
        let value = wire.clampedToUnit
        state.strip(id).automix.weightWire = value
        write(id.automixWeightAddress, .float(Float(value)))
    }

    func setAutomixEnabled(_ on: Bool) {
        state.automixEnabled = on
        writeNow(XAirAddress.automixEnable, .int(on ? 1 : 0))
    }

    func setAutomixLocked(_ on: Bool) {
        state.automixLocked = on
        writeNow(XAirAddress.automixLock, .int(on ? 1 : 0))
    }

    // MARK: - Effects

    func setFXType(_ slot: Int, index: Int) {
        guard let i = state.fx.firstIndex(where: { $0.slot == slot }) else { return }
        state.fx[i].typeIndex = index
        writeNow(XAirAddress.fxType(slot), .int(Int32(index)))
        // A new engine means a new parameter set — pull it fresh.
        syncFXSlot(slot)
    }

    func setFXParameter(_ slot: Int, parameter: Int, wire: Double) {
        let value = wire.clampedToUnit
        guard let i = state.fx.firstIndex(where: { $0.slot == slot }) else { return }
        let index = parameter - 1
        guard state.fx[i].parameters.indices.contains(index) else { return }
        state.fx[i].parameters[index] = value
        write(XAirAddress.fxParameter(slot, parameter), .float(Float(value)))
    }

    // MARK: - Monitor bus

    func setMonitorLevel(wire: Double) {
        let value = wire.clampedToUnit
        state.monitor.levelWire = value
        write(XAirAddress.soloLevel, .float(Float(value)))
    }

    func setMonitorSource(_ source: Int) {
        state.monitor.source = source
        writeNow(XAirAddress.soloSource, .int(Int32(source)))
    }

    func setMonitorTrim(wire: Double) {
        let value = wire.clampedToUnit
        state.monitor.trimWire = value
        write(XAirAddress.soloSourceTrim, .float(Float(value)))
    }

    func setMonitorDim(_ on: Bool) {
        state.monitor.dim = on
        writeNow(XAirAddress.soloDim, .int(on ? 1 : 0))
    }

    func setMonitorDimAttenuation(wire: Double) {
        let value = wire.clampedToUnit
        state.monitor.dimAttenuationWire = value
        write(XAirAddress.soloDimAttenuation, .float(Float(value)))
    }

    func setMonitorMono(_ on: Bool) {
        state.monitor.mono = on
        writeNow(XAirAddress.soloMono, .int(on ? 1 : 0))
    }

    func setMonitorMute(_ on: Bool) {
        state.monitor.mute = on
        writeNow(XAirAddress.soloMute, .int(on ? 1 : 0))
    }

    // MARK: - Stereo linking

    func setChannelLink(oddIndex: Int, _ on: Bool) {
        state.links.channelLinks[oddIndex] = on
        writeNow(XAirAddress.channelLink(oddIndex), .int(on ? 1 : 0))
    }

    func setBusLink(oddIndex: Int, _ on: Bool) {
        state.links.busLinks[oddIndex] = on
        writeNow(XAirAddress.busLink(oddIndex), .int(on ? 1 : 0))
    }

    func setLinksEQ(_ on: Bool) {
        state.links.linksEQ = on
        writeNow(XAirAddress.linkEQ, .int(on ? 1 : 0))
    }

    func setLinksDynamics(_ on: Bool) {
        state.links.linksDynamics = on
        writeNow(XAirAddress.linkDynamics, .int(on ? 1 : 0))
    }

    func setLinksFaderAndMute(_ on: Bool) {
        state.links.linksFaderAndMute = on
        writeNow(XAirAddress.linkFaderMute, .int(on ? 1 : 0))
    }

    // MARK: - Snapshots

    func loadSnapshot(_ index: Int) {
        writeNow(XAirAddress.snapshotLoad, .int(Int32(index)))
        state.currentSnapshot = index
        // A recall rewrites nearly everything; re-read the surface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.resyncEverything()
        }
    }

    func saveSnapshot(_ index: Int) {
        writeNow(XAirAddress.snapshotSave, .int(Int32(index)))
    }

    func renameSnapshot(_ index: Int, name: String) {
        let trimmed = String(name.prefix(12))
        state.snapshotNames[index] = trimmed
        writeNow(XAirAddress.snapshotName(index), .string(trimmed))
    }

    // MARK: - USB recorder

    func setTapeState(_ tapeState: XAirTapeState) {
        state.tape.state = tapeState
        writeNow(XAirAddress.tapeState, .int(Int32(tapeState.rawValue)))
    }

    // MARK: - Desk identity

    /// Renames the mixer itself — the name it announces over the network.
    func renameDesk(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(16))
        guard !trimmed.isEmpty else { return }
        writeNow("/-prefs/name", .string(trimmed))
        state.info.name = trimmed
        // Re-read the announcement so the mirror reflects what the desk kept.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.resync(XAirAddress.xinfo)
        }
    }

    // MARK: - Raw access (OSC Inspector)

    func sendRaw(_ address: String, values: [OSCValue]) {
        writeNow(address, values.first ?? .int(0))
        if values.count > 1 {
            // Multi-argument sends bypass the coalescing path entirely.
            rawMultiSend(OSCMessage(address, values))
        }
    }

    func queryRaw(_ address: String) {
        resync(address)
    }
}

// MARK: - Parameter identifiers

enum GateParameter: String, CaseIterable, Identifiable {
    case threshold, range, attack, hold, release

    var id: String { rawValue }

    var oscName: String {
        switch self {
        case .threshold: return "thr"
        case .range: return "range"
        case .attack: return "attack"
        case .hold: return "hold"
        case .release: return "release"
        }
    }

    var title: String {
        switch self {
        case .threshold: return "Threshold"
        case .range: return "Range"
        case .attack: return "Attack"
        case .hold: return "Hold"
        case .release: return "Release"
        }
    }

    var scale: XAirScale {
        switch self {
        case .threshold: return P.gateThreshold
        case .range: return P.gateRange
        case .attack: return P.attack
        case .hold: return P.hold
        case .release: return P.release
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .threshold: return XAirFormat.decibelsWithUnit(value)
        case .range: return String(format: "%.0f dB", value)
        case .attack, .hold, .release: return XAirFormat.milliseconds(value)
        }
    }

    func wire(from state: GateState) -> Double {
        switch self {
        case .threshold: return state.thresholdWire
        case .range: return state.rangeWire
        case .attack: return state.attackWire
        case .hold: return state.holdWire
        case .release: return state.releaseWire
        }
    }
}

enum DynamicsParameter: String, CaseIterable, Identifiable {
    case threshold, knee, makeup, attack, hold, release, mix

    var id: String { rawValue }

    var oscName: String {
        switch self {
        case .threshold: return "thr"
        case .knee: return "knee"
        case .makeup: return "mgain"
        case .attack: return "attack"
        case .hold: return "hold"
        case .release: return "release"
        case .mix: return "mix"
        }
    }

    var title: String {
        switch self {
        case .threshold: return "Threshold"
        case .knee: return "Knee"
        case .makeup: return "Makeup"
        case .attack: return "Attack"
        case .hold: return "Hold"
        case .release: return "Release"
        case .mix: return "Mix"
        }
    }

    var scale: XAirScale {
        switch self {
        case .threshold: return P.dynThreshold
        case .knee: return P.knee
        case .makeup: return P.makeupGain
        case .attack: return P.attack
        case .hold: return P.hold
        case .release: return P.release
        case .mix: return P.dryWetMix
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .threshold: return XAirFormat.decibelsWithUnit(value)
        case .knee: return String(format: "%.1f", value)
        case .makeup: return String(format: "%.1f dB", value)
        case .attack, .hold, .release: return XAirFormat.milliseconds(value)
        case .mix: return XAirFormat.percent(value)
        }
    }

    func wire(from state: DynamicsState) -> Double {
        switch self {
        case .threshold: return state.thresholdWire
        case .knee: return state.kneeWire
        case .makeup: return state.makeupWire
        case .attack: return state.attackWire
        case .hold: return state.holdWire
        case .release: return state.releaseWire
        case .mix: return state.mixWire
        }
    }
}

// MARK: - Sync-on-session

extension View {
    /// Runs `action` when the view appears, and again each time the desk
    /// establishes a session.
    ///
    /// Connecting resets the client's sync queue, so a panel that asked for its
    /// data before (or during) a connect would otherwise sit on defaults
    /// forever.
    func syncOnSession(_ client: XAirClient, _ action: @escaping () -> Void) -> some View {
        onAppear(perform: action)
            .onChange(of: client.sessionID) { _, _ in action() }
    }
}
