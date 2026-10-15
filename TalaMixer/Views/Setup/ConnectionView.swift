//
//  ConnectionView.swift
//  TalaMixer
//
//  Finding and connecting to the desk.
//

import SwiftUI

struct ConnectionView: View {
    /// Stored in place of an IP address to mean "reopen the demo desk".
    static let demoHost = "demo"

    @Environment(XAirClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastMixerHost") private var lastHost = ""

    @State private var manualHost = ""
    @State private var renamePrompt = false
    @State private var renameText = ""
    @State private var found: [OSCDiscovery.Found] = []
    @State private var discovery = OSCDiscovery()
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    statusPanel
                    discoveredPanel
                    manualPanel
                    demoPanel
                    helpPanel
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .presentationSizing(.form)
        .presentationBackground(Theme.background)
        .onAppear {
            manualHost = lastHost
            startDiscovery()
        }
        .onDisappear { discovery.stop() }
        .alert("Rename the desk", isPresented: $renamePrompt) {
            TextField("Mixer name", text: $renameText)
            Button("Rename") {
                client.renameDesk(renameText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sets the name the mixer announces on the network.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Mixer connection")
                    .themeTitle(21)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("x-air over wi-fi, udp port 10024")
                    .themeSectionLabel(12)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
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
        .padding(16)
        .background(Theme.surface)
    }

    // MARK: Status

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Status")

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusText)
                        .themeBody(13, weight: .bold)
                        .foregroundStyle(Theme.textPrimary)
                    if !client.state.info.isEmpty {
                        Text("\(client.state.info.model) · firmware \(client.state.info.firmware)")
                            .themeBody(11)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer()

                if client.status.isLive {
                    Button {
                        renameText = client.state.info.name
                        renamePrompt = true
                    } label: {
                        Text("Rename")
                            .font(Theme.label(11, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)

                    Button {
                        client.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(Theme.label(11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.mute))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel()
    }

    // MARK: Discovery

    private var discoveredPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Found on this network",
                          subtitle: isSearching ? "Searching…" : nil) {
                Button {
                    startDiscovery()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.surfaceRaised))
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search again")
            }

            if found.isEmpty {
                Text("Nothing yet. The mixer must be on the same Wi-Fi network, and iOS will ask for local network permission the first time.")
                    .themeBody(12)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(found) { mixer in
                    Button {
                        connect(to: mixer.ip)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mixer.name.isEmpty ? mixer.model : mixer.name)
                                    .themeBody(13, weight: .bold)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(mixer.model) · \(mixer.ip) · fw \(mixer.firmware)")
                                    .themeBody(11)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerMedium, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel()
    }

    // MARK: Manual

    private var manualPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Enter an address")

            HStack(spacing: 8) {
                TextField("192.168.0.10", text: $manualHost)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .well(Theme.Metric.cornerSmall)
                    .onSubmit { connect(to: manualHost) }

                Button {
                    connect(to: manualHost)
                } label: {
                    Text("Connect")
                        .font(Theme.label(12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(manualHost.isEmpty)
                .opacity(manualHost.isEmpty ? 0.4 : 1)
            }
        }
        .panel()
    }

    // MARK: Demo

    private var demoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Demo desk", subtitle: "No hardware needed")

            Text("Runs a simulated XR18 inside the app. Every control works and the meters move. No hardware needed.")
                .themeBody(12)
                .foregroundStyle(Theme.textTertiary)

            Button {
                lastHost = ConnectionView.demoHost
                client.connect(host: ConnectionView.demoHost, demo: true)
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.circle.fill")
                    Text("Start demo desk")
                }
                .font(Theme.label(12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Theme.warning))
            }
            .buttonStyle(.plain)
        }
        .panel()
    }

    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("If it won't connect")
            bullet("The iPad and the mixer have to be on the same network. The XR18's own Wi-Fi access point works, as does joining both to a router.")
            bullet("The mixer sends smooth updates to one app at a time. Quit X AIR or Mixing Station if it's running.")
            bullet("iOS asks for local network permission once. If you declined it, re-enable it in Settings › TalaMixer.")
        }
        .panel()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 4, height: 4)
                .padding(.top, 5)
                .accessibilityHidden(true)
            Text(text)
                .themeBody(12)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Actions

    private func connect(to host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        lastHost = trimmed
        client.connect(host: trimmed)
        dismiss()
    }

    private func startDiscovery() {
        found = []
        isSearching = true
        discovery.stop()
        discovery.onFound = { mixer in
            if !found.contains(where: { $0.ip == mixer.ip }) {
                found.append(mixer)
            }
        }
        discovery.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            isSearching = false
        }
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: return client.isDemo ? Theme.warning : Theme.meterLow
        case .syncing, .connecting: return Theme.solo
        case .failed: return Theme.mute
        case .disconnected: return Theme.textTertiary
        }
    }

    private var statusText: String {
        switch client.status {
        case .connected: return client.isDemo ? "Demo desk running" : "Connected to \(client.host)"
        case .syncing: return "Syncing state…"
        case .connecting: return "Connecting to \(client.host)…"
        case .failed(let reason): return reason
        case .disconnected: return "Not connected"
        }
    }
}
