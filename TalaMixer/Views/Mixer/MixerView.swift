//
//  MixerView.swift
//  TalaMixer
//
//  The mixing surface: status + bus selector row, group row with quick-jump,
//  and the fader bank with the master pinned right.
//

import SwiftUI

struct MixerView: View {
    @Environment(XAirClient.self) private var client
    @AppStorage("simplifiedMode") private var simplified = false

    @State private var mode: BankMode = .main
    @State private var detailStrip: StripID?
    @State private var showsMuteGroupEditor = false
    @State private var showsConnection = false
    @State private var scrollTarget: StripID?

    var body: some View {
        VStack(spacing: 0) {
            TopRow(mode: $mode, simplified: simplified,
                   openConnection: { showsConnection = true })
            Divider().overlay(Theme.stroke)
            if !simplified {
                GroupRow(showsMuteGroupEditor: $showsMuteGroupEditor, jump: jumpTo)
                Divider().overlay(Theme.stroke)
            }
            bank
                // Keep the strip readouts clear of the floating tab bar:
                // bar bottom offset (4) + bar height (54) + breathing room.
                .padding(.bottom, 66)
        }
        .background(Theme.background)
        .onAppear {
            // "-openChannel 3" opens that channel's detail — used by tests
            // and screenshot runs, like "-startTab".
            if let n = Int(UserDefaults.standard.string(forKey: "openChannel") ?? ""),
               (1...client.state.model.channelCount).contains(n) {
                detailStrip = .channel(n)
            }
        }
        .sheet(item: $detailStrip) { id in
            if simplified {
                SimpleChannelView(stripID: id)
            } else {
                ChannelDetailView(stripID: id)
            }
        }
        .sheet(isPresented: $showsMuteGroupEditor) {
            MuteGroupSetupView()
        }
        .sheet(isPresented: $showsConnection) {
            ConnectionView()
        }
    }

    // MARK: Fader bank

    private func jumpTo(_ family: StripID.Family) {
        if let first = client.state.stripOrder.first(where: { $0.family == family }) {
            scrollTarget = first
        }
    }

    private var bank: some View {
        HStack(spacing: 0) {
            // Derived from StripLayout plus the bank's own vertical inset, so the
            // ruler lines up with real fader travel instead of being eyeballed.
            FaderScale()
                .padding(.top, Self.bankVerticalInset + StripLayout.faderTopInset)
                .padding(.bottom, Self.bankVerticalInset + StripLayout.faderBottomInset)
                .padding(.leading, 6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Metric.stripSpacing) {
                        ForEach(Array(bankGroups.enumerated()), id: \.offset) { _, group in
                            if group.showsLabel {
                                FamilyDivider(title: group.family.rawValue)
                            }
                            ForEach(group.strips) { strip in
                                FaderStripView(
                                    strip: strip,
                                    mode: mode,
                                    isSelected: detailStrip == strip.id,
                                    isSimplified: simplified,
                                    onOpenDetail: { detailStrip = strip.id }
                                )
                                .id(strip.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, Self.bankVerticalInset)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                    scrollTarget = nil
                }
            }

            masterColumn
        }
    }

    /// Strips grouped by family so the bank reads in sections.
    private struct BankGroup {
        var family: StripID.Family
        var strips: [StripState]
        var showsLabel: Bool
    }

    private var bankGroups: [BankGroup] {
        // Simplified mode shows what a stand-in operator needs: the inputs and
        // returns feeding the room, plus the mix masters (wedge/IEM/FX levels).
        // Only DCAs stay the engineer's business.
        let families: [StripID.Family] = simplified
            ? [.inputs, .returns, .buses, .fxSends]
            : [.inputs, .returns, .buses, .fxSends, .dcas]
        var groups: [BankGroup] = []

        for family in families {
            var strips = client.state.strips(in: family)

            // Sends on fader only makes sense for strips that have sends. The
            // target bus master moves to the pinned column instead.
            if mode.sendSlot != nil {
                strips = strips.filter { $0.id.hasSends }
            }

            guard !strips.isEmpty else { continue }
            groups.append(BankGroup(family: family, strips: strips, showsLabel: !groups.isEmpty))
        }
        return groups
    }

    /// The master strip on the right: LR normally, or the send target's master
    /// when sends-on-fader is active.
    ///
    /// Deliberately carries no caption above it — anything there would push this
    /// fader out of line with the bank. Its position, divider and darker backing
    /// already mark it as the master.
    private var masterColumn: some View {
        let masterID: StripID = mode.sendSlot.map { client.state.sendStripID($0) } ?? .main
        let master = client.state.strip(masterID)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)

            FaderStripView(
                strip: master,
                mode: .main,
                isSelected: detailStrip == masterID,
                isSimplified: simplified,
                onOpenDetail: { detailStrip = masterID }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, Self.bankVerticalInset)
            .background(Theme.surfaceSunken.opacity(0.4))
        }
    }

    /// Vertical inset around the fader bank. The dB scale is derived from this.
    static let bankVerticalInset: CGFloat = 10
}

