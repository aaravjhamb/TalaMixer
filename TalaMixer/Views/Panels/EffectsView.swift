//
//  EffectsView.swift
//  TalaMixer
//
//  The four FX slots: engine selection plus the generic parameter block.
//

import SwiftUI

struct EffectsView: View {
    @Environment(XAirClient.self) private var client

    @State private var slot = 1
    @State private var showsAllParameters = false

    private var fx: FXSlotState? {
        client.state.fx.first { $0.slot == slot }
    }

    /// Named parameters for the loaded engine, when the layout is known.
    private var parameterNames: [String]? {
        guard let fx else { return nil }
        return XAirFXCatalog.parameterNames(for: fx.typeIndex)
    }

    /// Most engines use well under 16 of the 64 parameter slots; showing them
    /// all by default would bury the useful ones.
    private var visibleParameterCount: Int {
        if showsAllParameters { return 64 }
        if let names = parameterNames { return names.count }
        return 16
    }

    private func parameterTitle(_ parameter: Int) -> String {
        if let names = parameterNames, parameter <= names.count {
            return names[parameter - 1]
        }
        return "Par \(parameter)"
    }

    var body: some View {
        PageScaffold("Effects", subtitle: "\(client.state.model.fxCount) stereo engines") {
            VStack(spacing: 16) {
                slotSelector

                if let fx {
                    enginePanel(fx)
                    parameterPanel(fx)
                    routingHint
                }
            }
        }
        .syncOnSession(client) { client.syncFXSlot(slot) }
        .onChange(of: slot) { _, newValue in client.syncFXSlot(newValue) }
    }

    // MARK: Slot selector

    private var slotSelector: some View {
        HStack(spacing: 6) {
            ForEach(1...client.state.model.fxCount, id: \.self) { index in
                let engine = client.state.fx.first { $0.slot == index }
                let isSelected = slot == index
                Button {
                    Haptics.tap()
                    slot = index
                } label: {
                    VStack(spacing: 2) {
                        Text("FX \(index)")
                            .font(Theme.label(13, weight: .bold))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.textPrimary)
                        Text(engine?.typeName ?? "—")
                            .font(Theme.label(9, weight: .medium))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.6) : Theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Theme.solo : Theme.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Theme.solo : Theme.stroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Engine

    private func enginePanel(_ fx: FXSlotState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Engine") {
                Badge(text: "type \(fx.typeIndex)", tint: Theme.solo)
            }

            Menu {
                ForEach(0..<XAirFXCatalog.count, id: \.self) { index in
                    Button {
                        client.setFXType(fx.slot, index: index)
                    } label: {
                        HStack {
                            Text("\(index)  ·  \(XAirFXCatalog.name(for: index))")
                            if fx.typeIndex == index { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(fx.typeName)
                        .font(Theme.label(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .well(Theme.Metric.cornerSmall)
            }
        }
        .panel()
    }

    // MARK: Parameters

    private func parameterPanel(_ fx: FXSlotState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Parameters",
                          subtitle: showsAllParameters ? "all 64 raw slots"
                            : (parameterNames != nil ? "named for this engine" : "first 16 slots")) {
                Button {
                    showsAllParameters.toggle()
                } label: {
                    Text(showsAllParameters ? "Named view" : "Raw 64")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 2),
                      spacing: 12) {
                ForEach(1...visibleParameterCount, id: \.self) { parameter in
                    let index = parameter - 1
                    let wire = fx.parameters.indices.contains(index) ? fx.parameters[index] : 0
                    ParameterSlider(
                        title: showsAllParameters ? "Par \(parameter)" : parameterTitle(parameter),
                        scale: .linear(0, 100),
                        wire: wire,
                        tint: Theme.solo,
                        format: { XAirFormat.percent($0) },
                        onChange: { client.setFXParameter(fx.slot, parameter: parameter, wire: $0) },
                        onEnded: { client.endGesture(XAirAddress.fxParameter(fx.slot, parameter)) }
                    )
                }
            }
        }
        .panel()
    }

    private var routingHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Getting signal in and out")
            Text("Feed this engine from each channel's Sends page (FX \(slot)), and bring it back on the FX \(slot) Rtn strip in the fader bank. The FX \(slot) send master is in the bank too.")
                .font(Theme.label(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .panel()
    }
}
