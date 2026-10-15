//
//  RoutingView.swift
//  TalaMixer
//
//  Preamps, input sources and stereo linking.
//

import SwiftUI

struct RoutingContent: View {
    @Environment(XAirClient.self) private var client

    @State private var tab: Tab = .preamps

    enum Tab: String, CaseIterable, Identifiable {
        case preamps = "Preamps"
        case sources = "Input sources"
        case links = "Stereo links"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            SegmentedControl(
                options: Tab.allCases.map { .init(value: $0, label: $0.rawValue) },
                selection: tab
            ) { tab = $0 }

            switch tab {
            case .preamps: preamps
            case .sources: sources
            case .links: links
            }
        }
        .syncOnSession(client) { client.syncRouting() }
    }

    // MARK: Preamps

    private var preamps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Analogue gain", subtitle: "\(client.state.model.channelCount) mic inputs")

            ForEach(client.state.headamps) { headamp in
                let strip = client.state.strip(.channel(headamp.index))
                HStack(spacing: 12) {
                    Text(String(format: "%02d", headamp.index))
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(strip.color == .off ? Theme.textTertiary : strip.color.tint)
                            .frame(width: 7, height: 7)
                        Text(strip.displayName)
                            .font(Theme.label(12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 110, alignment: .leading)

                    ParameterSlider(
                        title: "",
                        scale: P.headampGain,
                        wire: headamp.gainWire,
                        format: { XAirFormat.gain($0) },
                        onChange: { client.setHeadampGain(headamp.index, wire: $0) },
                        onEnded: { client.endGesture(XAirAddress.headampGain(headamp.index)) }
                    )

                    TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { _ in
                        let index = XAirMeterLayout.index(in: .all,
                                                          for: .channel(headamp.index),
                                                          model: client.state.model)
                        HorizontalMeter(db: client.state.meters.level(at: index), height: 6)
                            .frame(width: 74)
                    }

                    ToggleChip(title: "48V", isOn: headamp.phantom, tint: Theme.mute, width: 52) {
                        client.setPhantom(headamp.index, !headamp.phantom)
                    }

                    ToggleChip(title: "Ø", isOn: strip.preamp.invert, tint: Theme.warning, width: 40) {
                        client.setPhaseInvert(.channel(headamp.index), !strip.preamp.invert)
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Input sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Input source per strip")

            ForEach(client.state.stripOrder.filter { $0.hasPreamp }, id: \.self) { id in
                let strip = client.state.strip(id)
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(strip.color == .off ? Theme.textTertiary : strip.color.tint)
                            .frame(width: 7, height: 7)
                        Text(strip.displayName)
                            .font(Theme.label(12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 130, alignment: .leading)

                    Text(id.tag)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)

                    Spacer()

                    Text("Source")
                        .font(Theme.label(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Stepper(value: Binding(get: { strip.inputSource },
                                           set: { client.setInputSource(id, $0) }),
                            in: 0...40) { EmptyView() }
                        .labelsHidden()
                    Text("\(strip.inputSource)")
                        .font(Theme.value(12))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 26)

                    ToggleChip(title: "USB", isOn: strip.preamp.usbInput, tint: Theme.warning, width: 54) {
                        client.setUSBInput(id, !strip.preamp.usbInput)
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Stereo links

    private var links: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("What a link couples")
                HStack(spacing: 8) {
                    ToggleChip(title: "EQ", isOn: client.state.links.linksEQ,
                               tint: Theme.accent, width: 74) {
                        client.setLinksEQ(!client.state.links.linksEQ)
                    }
                    ToggleChip(title: "DYNAMICS", isOn: client.state.links.linksDynamics,
                               tint: Theme.accent, width: 110) {
                        client.setLinksDynamics(!client.state.links.linksDynamics)
                    }
                    ToggleChip(title: "FADER + MUTE", isOn: client.state.links.linksFaderAndMute,
                               tint: Theme.accent, width: 140) {
                        client.setLinksFaderAndMute(!client.state.links.linksFaderAndMute)
                    }
                    Spacer()
                }
            }
            .panel()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Channel pairs")
                ChipGrid(columns: 4) {
                    ForEach(Array(stride(from: 1, through: client.state.model.channelCount - 1, by: 2)),
                            id: \.self) { odd in
                        let isOn = client.state.links.channelLinks[odd] ?? false
                        ToggleChip(title: "\(odd)–\(odd + 1)", isOn: isOn,
                                   tint: Theme.active, expands: true) {
                            client.setChannelLink(oddIndex: odd, !isOn)
                        }
                    }
                }
            }
            .panel()

            if client.state.model.busCount >= 2 {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Mix pairs")
                    ChipGrid(columns: 4) {
                        ForEach(Array(stride(from: 1, through: client.state.model.busCount - 1, by: 2)),
                                id: \.self) { odd in
                            let isOn = client.state.links.busLinks[odd] ?? false
                            ToggleChip(title: "\(odd)–\(odd + 1)", isOn: isOn,
                                       tint: Theme.active, expands: true) {
                                client.setBusLink(oddIndex: odd, !isOn)
                            }
                        }
                    }
                }
                .panel()
            }
        }
    }
}
