//
//  XAirClient.swift
//  TalaMixer
//
//  Owns the link to the desk: subscription upkeep, state synchronisation,
//  outbound rate limiting, and the typed setters the UI calls.
//

import Foundation
import Observation

@MainActor
@Observable
final class XAirClient {

    enum Status: Equatable {
        case disconnected
        case connecting
        case syncing(progress: Double)
        case connected
        case failed(String)

        var isLive: Bool {
            switch self {
            case .connected, .syncing: return true
            default: return false
            }
        }
    }

    // MARK: Published state

    private(set) var status: Status = .disconnected
    let state = MixerState()
    let log = OSCLog()
    let clipboard = ChannelClipboard()
    let presets = PresetStore()

    /// True when we're driving the built-in demo desk rather than real hardware.
    private(set) var isDemo = false

    /// Increments each time a session is established. Panels observe this to
    /// re-request their data after a connect or reconnect — a connect clears the
    /// sync queue, so anything queued beforehand is gone.
    private(set) var sessionID = 0

    var host: String = ""
    var port: UInt16 = 10024

    // MARK: Internals

    private var link: OSCLink?

    private var keepAliveTimer: Timer?
    private var flushTimer: Timer?
    private var syncTimer: Timer?
    private var meterFallbackWork: DispatchWorkItem?

    /// Latest value per address, waiting to go out on the next flush.
    private var outbox: [String: OSCValue] = [:]
    private var outboxOrder: [String] = []

    /// Addresses we've written recently — inbound echoes for these are dropped
    /// so the desk can't fight a finger that's mid-drag.
    private var recentWrites: [String: Date] = [:]
    private let echoSuppression: TimeInterval = 0.25

    /// Addresses still to be queried during a state sync.
    private var syncQueue: [String] = []
    private var syncTotal = 0

    /// Strips whose full parameter set we've already pulled.
    private var deepSynced: Set<StripID> = []

    /// Set once the desk is subscribed and ready to answer queries. Queries
    /// raised before this (a detail view opened during connect, say) sit in the
    /// queue rather than being fired into a socket that will drop them.
    private var isSessionReady = false

    private var hasSeenMeters = false

    // Timing
    private let flushInterval: TimeInterval = 0.02      // 50 Hz outbound
    private let keepAliveInterval: TimeInterval = 7     // subscriptions expire at 10 s
    private let syncInterval: TimeInterval = 0.012      // one burst every 12 ms
    private let syncBurstSize = 6

    // MARK: - Lifecycle

    func connect(host: String, port: UInt16 = 10024, demo: Bool = false) {
        disconnect()

        self.host = host
        self.port = port
        self.isDemo = demo
        status = .connecting

        let link: OSCLink = demo ? VirtualXAir() : OSCTransport()
        link.onMessage = { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }
        link.onState = { [weak self] linkState in
            Task { @MainActor in self?.handleLinkState(linkState) }
        }
        self.link = link
        link.connect(host: host, port: port)

        startFlushTimer()
    }

    func disconnect() {
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
        syncTimer?.invalidate(); syncTimer = nil
        meterFallbackWork?.cancel(); meterFallbackWork = nil

        if link != nil {
            send(OSCMessage(XAirAddress.unsubscribe), immediate: true)
        }
        link?.onMessage = nil
        link?.onState = nil
        link?.disconnect()
        link = nil

        outbox.removeAll()
        outboxOrder.removeAll()
        recentWrites.removeAll()
        syncQueue.removeAll()
        deepSynced.removeAll()
        hasSeenMeters = false
        isSessionReady = false

        state.invalidate()
        status = .disconnected
    }

    private func handleLinkState(_ linkState: OSCLinkState) {
        switch linkState {
        case .idle:
            if status.isLive { status = .disconnected }
        case .connecting:
            status = .connecting
        case .ready:
            beginSession()
        case .failed(let reason):
            status = .failed(reason)
        }
    }

