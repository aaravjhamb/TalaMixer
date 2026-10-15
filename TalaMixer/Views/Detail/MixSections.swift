//
//  MixSections.swift
//  TalaMixer
//
//  Bus/FX sends, and the 31-band graphic EQ on buses and the main bus.
//

import SwiftUI

// MARK: - Sends

struct SendsSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    private var strip: StripState { client.state.strip(stripID) }
    private var model: XAirModel { client.state.model }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Mix sends", subtitle: "\(model.busCount) monitor mixes")

                ForEach(1...model.busCount, id: \.self) { slot in
                    sendRow(slot: slot, tint: Theme.accent)
                }
            }
            .panel()

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("FX sends", subtitle: "\(model.fxCount) engines")

                ForEach(1...model.fxCount, id: \.self) { fxIndex in
                    let slot = model.busCount + fxIndex
                    sendRow(slot: slot,
                            tint: Theme.solo,
                            trailing: client.state.fx.first { $0.slot == fxIndex }?.typeName)
                }
            }
            .panel()
        }
    }

    private func sendRow(slot: Int, tint: Color, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(client.state.sendLabel(slot))
                    .font(Theme.label(12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let trailing {
                    Text(trailing)
                        .font(Theme.label(9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 110, alignment: .leading)

            ParameterSlider(
                title: "",
                scale: P.sendLevel,
                wire: strip.sendWire(slot),
                tint: tint,
                format: { XAirFormat.decibelsWithUnit($0) },
                resetWire: 0,
                onChange: { client.setSendLevel(stripID, slot: slot, wire: $0) },
                onEnded: { client.endGesture(stripID.sendLevelAddress(slot)) }
            )

            HStack(spacing: 4) {
                quickButton("-∞", wire: 0, slot: slot)
                quickButton("0", wire: XAirScale.unityWire, slot: slot)
            }
        }
    }

    private func quickButton(_ title: String, wire: Double, slot: Int) -> some View {
        Button {
            Haptics.tap()
            client.setSendLevel(stripID, slot: slot, wire: wire)
        } label: {
            Text(title)
                .font(Theme.label(10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Graphic EQ

struct GraphicEQSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    @State private var touchedBand: Int?

    private var strip: StripState { client.state.strip(stripID) }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Graphic EQ", subtitle: "31 bands, ±15 dB") {
                    HStack(spacing: 8) {
                        if let touchedBand, XAirGEQ.bands.indices.contains(touchedBand) {
                            Text("\(XAirGEQ.bands[touchedBand].label) Hz  "
                                 + XAirFormat.gain(P.graphicEQGain.value(fromWire: strip.graphicEQWire(touchedBand))))
                                .font(Theme.value(12, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        Button {
                            Haptics.detent()
                            client.flattenGraphicEQ(stripID)
                        } label: {
                            Text("Flatten")
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
                }

                HStack(alignment: .top, spacing: 3) {
                    ForEach(XAirGEQ.bands.indices, id: \.self) { index in
                        VStack(spacing: 5) {
                            MiniVerticalSlider(
                                wire: strip.graphicEQWire(index),
                                tint: touchedBand == index ? Theme.solo : Theme.accent,
                                onChange: { value in
                                    touchedBand = index
                                    client.setGraphicEQ(stripID, bandIndex: index, wire: value)
                                },
                                onEnded: {
                                    client.endGesture(
                                        stripID.graphicEQAddress(XAirGEQ.bands[index].address)
                                    )
                                }
                            )
                            .frame(height: 190)

                            Text(XAirGEQ.bands[index].label)
                                .font(Theme.mono(7))
                                .foregroundStyle(index % 2 == 0 ? Theme.textSecondary : Theme.textTertiary)
                                .fixedSize()
                                .rotationEffect(.degrees(-90))
                                .frame(width: 12, height: 26)
                        }
                    }
                }
            }
            .panel()
        }
    }
}

/// A narrow vertical slider, filled outward from the centre. Used for graphic EQ
/// bands, where zero is the meaningful resting point.
struct MiniVerticalSlider: View {
    var wire: Double
    var tint: Color
    var onChange: (Double) -> Void
    var onEnded: () -> Void = {}

    @State private var dragOrigin: Double?

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let position = (1 - CGFloat(wire.clampedToUnit)) * height
            let centre = height / 2

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.surfaceSunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.4), lineWidth: 1)
                    )

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)
                    .offset(y: centre)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(0.8))
                    .frame(height: abs(position - centre))
                    .offset(y: min(position, centre))

                Capsule()
                    .fill(Color(white: 0.9))
                    .frame(height: 5)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(y: max(0, min(height - 5, position - 2.5)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let origin = dragOrigin ?? wire
                        if dragOrigin == nil { dragOrigin = origin }
                        let delta = -Double(value.translation.height) / Double(max(1, height))
                        onChange((origin + delta).clampedToUnit)
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onEnded()
                    }
            )
            .onTapGesture(count: 2) {
                Haptics.detent()
                onChange(0.5)
                onEnded()
            }
        }
        .frame(width: 14)
    }
}