// MARK: - Top row: status + bus selector

private struct TopRow: View {
    @Environment(XAirClient.self) private var client
    @Binding var mode: BankMode
    var simplified: Bool = false
    var openConnection: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openConnection) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(Theme.label(12, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(Theme.label(9, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Theme.surface)
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            if case .syncing(let progress) = client.status {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.gold)
                    .frame(width: 70)
            }

            Rectangle().fill(Theme.stroke).frame(width: 1, height: 24)

            // The mix / FX-send selector stays in simplified mode — adjusting
            // wedges and effect sends is exactly what a stand-in operator is
            // handed the iPad for.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("faders")
                        .font(Theme.sectionLabel(12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.trailing, 2)

                    pill(title: "MAIN LR", isOn: mode == .main) {
                        mode = .main
                    }

                    ForEach(1...client.state.model.sendCount, id: \.self) { slot in
                        pill(title: client.state.sendLabel(slot).uppercased(),
                             isOn: mode == .sends(slot),
                             tint: Theme.warning) {
                            mode = mode == .sends(slot) ? .main : .sends(slot)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
    }

    private func pill(title: String, isOn: Bool, tint: Color = Theme.gold,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(Theme.label(11, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(isOn ? tint : Theme.surfaceRaised)
                        .overlay(Capsule().stroke(isOn ? tint : Theme.stroke, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: return client.isDemo ? Theme.warning : Theme.meterLow
        case .syncing, .connecting: return Theme.gold
        case .failed: return Theme.mute
        case .disconnected: return Theme.textTertiary
        }
    }

    private var title: String {
        if client.isDemo { return "Demo Desk" }
        let name = client.state.info.name
        return name.isEmpty ? (client.host.isEmpty ? "Not connected" : client.host) : name
    }

    private var subtitle: String {
        switch client.status {
        case .connected: return client.state.info.model.isEmpty ? client.state.model.id : client.state.info.model
        case .syncing: return "Syncing…"
        case .connecting: return "Connecting…"
        case .failed(let reason): return reason
        case .disconnected: return "Tap to connect"
        }
    }
}

// MARK: - Group row: mute groups, DCAs, quick jump

private struct GroupRow: View {
    @Environment(XAirClient.self) private var client
    @Binding var showsMuteGroupEditor: Bool
    var jump: (StripID.Family) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("mute")
                    .font(Theme.sectionLabel(12))
                    .foregroundStyle(Theme.textTertiary)

                ForEach(1...client.state.model.muteGroupCount, id: \.self) { group in
                    let isOn = client.state.muteGroups.indices.contains(group - 1)
                        && client.state.muteGroups[group - 1]
                    ToggleChip(title: "\(group)", isOn: isOn, tint: Theme.mute, width: 42,
                               accessibilityLabel: "Mute group \(group)") {
                        client.toggleMuteGroup(group)
                    }
                }

                RoundIconButton(icon: "pencil", label: "Edit mute groups", size: 30) {
                    showsMuteGroupEditor = true
                }

                Rectangle().fill(Theme.stroke).frame(width: 1, height: 22)

                Text("dca")
                    .font(Theme.sectionLabel(12))
                    .foregroundStyle(Theme.textTertiary)

                ForEach(1...client.state.model.dcaCount, id: \.self) { n in
                    let strip = client.state.strip(.dca(n))
                    ToggleChip(title: strip.displayName,
                               isOn: strip.isMuted,
                               tint: Theme.mute) {
                        client.toggleMute(.dca(n))
                    }
                }

                Rectangle().fill(Theme.stroke).frame(width: 1, height: 22)

                Text("go to")
                    .font(Theme.sectionLabel(12))
                    .foregroundStyle(Theme.textTertiary)

                jumpChip("Inputs", .inputs)
                jumpChip("Returns", .returns)
                jumpChip("Mixes", .buses)
                jumpChip("FX", .fxSends)
                jumpChip("DCAs", .dcas)

                if client.hasAnySolo {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 22)
                    ToggleChip(title: "CLEAR SOLO", isOn: true, tint: Theme.solo) {
                        client.clearAllSolos()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Theme.surface.opacity(0.3))
    }

    private func jumpChip(_ title: String, _ family: StripID.Family) -> some View {
        Button {
            Haptics.tap()
            jump(family)
        } label: {
            Text(title)
                .font(Theme.label(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bits

private struct FamilyDivider: View {
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
            Text(title.lowercased())
                .font(Theme.sectionLabel(11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(height: 60)
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
        }
        .frame(width: 16)
    }
}

// MARK: - Sheet helper

/// `sheet(item:)` for plain `Identifiable` bindings, so the panels above can be
/// driven by simple enum / ID state.
extension View {
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}
