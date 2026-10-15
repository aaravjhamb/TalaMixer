//
//  XAirTopology.swift
//  TalaMixer
//
//  Which strips an XR18 has, what each one supports, and the OSC address that
//  every parameter lives at.
//
//  Address conventions on the X-Air (they are NOT uniform, which is a common
//  source of bugs):
//    • channels are zero-padded two digits   /ch/01 … /ch/16
//    • buses, FX sends, FX returns and DCAs are single digit   /bus/1, /dca/4
//    • the aux return has no index at all    /rtn/aux
//    • bus sends are zero-padded two digits  /ch/01/mix/07/level
//    • headamps are zero-padded two digits   /headamp/01
//

import Foundation

// MARK: - Mixer model

/// The X-Air family member we're talking to. The XR18 is the target, but the
/// counts are all data-driven so the smaller desks work too.
struct XAirModel: Equatable {
    var id: String
    var channelCount: Int
    var busCount: Int
    var fxCount: Int
    var dcaCount: Int
    var muteGroupCount: Int = 4

    static let xr18 = XAirModel(id: "XR18", channelCount: 16, busCount: 6, fxCount: 4, dcaCount: 4)
    static let xr16 = XAirModel(id: "XR16", channelCount: 16, busCount: 4, fxCount: 4, dcaCount: 4)
    static let xr12 = XAirModel(id: "XR12", channelCount: 12, busCount: 2, fxCount: 4, dcaCount: 4)
    static let mr18 = XAirModel(id: "MR18", channelCount: 16, busCount: 6, fxCount: 4, dcaCount: 4)

    /// Total bus sends per input strip: the aux buses followed by the FX sends.
    var sendCount: Int { busCount + fxCount }

    static func named(_ raw: String) -> XAirModel {
        switch raw.uppercased() {
        case let s where s.contains("XR12"): return .xr12
        case let s where s.contains("XR16"): return .xr16
        case let s where s.contains("MR18"): return .mr18
        default: return .xr18
        }
    }
}

// MARK: - Strip identity

/// Identifies one mixer strip. This is the key the whole app indexes state by.
enum StripID: Hashable, Identifiable, Sendable {
    case channel(Int)       // 1...16
    case auxReturn          // the stereo aux/USB return (inputs 17-18)
    case fxReturn(Int)      // 1...4
    case bus(Int)           // 1...6
    case fxSend(Int)        // 1...4
    case main               // the LR bus
    case dca(Int)           // 1...4

    var id: String { address }

    /// The OSC root for this strip.
    var address: String {
        switch self {
        case .channel(let n): return String(format: "/ch/%02d", n)
        case .auxReturn: return "/rtn/aux"
        case .fxReturn(let n): return "/rtn/\(n)"
        case .bus(let n): return "/bus/\(n)"
        case .fxSend(let n): return "/fxsend/\(n)"
        case .main: return "/lr"
        case .dca(let n): return "/dca/\(n)"
        }
    }

    // MARK: Presentation

    /// The short tag drawn above the fader, e.g. "01", "BUS 3", "LR".
    var tag: String {
        switch self {
        case .channel(let n): return String(format: "%02d", n)
        case .auxReturn: return "AUX"
        case .fxReturn(let n): return "FX\(n)"
        case .bus(let n): return "MIX \(n)"
        case .fxSend(let n): return "FX \(n)"
        case .main: return "LR"
        case .dca(let n): return "DCA \(n)"
        }
    }

    /// The name shown when the desk hasn't been given a custom one.
    var defaultName: String {
        switch self {
        case .channel(let n): return "Ch \(n)"
        case .auxReturn: return "Aux In"
        case .fxReturn(let n): return "FX \(n) Rtn"
        case .bus(let n): return "Mix \(n)"
        case .fxSend(let n): return "FX \(n) Send"
        case .main: return "Main LR"
        case .dca(let n): return "DCA \(n)"
        }
    }

    /// Which section of the mixer this belongs to, for grouping in the UI.
    enum Family: String, CaseIterable, Identifiable {
        case inputs = "Inputs"
        case returns = "Returns"
        case buses = "Mixes"
        case fxSends = "FX Sends"
        case dcas = "DCAs"
        case main = "Main"
        var id: String { rawValue }
    }

    var family: Family {
        switch self {
        case .channel: return .inputs
        case .auxReturn, .fxReturn: return .returns
        case .bus: return .buses
        case .fxSend: return .fxSends
        case .dca: return .dcas
        case .main: return .main
        }
    }

