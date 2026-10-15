//
//  FaderStripView.swift
//  TalaMixer
//
//  One channel strip in the fader bank. ON and SOLO sit at the top, under the
//  name tile, with the fader taking the remaining height.
//

import SwiftUI

/// Fixed heights for every section of a strip except the fader itself.
///
/// Pinning these does two things: it keeps faders aligned across the whole bank
/// regardless of what a given strip shows, and it lets the shared dB scale be
/// positioned from arithmetic rather than from guesswork.
enum StripLayout {
    static let padding: CGFloat = 7
    static let spacing: CGFloat = 7
    static let headerHeight: CGFloat = 46
    static let readoutHeight: CGFloat = 30
    /// ON + SOLO plus the gap between them.
    static let buttonsHeight: CGFloat = 64
    static let badgesHeight: CGFloat = 14

    /// Distance from the top of a strip to the top of its fader travel.
    static var faderTopInset: CGFloat {
        padding + headerHeight + spacing + buttonsHeight + spacing
    }

    /// Distance from the bottom of a strip to the bottom of its fader travel.
    static var faderBottomInset: CGFloat {
        padding + badgesHeight + spacing + readoutHeight + spacing
    }
}

/// What the bank's faders are currently driving.
enum BankMode: Equatable {
    /// Each strip's own main fader.
    case main
    /// Sends on fader: each input strip's send to the given 1-based slot.
    case sends(Int)

    var sendSlot: Int? {
        if case .sends(let slot) = self { return slot }
        return nil
    }
}

struct FaderStripView: View {
    @Environment(XAirClient.self) private var client

    let strip: StripState
    let mode: BankMode
    var isSelected: Bool
    /// Simplified mode: no solo, no processing dots, wider strips for easier
    /// grabbing. Tapping the header opens the simple channel sheet.
    var isSimplified: Bool = false
    var onOpenDetail: () -> Void

    private var id: StripID { strip.id }

    /// In sends-on-fader mode the fader drives the send, not the strip level.
    private var isSendMode: Bool { mode.sendSlot != nil }

    private var faderWire: Double {
        if let slot = mode.sendSlot { return strip.sendWire(slot) }
        return strip.faderWire
    }

    private var faderDB: Double {
        P.fader.value(fromWire: faderWire)
    }

    private var address: String {
        if let slot = mode.sendSlot { return id.sendLevelAddress(slot) }
        return id.faderAddress
    }

    private var tint: Color {
        strip.color == .off ? Theme.gold : strip.color.tint
    }

    private var meterIndex: Int? {
        XAirMeterLayout.index(in: .all, for: id, model: client.state.model)
    }

    private var meterRightIndex: Int? {
        XAirMeterLayout.rightIndex(in: .all, for: id, model: client.state.model)
    }

