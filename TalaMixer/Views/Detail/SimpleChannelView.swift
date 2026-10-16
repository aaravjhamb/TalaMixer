//
//  SimpleChannelView.swift
//  TalaMixer
//
//  The simplified-mode channel sheet: input gain, a three-knob tone EQ, and
//  one-knob compressor and gate. Every knob drives the same desk parameters
//  as the full detail view — this is a smaller window, not a different engine.
//
//  The one-knob dynamics convention: the knob is "how much", not "threshold".
//  Turning the compressor up lowers its threshold; turning the gate up raises
//  its threshold. At zero the block switches off entirely, so a channel can't
//  be left ducking with nothing on the meter to explain why.
//

import SwiftUI

struct SimpleChannelView: View {
    @Environment(XAirClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    let stripID: StripID

    @State private var renamePrompt = false
    @State private var renameText = ""

    private var strip: StripState { client.state.strip(stripID) }

    /// Below this the one-knob blocks read as "off".
    private let offWindow = 0.02

    // Low / mid / high picked from whatever parametric bands the strip has.
    private var lowBand: EQBandState? { strip.eq.bands.first }
    private var midBand: EQBandState? {
        guard strip.eq.bands.count > 2 else { return nil }
        return strip.eq.bands[(strip.eq.bands.count - 1) / 2]
    }
    private var highBand: EQBandState? {
        strip.eq.bands.count > 1 ? strip.eq.bands.last : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    tonePanel
                    if stripID.hasGate || stripID.hasDynamics {
                        dynamicsPanel
                    }
                    if stripID.hasSends {
                        mixesPanel
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .presentationSizing(.form)
        .presentationBackground(Theme.background)
        .syncOnSession(client) { client.deepSync(stripID) }
        .alert("Rename \(strip.displayName)", isPresented: $renamePrompt) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { client.setName(stripID, trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes the name stored on the mixer.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(strip.color == .off ? Theme.surfaceRaised : strip.color.tint)
                .frame(width: 6, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(strip.displayName)
                    .themeTitle(21)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(stripID.tag)
                    .themeBody(11)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            RoundIconButton(icon: "pencil", label: "Rename", size: 32) {
                renameText = strip.name
                renamePrompt = true
            }

            OnButton(isOn: strip.on) {
                client.toggleMute(stripID)
            }
            .frame(width: 74)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    // MARK: Gain + EQ

    private var tonePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Sound")

            HStack(alignment: .top, spacing: 0) {
                if let index = stripID.headampIndex,
                   let headamp = client.state.headamps.first(where: { $0.index == index }) {
                    // Remapped onto the Scarlett-style range; desk values below
                    // its floor just park the knob at the bottom.
                    Knob(title: "Gain",
                         scale: P.simpleHeadampGain,
                         wire: P.simpleHeadampGain.wire(fromValue: headamp.gainDB),
                         format: { XAirFormat.gain($0) },
                         diameter: 72,
                         onChange: {
                             let db = P.simpleHeadampGain.value(fromWire: $0)
                             client.setHeadampGain(index, wire: P.headampGain.wire(fromValue: db))
                         },
                         onEnded: { client.endGesture(XAirAddress.headampGain(index)) })
                        .frame(maxWidth: .infinity)

                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 84)
                }

                if let band = lowBand { eqKnob("Low", band) }
                if let band = midBand { eqKnob("Mid", band) }
                if let band = highBand { eqKnob("High", band) }
            }
        }
        .panel()
    }

    private func eqKnob(_ title: String, _ band: EQBandState) -> some View {
        Knob(title: title,
             scale: P.eqGain,
             wire: band.gainWire,
             format: { XAirFormat.gain($0) },
             resetWire: P.eqGain.wire(fromValue: 0),
             diameter: 72,
             onChange: { wire in
                 if !strip.eq.on { client.setEQOn(stripID, true) }
                 client.setEQGain(stripID, band: band.band, wire: wire)
             },
             onEnded: { client.endGesture(stripID.eqAddress(band: band.band, "g")) })
            .frame(maxWidth: .infinity)
    }

    // MARK: One-knob dynamics

    private var dynamicsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Dynamics", subtitle: "turn to zero to switch off")

            HStack(alignment: .top, spacing: 0) {
                if stripID.hasDynamics {
                    Knob(title: "Compress",
                         scale: P.dynThreshold,
                         wire: 1 - strip.dynamics.thresholdWire,
                         tint: Theme.warning,
                         format: { _ in compAmountText },
                         resetWire: 0,
                         diameter: 72,
                         onChange: { amount in
                             client.setDynamicsParameter(stripID, .threshold, wire: 1 - amount)
                             setEngaged(amount, strip.dynamics.on, client.setDynamicsOn)
                         },
                         onEnded: { client.endGesture(stripID.dynAddress("thr")) })
                        .frame(maxWidth: .infinity)
                }

                if stripID.hasGate {
                    Knob(title: "Gate",
                         scale: P.gateThreshold,
                         wire: strip.gate.thresholdWire,
                         tint: Theme.meterLow,
                         format: { _ in gateAmountText },
                         resetWire: 0,
                         diameter: 72,
                         onChange: { amount in
                             client.setGateParameter(stripID, .threshold, wire: amount)
                             setEngaged(amount, strip.gate.on, client.setGateOn)
                         },
                         onEnded: { client.endGesture(stripID.gateAddress("thr")) })
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .panel()
    }

    // MARK: Mixes

    /// How much of this channel goes to each wedge, IEM and effect.
    private var mixesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Mixes", subtitle: "send levels to monitors and effects")

            ForEach(1...client.state.model.sendCount, id: \.self) { slot in
                let isFX = slot > client.state.model.busCount
                HStack(spacing: 12) {
                    Text(client.state.sendLabel(slot))
                        .font(Theme.label(12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 96, alignment: .leading)

                    ParameterSlider(
                        title: "",
                        scale: P.sendLevel,
                        wire: strip.sendWire(slot),
                        tint: isFX ? Theme.warning : Theme.gold,
                        format: { XAirFormat.decibelsWithUnit($0) },
                        resetWire: 0,
                        onChange: { client.setSendLevel(stripID, slot: slot, wire: $0) },
                        onEnded: { client.endGesture(stripID.sendLevelAddress(slot)) }
                    )
                    .accessibilityLabel("\(client.state.sendLabel(slot)) send")
                }
            }
        }
        .panel()
    }

    private var compAmountText: String {
        let amount = 1 - strip.dynamics.thresholdWire
        return strip.dynamics.on && amount > offWindow ? "\(Int(amount * 100))%" : "off"
    }

    private var gateAmountText: String {
        strip.gate.on && strip.gate.thresholdWire > offWindow
            ? "\(Int(strip.gate.thresholdWire * 100))%" : "off"
    }

    /// The zero detent: the block follows the knob in and out of existence.
    private func setEngaged(_ amount: Double, _ isOn: Bool,
                            _ set: (StripID, Bool) -> Void) {
        if amount > offWindow, !isOn { set(stripID, true) }
        if amount <= offWindow, isOn { set(stripID, false) }
    }
}