    // MARK: Capabilities

    /// Inputs carry a preamp block; buses and DCAs don't.
    var hasPreamp: Bool {
        switch self {
        case .channel, .auxReturn, .fxReturn: return true
        default: return false
        }
    }

    /// Only real input channels have a gate and a full compressor.
    var hasGate: Bool {
        if case .channel = self { return true }
        return false
    }

    var hasDynamics: Bool {
        switch self {
        case .channel, .bus, .main: return true
        default: return false
        }
    }

    var hasInsert: Bool {
        switch self {
        case .channel, .bus, .main: return true
        default: return false
        }
    }

    /// Inputs get a 4-band PEQ; buses and the main bus get 6 bands.
    var eqBandCount: Int {
        switch self {
        case .channel, .auxReturn, .fxReturn: return 4
        case .bus, .main: return 6
        default: return 0
        }
    }

    /// Buses and LR add a 31-band graphic EQ alongside the parametric one.
    var hasGraphicEQ: Bool {
        switch self {
        case .bus, .main: return true
        default: return false
        }
    }

    /// Strips that can send to the aux buses and FX engines.
    var hasSends: Bool {
        switch self {
        case .channel, .auxReturn, .fxReturn: return true
        default: return false
        }
    }

    /// Strips that can be assigned to DCAs and mute groups.
    var hasGroupAssign: Bool {
        switch self {
        case .channel, .auxReturn, .fxReturn, .bus, .fxSend: return true
        default: return false
        }
    }

    /// Only mono input channels take part in the automixer.
    var hasAutomix: Bool {
        if case .channel = self { return true }
        return false
    }

    /// Whether the strip can be panned into LR.
    var hasPan: Bool {
        switch self {
        case .channel, .auxReturn, .fxReturn, .bus: return true
        default: return false
        }
    }

    /// Whether the strip has an LR assign switch.
    var hasMainAssign: Bool {
        switch self {
        case .channel, .auxReturn, .fxReturn, .bus: return true
        default: return false
        }
    }

    /// The physical preamp behind this strip, if any. XR18 inputs 1-16 map
    /// straight onto `/headamp/01`…`/headamp/16`.
    var headampIndex: Int? {
        if case .channel(let n) = self { return n }
        return nil
    }

    /// DCAs use a flat `/dca/N/fader`; everything else nests under `/mix`.
    var isDCA: Bool {
        if case .dca = self { return true }
        return false
    }

    // MARK: Parameter addresses

    var nameAddress: String { "\(address)/config/name" }
    var colorAddress: String { "\(address)/config/color" }
    var inputSourceAddress: String { "\(address)/config/insrc" }
    var usbReturnSourceAddress: String { "\(address)/config/rtnsrc" }

    /// `on` is *unmuted* on this desk: 1 = passing audio, 0 = muted.
    var onAddress: String { isDCA ? "\(address)/on" : "\(address)/mix/on" }
    var faderAddress: String { isDCA ? "\(address)/fader" : "\(address)/mix/fader" }
    var panAddress: String { "\(address)/mix/pan" }
    var mainAssignAddress: String { "\(address)/mix/lr" }

    var dcaAssignAddress: String { "\(address)/grp/dca" }
    var muteGroupAssignAddress: String { "\(address)/grp/mute" }

    var automixGroupAddress: String { "\(address)/automix/group" }
    var automixWeightAddress: String { "\(address)/automix/weight" }

    var insertOnAddress: String { "\(address)/insert/on" }
    var insertSelAddress: String { "\(address)/insert/sel" }

    /// Send `index` is 1-based: 1…busCount are the aux buses, the rest are FX sends.
    func sendLevelAddress(_ index: Int) -> String {
        String(format: "%@/mix/%02d/level", address, index)
    }

    func eqAddress(band: Int, _ parameter: String) -> String {
        "\(address)/eq/\(band)/\(parameter)"
    }

    var eqOnAddress: String { "\(address)/eq/on" }
    var eqModeAddress: String { "\(address)/eq/mode" }

    func graphicEQAddress(_ bandAddress: String) -> String {
        "\(address)/geq/\(bandAddress)"
    }

    func preampAddress(_ parameter: String) -> String { "\(address)/preamp/\(parameter)" }
    func gateAddress(_ parameter: String) -> String { "\(address)/gate/\(parameter)" }
    func dynAddress(_ parameter: String) -> String { "\(address)/dyn/\(parameter)" }
}

// MARK: - Global addresses

