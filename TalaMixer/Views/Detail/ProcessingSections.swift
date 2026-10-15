//
//  ProcessingSections.swift
//  TalaMixer
//
//  Preamp, gate and compressor pages.
//

import SwiftUI

// MARK: - Preamp

struct PreampSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    private var strip: StripState { client.state.strip(stripID) }

    private var headamp: HeadampState? {
        guard let index = stripID.headampIndex else { return nil }
        return client.state.headamps.first { $0.index == index }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let headamp {
                analogPanel(headamp)
            }
            filterPanel
            usbPanel
        }
    }

    // MARK: Analogue input

    private func analogPanel(_ headamp: HeadampState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Analogue input", subtitle: "Mic in \(headamp.index)")

            HStack(alignment: .top, spacing: 22) {
                Knob(title: "Gain",
                     scale: P.headampGain,
                     wire: headamp.gainWire,
                     tint: Theme.accent,
                     format: { XAirFormat.gain($0) },
                     diameter: 76,
                     onChange: { client.setHeadampGain(headamp.index, wire: $0) },
                     onEnded: { client.endGesture(XAirAddress.headampGain(headamp.index)) })

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ToggleChip(title: "48V", isOn: headamp.phantom, tint: Theme.mute, width: 62) {
                            client.setPhantom(headamp.index, !headamp.phantom)
                        }
                        ToggleChip(title: "Ø POL", isOn: strip.preamp.invert, tint: Theme.warning, width: 74) {
                            client.setPhaseInvert(stripID, !strip.preamp.invert)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(headamp.phantom
                         ? "Phantom power is on. Mute before repatching."
                         : "Phantom power off")
                        .font(Theme.label(10, weight: .medium))
                        .foregroundStyle(headamp.phantom ? Theme.warning : Theme.textTertiary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INPUT LEVEL")
                            .font(Theme.label(9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { _ in
                            let index = XAirMeterLayout.index(in: .all, for: stripID,
                                                              model: client.state.model)
                            HorizontalMeter(db: client.state.meters.level(at: index), height: 7)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .panel()
    }

    // MARK: High-pass

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Low cut") {
                ToggleChip(title: strip.preamp.highPassOn ? "ON" : "OFF",
                           isOn: strip.preamp.highPassOn,
                           tint: Theme.active,
                           width: 62) {
                    client.setHighPassOn(stripID, !strip.preamp.highPassOn)
                }
            }

            HStack(spacing: 22) {
                Knob(title: "Frequency",
                     scale: P.highPassFilter,
                     wire: strip.preamp.highPassWire,
                     tint: Theme.accent,
                     format: { XAirFormat.frequencyWithUnit($0) },
                     onChange: { client.setHighPass(stripID, wire: $0) },
                     onEnded: { client.endGesture(stripID.preampAddress("hpf")) })
                    .opacity(strip.preamp.highPassOn ? 1 : 0.4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick set")
                        .font(Theme.label(10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 6) {
                        ForEach([40.0, 60.0, 80.0, 100.0, 150.0], id: \.self) { hz in
                            Button {
                                Haptics.tap()
                                client.setHighPass(stripID, wire: P.highPassFilter.wire(fromValue: hz))
                            } label: {
                                Text("\(Int(hz))")
                                    .font(Theme.label(11, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 42, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Theme.surfaceRaised)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .panel()
    }

    // MARK: USB / card return

    private var usbPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("USB return") {
                ToggleChip(title: strip.preamp.usbInput ? "USB SOURCE" : "ANALOGUE",
                           isOn: strip.preamp.usbInput,
                           tint: Theme.warning,
                           width: 130) {
                    client.setUSBInput(stripID, !strip.preamp.usbInput)
                }
            }

            ParameterSlider(
                title: "USB trim",
                scale: P.usbTrim,
                wire: strip.preamp.usbTrimWire,
                format: { XAirFormat.gain($0) },
                resetWire: P.usbTrim.wire(fromValue: 0),
                bipolar: true,
                onChange: { client.setUSBTrim(stripID, wire: $0) },
                onEnded: { client.endGesture(stripID.preampAddress("rtntrim")) }
            )

            Text("With USB selected, this strip plays back from the recorder instead of its physical input, for virtual soundcheck.")
                .font(Theme.label(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .panel()
    }
}

// MARK: - Gate

struct GateSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    private var gate: GateState { client.state.strip(stripID).gate }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Gate / expander") {
                    ToggleChip(title: gate.on ? "ON" : "OFF", isOn: gate.on,
                               tint: Theme.active, width: 62) {
                        client.setGateOn(stripID, !gate.on)
                    }
                }

                SegmentedControl(
                    options: XAirGateMode.allCases.map { .init(value: $0, label: $0.displayName) },
                    selection: gate.mode
                ) { client.setGateMode(stripID, $0) }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(GateParameter.allCases) { parameter in
                        Knob(title: parameter.title,
                             scale: parameter.scale,
                             wire: parameter.wire(from: gate),
                             tint: Theme.active,
                             format: { parameter.format($0) },
                             onChange: { client.setGateParameter(stripID, parameter, wire: $0) },
                             onEnded: { client.endGesture(stripID.gateAddress(parameter.oscName)) })
                    }
                }
                .opacity(gate.on ? 1 : 0.5)
            }
            .panel()

            SidechainPanel(
                title: "Gate sidechain",
                filter: gate.filter,
                tint: Theme.active,
                onToggle: { client.setGateFilterOn(stripID, $0) },
                onType: { client.setGateFilterType(stripID, $0) },
                onFrequency: { client.setGateFilterFrequency(stripID, wire: $0) },
                onFrequencyEnd: { client.endGesture(stripID.gateAddress("filter/f")) }
            )

            KeySourcePanel(
                title: "Gate key source",
                source: gate.keySource,
                onChange: { client.setGateKeySource(stripID, $0) }
            )
        }
    }
}

// MARK: - Dynamics

struct DynamicsSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    private var dyn: DynamicsState { client.state.strip(stripID).dynamics }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Compressor") {
                    ToggleChip(title: dyn.on ? "ON" : "OFF", isOn: dyn.on,
                               tint: Theme.warning, width: 62) {
                        client.setDynamicsOn(stripID, !dyn.on)
                    }
                }

                HStack(spacing: 8) {
                    SegmentedControl(
                        options: XAirDynMode.allCases.map { .init(value: $0, label: $0.displayName) },
                        selection: dyn.mode, tint: Theme.warning
                    ) { client.setDynamicsMode(stripID, $0) }

                    SegmentedControl(
                        options: XAirDynDetection.allCases.map { .init(value: $0, label: $0.displayName) },
                        selection: dyn.detection, tint: Theme.warning
                    ) { client.setDynamicsDetection(stripID, $0) }

                    SegmentedControl(
                        options: XAirDynEnvelope.allCases.map { .init(value: $0, label: $0.displayName) },
                        selection: dyn.envelope, tint: Theme.warning
                    ) { client.setDynamicsEnvelope(stripID, $0) }

                    ToggleChip(title: "AUTO", isOn: dyn.autoTime, tint: Theme.accent, width: 70) {
                        client.setDynamicsAutoTime(stripID, !dyn.autoTime)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("RATIO")
                        .font(Theme.label(9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    ChipGrid(columns: 6) {
                        ForEach(XAirDynRatio.values.indices, id: \.self) { index in
                            ToggleChip(title: XAirDynRatio.label(at: index),
                                       isOn: dyn.ratioIndex == index,
                                       tint: Theme.warning,
                                       expands: true) {
                                client.setDynamicsRatio(stripID, index: index)
                            }
                        }
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                    ForEach(DynamicsParameter.allCases) { parameter in
                        // Auto mode drives the timing constants itself.
                        let isTiming = [.attack, .hold, .release].contains(parameter)
                        Knob(title: parameter.title,
                             scale: parameter.scale,
                             wire: parameter.wire(from: dyn),
                             tint: Theme.warning,
                             format: { parameter.format($0) },
                             onChange: { client.setDynamicsParameter(stripID, parameter, wire: $0) },
                             onEnded: { client.endGesture(stripID.dynAddress(parameter.oscName)) })
                            .opacity(isTiming && dyn.autoTime ? 0.4 : 1)
                            .allowsHitTesting(!(isTiming && dyn.autoTime))
                    }
                }
                .opacity(dyn.on ? 1 : 0.5)
            }
            .panel()

            SidechainPanel(
                title: "Compressor sidechain",
                filter: dyn.filter,
                tint: Theme.warning,
                onToggle: { client.setDynamicsFilterOn(stripID, $0) },
                onType: { client.setDynamicsFilterType(stripID, $0) },
                onFrequency: { client.setDynamicsFilterFrequency(stripID, wire: $0) },
                onFrequencyEnd: { client.endGesture(stripID.dynAddress("filter/f")) }
            )

            KeySourcePanel(
                title: "Compressor key source",
                source: dyn.keySource,
                onChange: { client.setDynamicsKeySource(stripID, $0) }
            )
        }
    }
}

// MARK: - Shared sub-panels

private struct SidechainPanel: View {
    let title: String
    let filter: SidechainFilterState
    let tint: Color
    let onToggle: (Bool) -> Void
    let onType: (XAirFilterType) -> Void
    let onFrequency: (Double) -> Void
    let onFrequencyEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title) {
                ToggleChip(title: filter.on ? "ON" : "OFF", isOn: filter.on, tint: tint, width: 62) {
                    onToggle(!filter.on)
                }
            }

            SegmentedControl(
                options: XAirFilterType.allCases.map { .init(value: $0, label: $0.displayName) },
                selection: filter.type,
                tint: tint
            ) { onType($0) }

            ParameterSlider(
                title: "Filter frequency",
                scale: P.sidechainFrequency,
                wire: filter.frequencyWire,
                tint: tint,
                format: { XAirFormat.frequencyWithUnit($0) },
                onChange: onFrequency,
                onEnded: onFrequencyEnd
            )
        }
        .panel()
        .opacity(filter.on ? 1 : 0.7)
    }
}

/// Key source is a raw index into the desk's internal source list, whose
/// ordering isn't published — so it's shown as a number with the channels
/// labelled where the mapping is obvious (0 = self, 1…16 = channels).
private struct KeySourcePanel: View {
    @Environment(XAirClient.self) private var client
    let title: String
    let source: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, subtitle: label)

            HStack(spacing: 10) {
                Stepper(value: Binding(get: { source }, set: onChange), in: 0...40) {
                    EmptyView()
                }
                .labelsHidden()

                Text("Index \(source)")
                    .font(Theme.value(13))
                    .foregroundStyle(Theme.textPrimary)

                Button {
                    onChange(0)
                } label: {
                    Text("Self")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .panel()
    }

    private var label: String {
        if source == 0 { return "Self" }
        if source <= client.state.model.channelCount {
            return client.state.strip(.channel(source)).displayName
        }
        return "External source"
    }
}