    /// Identify the desk, subscribe, then pull the state the mixer view needs.
    private func beginSession() {
        status = .syncing(progress: 0)
        isSessionReady = true
        sessionID += 1
        send(OSCMessage(XAirAddress.xinfo), immediate: true)
        send(OSCMessage(XAirAddress.status), immediate: true)

        renewSubscriptions()
        subscribeToMeters()

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renewSubscriptions() }
        }

        // Give /xinfo a moment to land so the model (and therefore the strip
        // list) is right before we build the query list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startSurfaceSync()
        }
    }

    // MARK: - Subscriptions

    private func renewSubscriptions() {
        // The no-feedback variant: the desk reports changes made elsewhere but
        // does NOT echo our own writes back. With plain /xremote, late echoes of
        // our own fader moves would arrive after a gesture ended and nudge
        // controls by themselves. Must be re-sent inside every 10 s window.
        send(OSCMessage(XAirAddress.xremoteNoFeedback), immediate: true)
        send(OSCMessage(XAirAddress.renew, .string(Self.meterAlias)), immediate: true)
        // Re-subscribing (rather than renewing) is idempotent and also covers
        // the case where a view wanted the RTA before the session was ready.
        if rtaWanted > 0 { subscribeToRTA() }
    }

    private static let meterAlias = "/meters/1"
    private static let rtaAlias = "/meters/4"

    /// How many views currently want the RTA stream. Subscribed while > 0.
    private var rtaWanted = 0

    /// Views call these in matched pairs (appear/disappear). The RTA runs at
    /// meter rate and is only worth the traffic while something draws it.
    func beginRTA() {
        rtaWanted += 1
        if rtaWanted == 1 { subscribeToRTA() }
    }

    func endRTA() {
        rtaWanted = max(0, rtaWanted - 1)
    }

    private func subscribeToRTA() {
        guard isSessionReady else { return }
        send(OSCMessage(XAirAddress.batchSubscribe, [
            .string(Self.rtaAlias),
            .string(XAirAddress.meters(XAirMeterBank.rta.rawValue)),
            .int(0), .int(0), .int(2),
        ]), immediate: true)
    }

    private func subscribeToMeters() {
        // alias, path, from, to, time factor (1 = fastest)
        send(OSCMessage(XAirAddress.batchSubscribe, [
            .string(Self.meterAlias),
            .string(XAirAddress.meters(XAirMeterBank.all.rawValue)),
            .int(0), .int(0), .int(1),
        ]), immediate: true)

        // Some firmware revisions want the plain form instead. If nothing has
        // arrived shortly, ask the other way too — a duplicate subscription is
        // harmless, silent meters are not.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasSeenMeters else { return }
            self.send(OSCMessage(XAirAddress.meters(XAirMeterBank.all.rawValue)), immediate: true)
            self.send(OSCMessage("/meters", .string(XAirAddress.meters(XAirMeterBank.all.rawValue))), immediate: true)
        }
        meterFallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: - Inbound

    private func receive(_ message: OSCMessage) {
        var message = message
        // Aliased subscription replies can come back without a leading slash.
        if !message.address.hasPrefix("/") {
            message.address = "/" + message.address
        }

        if message.address.hasPrefix("/meters/") {
            hasSeenMeters = true
            state.apply(message)
            return
        }

        log.record(.inbound, message)

        // Drop the desk's echo of a value we just wrote.
        if let written = recentWrites[message.address],
           Date().timeIntervalSince(written) < echoSuppression {
            return
        }

        state.apply(message)

        if case .syncing = status, syncQueue.isEmpty {
            status = .connected
        }
    }

    // MARK: - Outbound

    /// Queues a message. Repeated writes to the same address within one flush
    /// window collapse into the newest value, which is what keeps a fader drag
    /// from swamping the desk.
    private func send(_ message: OSCMessage, immediate: Bool = false) {
        guard let link else { return }

        if immediate {
            log.record(.outbound, message)
            link.send(message)
            return
        }

        if outbox[message.address] == nil {
            outboxOrder.append(message.address)
        }
        outbox[message.address] = message.values.first ?? .int(0)
        recentWrites[message.address] = Date()
    }

    /// Writes a parameter, coalesced into the next flush window.
    func write(_ address: String, _ value: OSCValue) {
        send(OSCMessage(address, value))
    }

    /// Writes a parameter right now, bypassing coalescing. Use for discrete
    /// actions — mutes, names, snapshot recalls — where 20 ms of latency shows.
    func writeNow(_ address: String, _ value: OSCValue) {
        recentWrites[address] = Date()
        send(OSCMessage(address, value), immediate: true)
    }

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    private func flush() {
        guard let link, !outboxOrder.isEmpty else { return }
        for address in outboxOrder {
            guard let value = outbox[address] else { continue }
            let message = OSCMessage(address, value)
            log.record(.outbound, message)
            link.send(message)
        }
        outboxOrder.removeAll(keepingCapacity: true)
        outbox.removeAll(keepingCapacity: true)
    }

    // MARK: - State synchronisation

    /// Queries everything the fader bank draws. Runs paced, not in one burst —
    /// the desk drops UDP replies if you flood it.
    private func startSurfaceSync() {
        var addresses: [String] = []

        for id in state.stripOrder {
            addresses.append(id.nameAddress)
            addresses.append(id.colorAddress)
            addresses.append(id.onAddress)
            addresses.append(id.faderAddress)
            if id.hasPan { addresses.append(id.panAddress) }
            if id.hasMainAssign { addresses.append(id.mainAssignAddress) }
            if id.hasGroupAssign {
                addresses.append(id.dcaAssignAddress)
                addresses.append(id.muteGroupAssignAddress)
            }
            if id.hasSends {
                for slot in 1...state.model.sendCount {
                    addresses.append(id.sendLevelAddress(slot))
                }
            }
            if let solo = XAirAddress.soloIndex(for: id, model: state.model) {
                addresses.append(XAirAddress.soloSwitch(solo))
            }
        }

        for group in 1...state.model.muteGroupCount {
            addresses.append(XAirAddress.muteGroup(group))
        }
        for slot in 1...state.model.fxCount {
            addresses.append(XAirAddress.fxType(slot))
        }
        for index in 1...state.model.channelCount {
            addresses.append(XAirAddress.headampGain(index))
            addresses.append(XAirAddress.headampPhantom(index))
        }
        addresses.append(contentsOf: [
            XAirAddress.automixEnable, XAirAddress.automixLock,
            XAirAddress.soloLevel, XAirAddress.soloSource, XAirAddress.soloDim,
            XAirAddress.soloDimAttenuation, XAirAddress.soloMono, XAirAddress.soloMute,
            XAirAddress.linkEQ, XAirAddress.linkDynamics, XAirAddress.linkFaderMute,
            XAirAddress.snapshotIndex, XAirAddress.tapeState, XAirAddress.tapeFile,
        ])
        for odd in stride(from: 1, through: state.model.channelCount - 1, by: 2) {
            addresses.append(XAirAddress.channelLink(odd))
        }
        for odd in stride(from: 1, through: max(1, state.model.busCount - 1), by: 2) {
            addresses.append(XAirAddress.busLink(odd))
        }

        enqueueSync(addresses)
    }

    /// Pulls the full parameter set for one strip. Called when its detail view
    /// opens, so we never query 1,500 addresses we aren't showing.
    func deepSync(_ id: StripID, force: Bool = false) {
        guard force || !deepSynced.contains(id) else { return }
        deepSynced.insert(id)

        var addresses: [String] = []

        if id.hasPreamp {
            for p in ["invert", "hpon", "hpf", "rtntrim", "rtnsw"] {
                addresses.append(id.preampAddress(p))
            }
        }
        if id.hasGate {
            for p in ["on", "mode", "thr", "range", "attack", "hold", "release", "keysrc",
                      "filter/on", "filter/type", "filter/f"] {
                addresses.append(id.gateAddress(p))
            }
        }
        if id.hasDynamics {
            for p in ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain",
                      "attack", "hold", "release", "mix", "keysrc", "auto",
                      "filter/on", "filter/type", "filter/f"] {
                addresses.append(id.dynAddress(p))
            }
        }
        if id.eqBandCount > 0 {
            addresses.append(id.eqOnAddress)
            addresses.append(id.eqModeAddress)
            for band in 1...id.eqBandCount {
                for p in ["type", "f", "g", "q"] {
                    addresses.append(id.eqAddress(band: band, p))
                }
            }
        }
        if id.hasGraphicEQ {
            for band in XAirGEQ.bands {
                addresses.append(id.graphicEQAddress(band.address))
            }
        }
        if id.hasInsert {
            addresses.append(id.insertOnAddress)
            addresses.append(id.insertSelAddress)
        }
        if id.hasAutomix {
            addresses.append(id.automixGroupAddress)
            addresses.append(id.automixWeightAddress)
        }
        addresses.append(id.inputSourceAddress)

        enqueueSync(addresses)
    }

    /// Pulls one FX slot's parameter block.
    func syncFXSlot(_ slot: Int) {
        var addresses = [XAirAddress.fxType(slot)]
        for parameter in 1...64 {
            addresses.append(XAirAddress.fxParameter(slot, parameter))
        }
        enqueueSync(addresses)
    }

    /// Pulls the 64 snapshot names.
    func syncSnapshots() {
        var addresses = [XAirAddress.snapshotIndex]
        for index in 1...64 { addresses.append(XAirAddress.snapshotName(index)) }
        enqueueSync(addresses)
    }

    /// Pulls the input-source assignment for every strip that has one.
    func syncRouting() {
        var addresses: [String] = []
        for id in state.stripOrder where id.hasPreamp {
            addresses.append(id.inputSourceAddress)
            addresses.append(id.usbReturnSourceAddress)
        }
        enqueueSync(addresses)
    }

    private func enqueueSync(_ addresses: [String]) {
        syncQueue.append(contentsOf: addresses)
        syncTotal = max(syncTotal, syncQueue.count)
        guard syncTimer == nil else { return }

        status = .syncing(progress: 0)
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drainSyncQueue() }
        }
    }

    private func drainSyncQueue() {
        // Hold the queue until the desk can actually answer.
        guard isSessionReady, let link else { return }
        guard !syncQueue.isEmpty else {
            syncTimer?.invalidate(); syncTimer = nil
            syncTotal = 0
            if status.isLive { status = .connected }
            return
        }

        let burst = syncQueue.prefix(syncBurstSize)
        syncQueue.removeFirst(burst.count)
        for address in burst {
            link.send(OSCMessage.query(address))
        }

        if syncTotal > 0 {
            let done = Double(syncTotal - syncQueue.count) / Double(syncTotal)
            status = .syncing(progress: min(1, max(0, done)))
        }
    }

    /// Re-reads one address. Used when a drag ends, so that a change made
    /// elsewhere during the drag can't leave us showing a stale value.
    func resync(_ address: String) {
        recentWrites[address] = nil
        guard let link else { return }
        link.send(OSCMessage.query(address))
    }

    /// Re-reads the whole surface. Used after a snapshot recall, which can
    /// change almost every parameter at once.
    func resyncEverything() {
        deepSynced.removeAll()
        startSurfaceSync()
    }

    /// Sends a message with more than one argument, bypassing the coalescing
    /// path (which only carries a single value per address).
    func rawMultiSend(_ message: OSCMessage) {
        send(message, immediate: true)
    }
}
