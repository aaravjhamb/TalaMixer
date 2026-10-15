//
//  ChannelDetailView.swift
//  TalaMixer
//
//  The full channel strip, presented over the fader bank. Tabs are built from
//  the strip's capabilities, so a bus never shows a gate it doesn't have.
//

import SwiftUI

struct ChannelDetailView: View {
    @Environment(XAirClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    let stripID: StripID
    @State private var tab: Tab = .eq

    enum Tab: String, Identifiable, CaseIterable {
        case config = "Channel"
        case preamp = "Preamp"
        case eq = "EQ"
        case graphicEQ = "GEQ"
        case gate = "Gate"
        case dynamics = "Comp"
        case sends = "Sends"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .config: return "slider.horizontal.3"
            case .preamp: return "dial.high"
            case .eq: return "waveform.path.ecg"
            case .graphicEQ: return "chart.bar"
            case .gate: return "gate.open"
            case .dynamics: return "arrow.down.right.and.arrow.up.left"
            case .sends: return "arrow.up.right.circle"
            }
        }
    }

    private var strip: StripState { client.state.strip(stripID) }

    private var tabs: [Tab] {
        var result: [Tab] = [.config]
        if stripID.hasPreamp { result.append(.preamp) }
        if stripID.eqBandCount > 0 { result.append(.eq) }
        if stripID.hasGraphicEQ { result.append(.graphicEQ) }
        if stripID.hasGate { result.append(.gate) }
        if stripID.hasDynamics { result.append(.dynamics) }
        if stripID.hasSends { result.append(.sends) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar

            ScrollView {
                content
                    .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .presentationSizing(.page)
        .presentationBackground(Theme.background)
        .syncOnSession(client) { client.deepSync(stripID) }
        .onAppear {
            if !tabs.contains(tab) { tab = tabs.first ?? .config }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(strip.color == .off ? Theme.surfaceRaised : strip.color.tint)
                .frame(width: 6, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(strip.displayName)
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.textPrimary)
                Text(stripID.tag + (stripID.headampIndex != nil ? " · Mic in \(stripID.headampIndex!)" : ""))
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(XAirFormat.decibelsWithUnit(strip.faderDB))
                    .font(Theme.value(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Fader")
                    .font(Theme.label(9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            copyPasteMenu

            OnButton(isOn: strip.on) {
                client.toggleMute(stripID)
            }
            .frame(width: 74)

            if XAirAddress.soloIndex(for: stripID, model: client.state.model) != nil {
                MixButton(title: "SOLO", isOn: strip.solo, tint: Theme.solo) {
                    client.toggleSolo(stripID)
                }
                .frame(width: 74)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    /// Copy this channel's processing, or paste a copied one here.
    private var copyPasteMenu: some View {
        Menu {
            Button {
                client.clipboard.copy(from: strip)
            } label: {
                Label("Copy channel settings", systemImage: "doc.on.doc")
            }

            if !client.clipboard.isEmpty, let settings = client.clipboard.settings {
                Section("Paste from \(client.clipboard.sourceName)") {
                    Button("Everything") {
                        client.apply(settings, to: stripID, sections: .all)
                    }
                    Button("EQ only") {
                        client.apply(settings, to: stripID, sections: .eq)
                    }
                    Button("Gate + compressor") {
                        client.apply(settings, to: stripID, sections: [.gate, .dynamics])
                    }
                    Button("Sends only") {
                        client.apply(settings, to: stripID, sections: .sends)
                    }
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surfaceRaised))
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { item in
                let isSelected = tab == item
                Button {
                    Haptics.tap()
                    tab = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.rawValue)
                            .font(Theme.label(12, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? Theme.surfaceRaised : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isSelected ? Theme.strokeStrong : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .config: ConfigSection(stripID: stripID)
        case .preamp: PreampSection(stripID: stripID)
        case .eq: EQSection(stripID: stripID)
        case .graphicEQ: GraphicEQSection(stripID: stripID)
        case .gate: GateSection(stripID: stripID)
        case .dynamics: DynamicsSection(stripID: stripID)
        case .sends: SendsSection(stripID: stripID)
        }
    }
}
