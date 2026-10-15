//
//  HomeView.swift
//  TalaMixer
//
//  The landing page, in the shape of Tala Shruti's home: serif greeting, one
//  hero card for the desk, then a grid of tool cards.
//

import SwiftUI

struct HomeView: View {
    @Environment(XAirClient.self) private var client
    @AppStorage("simplifiedMode") private var simplified = false

    var openTab: (AppTab) -> Void
    var openConnection: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                deskCard

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("mixing tools")
                            .themeSectionLabel(13)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel("Mixing tools")
                        LinearGradient(colors: [Theme.gold.opacity(0.25), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }

                    if simplified {
                        toolCard(.mixer,
                                 subtitle: "Faders, mutes and monitor mixes")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                            GridItem(.flexible(), spacing: 14)],
                                  spacing: 14) {
                            toolCard(.mixer,
                                     subtitle: "Faders, mutes and sends")
                            toolCard(.effects,
                                     subtitle: "Four stereo engines")
                            toolCard(.scenes,
                                     subtitle: "Save and recall scenes")
                            toolCard(.tools,
                                     subtitle: "Meters · routing · recorder · OSC")
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, Theme.Metric.tabBarClearance)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack(alignment: .top) {
                Theme.background
                // A candle behind the greeting — warmth without noise.
                RadialGradient(colors: [Theme.gold.opacity(0.09), .clear],
                               center: .init(x: 0.25, y: 0),
                               startRadius: 20, endRadius: 640)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TALAMIXER")
                    .font(Theme.label(11, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Theme.gold.opacity(0.85))
                    .accessibilityLabel("TalaMixer")
                Text(greeting)
                    .themeTitle(36)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).lowercased())
                    .themeSectionLabel(13)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            ToggleChip(title: simplified ? "SIMPLE ON" : "SIMPLE",
                       isOn: simplified,
                       accessibilityLabel: "Simplified mode") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    simplified.toggle()
                }
            }
            .accessibilityHint("Shows only faders and mutes, hiding solo, sends, effects and snapshots")
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Desk card

    private var deskCard: some View {
        Button {
            if client.status.isLive { openTab(.mixer) } else { openConnection() }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("the desk")
                        .themeSectionLabel(12)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 9) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 9, height: 9)
                            .shadow(color: statusColor.opacity(0.8), radius: 4)
                            .accessibilityHidden(true)
                        Text(deskTitle)
                            .themeTitle(22)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(deskSubtitle)
                        .themeBody(11)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 12)

                if client.status.isLive {
                    mainMeters
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .well(Theme.Metric.cornerSmall)
                }

                RoundIconButton(
                    icon: client.status.isLive
                        ? "slider.vertical.3"
                        : "antenna.radiowaves.left.and.right",
                    label: client.status.isLive ? "Open mixer" : "Connect to a mixer",
                    size: 52, prominent: true
                ) {
                    if client.status.isLive { openTab(.mixer) } else { openConnection() }
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                client.status.isLive
                                    ? LinearGradient(colors: [Theme.gold.opacity(0.45),
                                                              Theme.gold.opacity(0.10)],
                                                     startPoint: .top, endPoint: .bottom)
                                    : Theme.cardEdge,
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 9)
            )
        }
        .buttonStyle(Pressable(scale: 0.99))
        // The inner icon button performs the same action, so one element is
        // both clearer and shorter for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The desk: \(deskTitle)")
        .accessibilityValue(deskSubtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(client.status.isLive ? "Opens the mixer" : "Opens the connection panel")
    }

    /// The main LR meters, alive on the home page — the desk breathing.
    private var mainMeters: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { _ in
            let left = XAirMeterLayout.index(in: .all, for: .main, model: client.state.model)
            let right = XAirMeterLayout.rightIndex(in: .all, for: .main, model: client.state.model)
            HStack(spacing: 3) {
                MeterBar(db: client.state.meters.level(at: left),
                         peakDB: client.state.meters.peak(at: left),
                         width: 5)
                MeterBar(db: client.state.meters.level(at: right),
                         peakDB: client.state.meters.peak(at: right),
                         width: 5)
            }
            .frame(height: 46)
        }
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: return client.isDemo ? Theme.warning : Theme.meterLow
        case .syncing, .connecting: return Theme.gold
        case .failed: return Theme.mute
        case .disconnected: return Theme.textTertiary
        }
    }

    private var deskTitle: String {
        if client.isDemo { return "Demo Desk" }
        let name = client.state.info.name
        if !name.isEmpty { return name }
        return client.host.isEmpty ? "Not connected" : client.host
    }

    private var deskSubtitle: String {
        switch client.status {
        case .connected:
            let model = client.state.info.model.isEmpty ? client.state.model.id : client.state.info.model
            let firmware = client.state.info.firmware
            return firmware.isEmpty ? "\(model) · connected" : "\(model) · fw \(firmware) · connected"
        case .syncing: return "Syncing the desk state…"
        case .connecting: return "Connecting…"
        case .failed(let reason): return reason
        case .disconnected: return "Connect to a mixer or run the demo"
        }
    }

    // MARK: Tool cards

    private func toolCard(_ tab: AppTab, subtitle: String) -> some View {
        Button {
            Haptics.tap()
            openTab(tab)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [Theme.gold.opacity(0.22),
                                                            Theme.gold.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Theme.gold.opacity(0.25), lineWidth: 1)
                                )
                        )
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .themeTitle(19)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .themeBody(11)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.cardEdge, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
            )
        }
        .buttonStyle(Pressable())
    }
}
