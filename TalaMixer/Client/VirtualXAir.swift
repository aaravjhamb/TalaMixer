//
//  VirtualXAir.swift
//  TalaMixer
//
//  An in-process stand-in for the desk. It speaks the same OSC dialect over the
//  same `OSCLink` interface, so demo mode exercises the real client code path —
//  subscriptions, queries, echoes and metering included.
//
//  Useful for laying hands on the UI without the XR18 plugged in, and for
//  checking behaviour before a show.
//

import Foundation

final class VirtualXAir: OSCLink {
    var onMessage: ((OSCMessage) -> Void)?
    var onState: ((OSCLinkState) -> Void)?

    private var store: [String: OSCValue] = [:]
    private let model = XAirModel.xr18

    private var meterTimer: Timer?
    private var metersSubscribed = false
    private var rtaSubscribed = false
    private var phase: Double = 0

    private let queue = DispatchQueue(label: "com.talamixer.virtual")

    // MARK: OSCLink

    func connect(host: String, port: UInt16) {
        seed()
        onState?(.connecting)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.onState?(.ready)
        }
    }

    func disconnect() {
        meterTimer?.invalidate()
        meterTimer = nil
        metersSubscribed = false
        onState?(.idle)
    }

    func send(_ message: OSCMessage) {
        // Mirror the real desk's small reply latency so the UI is exercised the
        // same way it will be on the night.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.006) { [weak self] in
            self?.handle(message)
        }
    }

    // MARK: Message handling

    private func handle(_ message: OSCMessage) {
        switch message.address {
        case XAirAddress.xinfo, XAirAddress.info:
            reply(OSCMessage(XAirAddress.xinfo, [
                .string("10.0.0.42"), .string("TalaMixer Demo"),
                .string("XR18"), .string("1.19"),
            ]))
            return

        case XAirAddress.status:
            reply(OSCMessage(XAirAddress.status, [
                .string("active"), .string("10.0.0.42"), .string("TalaMixer Demo"),
            ]))
            return

        case XAirAddress.xremote, XAirAddress.xremoteNoFeedback, XAirAddress.renew:
            return

        case XAirAddress.batchSubscribe:
            let args = message.values.compactMap { $0.stringValue }
            if args.contains(where: { $0.contains("/meters/4") }) {
                rtaSubscribed = true
            } else {
                startMeters()
            }
            return

        case "/meters", XAirAddress.meters(1):
            startMeters()
            return

        case XAirAddress.unsubscribe:
            meterTimer?.invalidate(); meterTimer = nil
            metersSubscribed = false; rtaSubscribed = false
            return

        case XAirAddress.snapshotLoad:
            if let index = message.values.first?.intValue {
                store[XAirAddress.snapshotIndex] = .int(Int32(index))
                reply(OSCMessage(XAirAddress.snapshotIndex, .int(Int32(index))))
            }
            return

        default:
            break
        }

        if message.values.isEmpty {
            // A bare address is a query.
            reply(OSCMessage(message.address, [value(for: message.address)]))
        } else {
            // A set: store it and echo it back, exactly as the desk does.
            store[message.address] = message.values[0]
            reply(message)
        }
    }

    private func reply(_ message: OSCMessage) {
        onMessage?(message)
    }

    private func value(for address: String) -> OSCValue {
        if let existing = store[address] { return existing }
        let fallback = Self.defaultValue(for: address)
        store[address] = fallback
        return fallback
    }

    // MARK: Metering

    private func startMeters() {
        guard !metersSubscribed else { return }
        metersSubscribed = true

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.emitMeters()
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    /// Fabricates a plausible-looking 40-slot frame so the meters move.
    private func emitMeters() {
        phase += 0.05
        var samples = [Int16](repeating: -8400, count: 40)

        for i in 0..<40 {
            // Each slot gets its own drift rate so the bank doesn't pulse in unison.
            let seed = Double(i) * 0.7
            let wave = sin(phase * (0.8 + Double(i % 5) * 0.35) + seed)
            let jitter = Double.random(in: -6...6)
            var db = -26 + wave * 16 + jitter

            // Leave a few strips quiet, as on a real desk.
            if i % 7 == 3 { db -= 45 }
            db = min(-0.5, max(-84, db))
            samples[i] = Int16(clamping: Int(db * 256))
        }

        var blob = Data()
        let count = UInt32(samples.count)
        blob.append(UInt8(count & 0xFF))
        blob.append(UInt8((count >> 8) & 0xFF))
        blob.append(UInt8((count >> 16) & 0xFF))
        blob.append(UInt8((count >> 24) & 0xFF))
        for sample in samples {
            let raw = UInt16(bitPattern: sample)
            blob.append(UInt8(raw & 0xFF))
            blob.append(UInt8(raw >> 8))
        }

        reply(OSCMessage(XAirAddress.meters(1), .blob(blob)))
        if rtaSubscribed { emitRTA() }
    }

    /// A pink-noise-ish spectrum with a moving low-mid bump, so the RTA looks
    /// like a band rather than a test tone.
    private func emitRTA() {
        var samples = [Int16](repeating: -8400, count: 100)
        for i in 0..<100 {
            let f = Double(i) / 99.0
            let tilt = -14.0 * f                                    // pink-ish rolloff
            let bump = 18.0 * exp(-pow((f - 0.25 - 0.06 * sin(phase * 0.5)) / 0.13, 2))
            let hiHat = 7.0 * exp(-pow((f - 0.8) / 0.09, 2)) * (0.5 + 0.5 * sin(phase * 3.1))
            let jitter = Double.random(in: -4...4)
            let db = min(-2.0, -46.0 + tilt + bump + hiHat + jitter)
            samples[i] = Int16(clamping: Int(db * 256))
        }
        var blob = Data()
        let count = UInt32(samples.count)
        blob.append(UInt8(count & 0xFF)); blob.append(UInt8((count >> 8) & 0xFF))
        blob.append(UInt8((count >> 16) & 0xFF)); blob.append(UInt8((count >> 24) & 0xFF))
        for sample in samples {
            let raw = UInt16(bitPattern: sample)
            blob.append(UInt8(raw & 0xFF)); blob.append(UInt8(raw >> 8))
        }
        reply(OSCMessage(XAirAddress.meters(4), .blob(blob)))
    }

    // MARK: Seeded show

    /// A believable starting point: a small band, buses set up as monitor
    /// sends, some processing already engaged.
    private func seed() {
        guard store.isEmpty else { return }

        let names = ["Kick", "Snare", "Hi Hat", "Rack Tom", "Floor Tom",
                     "OH L", "OH R", "Bass", "Gtr L", "Gtr R",
                     "Keys L", "Keys R", "Lead Vox", "Vox 2", "Vox 3", "Talkback"]
        let colors = [1, 1, 1, 1, 1, 3, 3, 5, 2, 2, 6, 6, 4, 4, 4, 7]
        let faders = [0.72, 0.70, 0.62, 0.64, 0.64, 0.68, 0.68, 0.74,
                      0.66, 0.66, 0.63, 0.63, 0.78, 0.60, 0.60, 0.0]

        for n in 1...model.channelCount {
            let id = StripID.channel(n)
            store[id.nameAddress] = .string(names[n - 1])
            store[id.colorAddress] = .int(Int32(colors[n - 1]))
            store[id.faderAddress] = .float(Float(faders[n - 1]))
            // Mics come up muted — the desk starts safe, as on a fresh show.
            store[id.onAddress] = .int(0)
            store[id.panAddress] = .float(0.5)
            store[id.mainAssignAddress] = .int(1)

            // Drums into DCA 1, guitars/keys into DCA 2, vocals into DCA 3.
            let dca: Int
            switch n {
            case 1...7: dca = 1
            case 8...12: dca = 2
            default: dca = 3
            }
            store[id.dcaAssignAddress] = .int(Int32(1 << (dca - 1)))
            store[id.muteGroupAssignAddress] = .int(n == 16 ? 1 : 0)

            store[id.gateAddress("on")] = .int(n <= 5 ? 1 : 0)
            store[id.dynAddress("on")] = .int(n <= 13 ? 1 : 0)
            store[id.eqOnAddress] = .int(1)
            store[id.preampAddress("hpon")] = .int(n == 1 ? 0 : 1)
            store[XAirAddress.headampPhantom(n)] = .int((6...7).contains(n) ? 1 : 0)
            store[XAirAddress.headampGain(n)] = .float(Float(P.headampGain.wire(fromValue: 24)))

            for slot in 1...model.sendCount {
                store[id.sendLevelAddress(slot)] = .float(slot <= 2 ? 0.55 : 0.0)
            }
        }

        let busNames = ["Wedge 1", "Wedge 2", "IEM Drums", "IEM Bass", "Side Fill", "Sub"]
        for n in 1...model.busCount {
            let id = StripID.bus(n)
            store[id.nameAddress] = .string(busNames[min(n - 1, busNames.count - 1)])
            store[id.colorAddress] = .int(Int32(4))
            store[id.faderAddress] = .float(0.75)
            store[id.onAddress] = .int(1)
        }

        for n in 1...model.fxCount {
            store[StripID.fxSend(n).nameAddress] = .string("FX \(n)")
            store[StripID.fxSend(n).faderAddress] = .float(0.75)
            store[StripID.fxSend(n).onAddress] = .int(1)
            store[StripID.fxReturn(n).nameAddress] = .string("FX \(n) Rtn")
            store[StripID.fxReturn(n).faderAddress] = .float(0.68)
            store[StripID.fxReturn(n).onAddress] = .int(1)
        }
        store[XAirAddress.fxType(1)] = .int(0)      // a hall
        store[XAirAddress.fxType(2)] = .int(10)     // a delay
        store[XAirAddress.fxType(3)] = .int(21)     // a chorus
        store[XAirAddress.fxType(4)] = .int(32)     // a graphic EQ

        let dcaNames = ["Drums", "Instruments", "Vocals", "Playback"]
        for n in 1...model.dcaCount {
            let id = StripID.dca(n)
            store[id.nameAddress] = .string(dcaNames[n - 1])
            store[id.colorAddress] = .int(Int32([1, 2, 4, 3][n - 1]))
            store[id.faderAddress] = .float(Float(XAirScale.unityWire))
            store[id.onAddress] = .int(1)
        }

        store[StripID.main.nameAddress] = .string("Main LR")
        store[StripID.main.faderAddress] = .float(Float(XAirScale.unityWire))
        store[StripID.main.onAddress] = .int(1)
        store[StripID.auxReturn.nameAddress] = .string("Playback")
        store[StripID.auxReturn.faderAddress] = .float(0.6)
        store[StripID.auxReturn.onAddress] = .int(1)

        for index in 1...64 {
            store[XAirAddress.snapshotName(index)] = .string(index <= 4
                ? ["Line Check", "Soundcheck", "Show", "Walk-in"][index - 1]
                : "")
        }
        store[XAirAddress.snapshotIndex] = .int(3)
        store[XAirAddress.tapeState] = .int(0)
        store[XAirAddress.tapeFile] = .string("SET_01.WAV")
    }

    /// Sensible resting values for anything the seed didn't cover.
    private static func defaultValue(for address: String) -> OSCValue {
        let parts = address.split(separator: "/").map(String.init)
        let last = parts.last ?? ""

        // EQ bands come up spread across the spectrum rather than stacked at 1 kHz.
        if parts.count >= 3, parts[parts.count - 3] == "eq", let band = Int(parts[parts.count - 2]) {
            switch last {
            case "f":
                let spread = [0.18, 0.42, 0.62, 0.82, 0.9, 0.95]
                return .float(Float(spread[min(band - 1, spread.count - 1)]))
            case "g": return .float(0.5)
            case "q": return .float(0.5)
            case "type": return .int(band == 1 ? 2 : 2)
            default: break
            }
        }

        switch last {
        case "name": return .string("")
        case "color": return .int(0)
        case "on": return .int(0)
        case "fader", "level": return .float(0)
        case "pan": return .float(0.5)
        case "lr": return .int(1)
        case "thr": return .float(0.6)
        case "ratio": return .int(3)
        case "mix": return .float(1)
        case "attack": return .float(0.1)
        case "hold", "release": return .float(0.5)
        case "hpf": return .float(Float(P.highPassFilter.wire(fromValue: 80)))
        case "f": return .float(0.5)
        case "g": return .float(0.5)
        case "gain": return .float(Float(P.headampGain.wire(fromValue: 20)))
        default:
            // GEQ bands are addressed by frequency label, e.g. /geq/3k15.
            if parts.count >= 2, parts[parts.count - 2] == "geq" { return .float(0.5) }
            if parts.count >= 2, parts[parts.count - 2] == "par" { return .float(0.4) }
            return .float(0)
        }
    }
}