    /// Muted by a mute group that's currently engaged.
    private var mutedByGroup: Bool {
        guard id.hasGroupAssign else { return false }
        for group in 1...client.state.model.muteGroupCount {
            if strip.muteGroupMask.hasGroupBit(group),
               client.state.muteGroups.indices.contains(group - 1),
               client.state.muteGroups[group - 1] {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(spacing: StripLayout.spacing) {
            header
                .frame(height: StripLayout.headerHeight)

            buttons
                .frame(height: StripLayout.buttonsHeight)

            HStack(spacing: 5) {
                LiveMeter(store: client.state.meters,
                          index: meterIndex,
                          rightIndex: meterRightIndex,
                          width: meterRightIndex == nil ? 7 : 5)
                    .padding(.vertical, FaderGeometry.capHeight / 2)

                VerticalFader(
                    wire: faderWire,
                    tint: isSendMode ? Theme.warning : tint,
                    isMuted: strip.isMuted || mutedByGroup,
                    accessibilityLabel: isSendMode
                        ? "\(strip.displayName) send level"
                        : "\(strip.displayName) fader",
                    onChange: { value in
                        if let slot = mode.sendSlot {
                            client.setSendLevel(id, slot: slot, wire: value)
                        } else {
                            client.setFader(id, wire: value)
                        }
                    },
                    onEnded: { client.endGesture(address) }
                )
            }
            .frame(maxHeight: .infinity)

            readout
                .frame(height: StripLayout.readoutHeight)
            badges
        }
        .padding(StripLayout.padding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Theme.surfaceRaised : Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Theme.gold.opacity(0.7) : Theme.stroke,
                                lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .frame(width: isSimplified ? 124 : Theme.Metric.stripWidth)
        .opacity(strip.isSynced || !client.status.isLive ? 1 : 0.55)
    }

    // MARK: Header

    private var header: some View {
        let filled = strip.color.isInverted

        return Button(action: onOpenDetail) {
            HStack(spacing: 7) {
                // The strip colour as a slim accent bar — quieter than a wash,
                // still instantly scannable across the bank.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(strip.color == .off ? Theme.textTertiary.opacity(0.5) : tint)
                    .frame(width: 4)
                    .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(id.tag)
                            .font(Theme.mono(9, weight: .semibold))
                            .foregroundStyle(filled ? Color.black.opacity(0.6) : Theme.textTertiary)
                        Spacer(minLength: 0)
                        if !isSimplified { processingDots }
                    }
                    Text(strip.displayName)
                        .font(Theme.label(13, weight: .bold))
                        .foregroundStyle(filled ? Color.black.opacity(0.88) : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? tint : Theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(filled ? tint : Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Small dots showing which processing blocks are engaged.
    private var processingDots: some View {
        HStack(spacing: 2) {
            if strip.preamp.highPassOn { dot(Theme.gold) }
            if strip.gate.on { dot(Theme.meterLow) }
            if strip.dynamics.on { dot(Theme.warning) }
            if strip.eq.on { dot(Theme.textPrimary) }
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 4, height: 4)
    }

    // MARK: Buttons — ON and SOLO, at the top of the strip

    private var buttons: some View {
        VStack(spacing: 4) {
            OnButton(
                isOn: strip.on && !mutedByGroup,
                isDimmed: mutedByGroup && strip.on,
                action: { client.toggleMute(id) }
            )

            if !isSimplified,
               XAirAddress.soloIndex(for: id, model: client.state.model) != nil {
                MixButton(
                    title: "SOLO",
                    isOn: strip.solo,
                    tint: Theme.solo,
                    action: { client.toggleSolo(id) }
                )
            } else {
                // DCAs have no solo bus, and simplified mode hides solo
                // everywhere. Hold the space anyway so every fader in the bank
                // stays on the same line.
                Color.clear.frame(height: 30)
            }
        }
    }

    // MARK: Readout

    private var readout: some View {
        VStack(spacing: 1) {
            Text(XAirFormat.decibels(faderDB))
                .font(Theme.value(15, weight: .bold))
                .foregroundStyle(isSendMode ? Theme.warning : Theme.textPrimary)
            if isSendMode, let slot = mode.sendSlot {
                Text("→ \(client.state.sendLabel(slot))")
                    .font(Theme.label(8, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if id.hasPan {
                Text(XAirFormat.pan(strip.panValue))
                    .font(Theme.label(9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text(" ").font(Theme.label(9))
            }
        }
    }

    // MARK: Badges

    private var badges: some View {
        HStack(spacing: 3) {
            if id.hasMainAssign, !strip.assignedToMain {
                Badge(text: "no LR", tint: Theme.warning)
            }
            ForEach(strip.dcaMask.groupBits(upTo: client.state.model.dcaCount), id: \.self) { n in
                Badge(text: "D\(n)", tint: Theme.gold)
            }
            ForEach(strip.muteGroupMask.groupBits(upTo: client.state.model.muteGroupCount), id: \.self) { n in
                Badge(text: "M\(n)", tint: Theme.mute)
            }
            Spacer(minLength: 0)
        }
        .frame(height: StripLayout.badgesHeight)
    }
}
