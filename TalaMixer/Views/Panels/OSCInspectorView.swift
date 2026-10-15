//
//  OSCInspectorView.swift
//  TalaMixer
//
//  A live view of the OSC traffic, plus a way to send any address by hand.
//
//  A handful of X-Air paths aren't publicly documented. Rather than guess in
//  silence, the app ships the tool for settling them against real hardware.
//

import SwiftUI

struct OSCInspectorContent: View {
    @Environment(XAirClient.self) private var client

    @State private var address = "/ch/01/mix/fader"
    @State private var argumentText = ""
    @State private var argumentType: ArgumentType = .none

    enum ArgumentType: String, CaseIterable, Identifiable {
        case none = "Query"
        case float = "Float"
        case int = "Int"
        case string = "String"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            senderPanel
            logPanel
            referencePanel
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ToggleChip(title: client.log.isEnabled ? "LOGGING ON" : "LOGGING OFF",
                       isOn: client.log.isEnabled,
                       tint: Theme.active,
                       width: 130) {
                client.log.isEnabled.toggle()
            }
            Button {
                client.log.clear()
            } label: {
                Text("Clear")
                    .font(Theme.label(11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.surfaceRaised)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Sender

    private var senderPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Send a message")

            TextField("/ch/01/mix/fader", text: $address)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .well(Theme.Metric.cornerSmall)

            HStack(spacing: 8) {
                SegmentedControl(
                    options: ArgumentType.allCases.map { .init(value: $0, label: $0.rawValue) },
                    selection: argumentType
                ) { argumentType = $0 }
                .frame(width: 260)

                if argumentType != .none {
                    TextField("value", text: $argumentText)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .well(Theme.Metric.cornerSmall)
                }

                Button {
                    sendMessage()
                } label: {
                    Text(argumentType == .none ? "Query" : "Send")
                        .font(Theme.label(12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(address.isEmpty)
            }

            if !client.log.isEnabled {
                Text("Turn logging on to see what comes back.")
                    .font(Theme.label(10, weight: .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
        .panel()
    }

    // MARK: Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Traffic", subtitle: "\(client.log.entries.count) recent · newest first")

            if client.log.entries.isEmpty {
                Text(client.log.isEnabled
                     ? "Nothing logged yet. Touch a fader, or send a query above."
                     : "Logging is off.")
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(client.log.entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.direction.rawValue)
                                .font(Theme.mono(9, weight: .bold))
                                .foregroundStyle(entry.direction == .inbound ? Theme.active : Theme.accent)
                                .frame(width: 26, alignment: .leading)
                            Text(entry.timeText)
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.textTertiary)
                            Text(entry.address)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(entry.summary)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Theme.surfaceSunken.opacity(0.5))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.stroke).frame(height: 0.5)
                        }
                        .contextMenu {
                            Button("Use this address") { address = entry.address }
                            Button("Copy") {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = "\(entry.address) \(entry.summary)"
                                #endif
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous))
            }
        }
        .panel()
    }

    // MARK: Reference

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("useful paths", subtitle: "tap to load into the sender")

            ChipGrid(columns: 2) {
                ForEach(Self.unverifiedPaths, id: \.self) { path in
                    Button {
                        address = path
                        argumentType = .none
                    } label: {
                        HStack {
                            Text(path)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel()
    }

    private static let unverifiedPaths = [
        "/-stat/solosw/01",
        "/-stat/clearsolo",
        "/-snap/load",
        "/-snap/01/name",
        "/-snap/index",
        "/-stat/tape/state",
        "/-stat/tape/file",
        "/-stat/tape/etime",
        "/ch/01/config/insrc",
        "/ch/01/insert/sel",
    ]

    // MARK: Actions

    private func sendMessage() {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.tap()

        switch argumentType {
        case .none:
            client.queryRaw(trimmed)
        case .float:
            guard let value = Float(argumentText) else { return }
            client.sendRaw(trimmed, values: [.float(value)])
        case .int:
            guard let value = Int32(argumentText) else { return }
            client.sendRaw(trimmed, values: [.int(value)])
        case .string:
            client.sendRaw(trimmed, values: [.string(argumentText)])
        }
    }
}