enum XAirAddress {
    // Session / transport
    static let info = "/info"
    static let xinfo = "/xinfo"
    static let status = "/status"
    static let xremote = "/xremote"
    /// Subscribe without feedback: the desk won't echo our own changes back.
    static let xremoteNoFeedback = "/xremotenfb"
    static let batchSubscribe = "/batchsubscribe"
    static let unsubscribe = "/unsubscribe"
    static let renew = "/renew"

    // Mute groups: /config/mute/1 … /config/mute/4
    static func muteGroup(_ index: Int) -> String { "/config/mute/\(index)" }

    // Automix master
    static let automixEnable = "/config/amixenable"
    static let automixLock = "/config/amixlock"

    // Solo / monitor bus
    static let soloLevel = "/config/solo/level"
    static let soloSource = "/config/solo/source"
    static let soloSourceTrim = "/config/solo/sourcetrim"
    static let soloDim = "/config/solo/dim"
    static let soloDimAttenuation = "/config/solo/dimatt"
    static let soloMono = "/config/solo/mono"
    static let soloMute = "/config/solo/mute"
    static let soloDimFPL = "/config/solo/dimfpl"
    static let soloChannelMode = "/config/solo/chmode"
    static let soloBusMode = "/config/solo/busmode"

    // Channel / bus stereo linking, and what a link couples
    static func channelLink(_ oddIndex: Int) -> String { "/config/chlink/\(oddIndex)-\(oddIndex + 1)" }
    static func busLink(_ oddIndex: Int) -> String { "/config/buslink/\(oddIndex)-\(oddIndex + 1)" }
    static let linkEQ = "/config/linkcfg/eq"
    static let linkDynamics = "/config/linkcfg/dyn"
    static let linkFaderMute = "/config/linkcfg/fdrmute"

    // Preamps
    static func headampGain(_ index: Int) -> String { String(format: "/headamp/%02d/gain", index) }
    static func headampPhantom(_ index: Int) -> String { String(format: "/headamp/%02d/phantom", index) }

    // Effects
    static func fxType(_ slot: Int) -> String { "/fx/\(slot)/type" }
    static func fxParameter(_ slot: Int, _ parameter: Int) -> String {
        String(format: "/fx/%d/par/%02d", slot, parameter)
    }

    // Metering
    static func meters(_ id: Int) -> String { "/meters/\(id)" }

    // MARK: Paths awaiting hardware confirmation
    //
    // These follow the X32 convention, which the X-Air is understood to share,
    // but could not be confirmed against a primary X-Air source. Everything
    // above this line is verified. Use the in-app OSC Inspector to check them
    // against your desk; if one is wrong, only this section needs editing.

    /// Per-strip solo switch. `index` is a flat 1-based position across the desk
    /// — see `soloIndex(for:)`.
    static func soloSwitch(_ index: Int) -> String { String(format: "/-stat/solosw/%02d", index) }
    static let clearSolo = "/-stat/clearsolo"

    /// Flat solo-bus ordering. **Unverified** — in particular the aux return may
    /// occupy two slots rather than one, which would shift every entry after it.
    ///
    /// Written as running offsets so the ordering is readable and stays correct
    /// if one section's size turns out to be wrong.
    static func soloIndex(for strip: StripID, model: XAirModel) -> Int? {
        let channels = model.channelCount            // 1 … 16
        let auxReturn = channels + 1                 // 17
        let fxReturns = auxReturn + 1                // 18 …
        let buses = fxReturns + model.fxCount        // 22 …
        let fxSends = buses + model.busCount         // 28 …
        let main = fxSends + model.fxCount           // 32

        switch strip {
        case .channel(let n): return n
        case .auxReturn: return auxReturn
        case .fxReturn(let n): return fxReturns + (n - 1)
        case .bus(let n): return buses + (n - 1)
        case .fxSend(let n): return fxSends + (n - 1)
        case .main: return main
        case .dca: return nil          // DCAs have no solo bus
        }
    }

    // Snapshots (the desk stores 64)
    static let snapshotLoad = "/-snap/load"
    static let snapshotSave = "/-snap/save"
    static let snapshotIndex = "/-snap/index"
    static func snapshotName(_ index: Int) -> String { String(format: "/-snap/%02d/name", index) }

    // USB recorder / player
    static let tapeState = "/-stat/tape/state"
    static let tapeFile = "/-stat/tape/file"
    static let tapePosition = "/-stat/tape/etime"
    static let tapeRemaining = "/-stat/tape/rtime"
}
