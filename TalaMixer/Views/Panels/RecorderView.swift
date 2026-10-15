//
//  RecorderView.swift
//  TalaMixer
//
//  The built-in two-track USB recorder / player.
//

import SwiftUI

struct RecorderContent: View {
    @Environment(XAirClient.self) private var client

    private var tape: TapeState { client.state.tape }

    var body: some View {
        VStack(spacing: 16) {
            statusPanel
            transportPanel
            virtualSoundcheckPanel
        }
        .syncOnSession(client) {
            client.queryRaw(XAirAddress.tapeState)
            client.queryRaw(XAirAddress.tapeFile)
            client.queryRaw(XAirAddress.tapePosition)
            client.queryRaw(XAirAddress.tapeRemaining)
        }
    }

    // MARK: Status

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Status")

            HStack(spacing: 12) {
                Circle()
                    .fill(tape.state.isRecording ? Theme.mute
                          : (tape.state == .play ? Theme.active : Theme.textTertiary))
                    .frame(width: 12, height: 12)
                    .shadow(color: tape.state.isRecording ? Theme.mute.opacity(0.8) : .clear, radius: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tape.state.displayName)
                        .font(Theme.label(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tape.file.isEmpty ? "No file" : tape.file)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(tape.elapsed.isEmpty ? "--:--" : tape.elapsed)
                        .font(Theme.value(17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tape.remaining.isEmpty ? "remaining --:--" : "remaining \(tape.remaining)")
                        .font(Theme.label(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .panel()
    }

    // MARK: Transport

    private var transportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Transport")

            HStack(spacing: 10) {
                transportButton("backward.end.fill", "Rewind", .rewind, tint: Theme.textSecondary)
                transportButton("stop.fill", "Stop", .stop, tint: Theme.textSecondary)
                transportButton("pause.fill", "Pause", .pausePlay, tint: Theme.textSecondary)
                transportButton("play.fill", "Play", .play, tint: Theme.active)
                transportButton("forward.end.fill", "Forward", .fastForward, tint: Theme.textSecondary)
                Spacer()
                transportButton("record.circle.fill", "Record", .record, tint: Theme.mute)
            }
        }
        .panel()
    }

    private func transportButton(_ icon: String, _ title: String,
                                 _ target: XAirTapeState, tint: Color) -> some View {
        let isActive = tape.state == target
        return Button {
            Haptics.tap()
            client.setTapeState(target)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(Theme.label(9, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : tint)
            .frame(width: 64, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? tint : Theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? tint : Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Virtual soundcheck

    private var virtualSoundcheckPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Virtual soundcheck")

            Text("Recording captures the inputs. Play it back and switch channels to their USB source (on each channel's Preamp page, or in Routing) to mix the band without the band in the room.")
                .font(Theme.label(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            let switched = client.state.stripOrder
                .filter { $0.hasPreamp }
                .filter { client.state.strip($0).preamp.usbInput }

            HStack(spacing: 8) {
                Button {
                    for id in client.state.stripOrder where id.hasPreamp {
                        client.setUSBInput(id, true)
                    }
                } label: {
                    Text("All to USB")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.warning))
                }
                .buttonStyle(.plain)

                Button {
                    for id in client.state.stripOrder where id.hasPreamp {
                        client.setUSBInput(id, false)
                    }
                } label: {
                    Text("All to analogue")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.surfaceRaised))
                }
                .buttonStyle(.plain)

                if !switched.isEmpty {
                    Badge(text: "\(switched.count) on USB", tint: Theme.warning)
                }
                Spacer()
            }
        }
        .panel()
    }
}

// MARK: - Monitor bus

struct MonitorContent: View {
    @Environment(XAirClient.self) private var client

    private var monitor: MonitorState { client.state.monitor }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Level") {
                        HStack(spacing: 8) {
                            ToggleChip(title: "DIM", isOn: monitor.dim, tint: Theme.warning, width: 62) {
                                client.setMonitorDim(!monitor.dim)
                            }
                            ToggleChip(title: "MONO", isOn: monitor.mono, tint: Theme.accent, width: 74) {
                                client.setMonitorMono(!monitor.mono)
                            }
                            ToggleChip(title: "MUTE", isOn: monitor.mute, tint: Theme.mute, width: 74) {
                                client.setMonitorMute(!monitor.mute)
                            }
                        }
                    }

                    ParameterSlider(
                        title: "Monitor level",
                        scale: P.monitorLevel,
                        wire: monitor.levelWire,
                        format: { XAirFormat.decibelsWithUnit($0) },
                        onChange: { client.setMonitorLevel(wire: $0) },
                        onEnded: { client.endGesture(XAirAddress.soloLevel) }
                    )

                    ParameterSlider(
                        title: "Dim attenuation",
                        scale: P.dimAttenuation,
                        wire: monitor.dimAttenuationWire,
                        tint: Theme.warning,
                        format: { String(format: "%.0f dB", $0) },
                        onChange: { client.setMonitorDimAttenuation(wire: $0) },
                        onEnded: { client.endGesture(XAirAddress.soloDimAttenuation) }
                    )

                    ParameterSlider(
                        title: "Source trim",
                        scale: P.monitorTrim,
                        wire: monitor.trimWire,
                        format: { XAirFormat.gain($0) },
                        resetWire: P.monitorTrim.wire(fromValue: 0),
                        bipolar: true,
                        onChange: { client.setMonitorTrim(wire: $0) },
                        onEnded: { client.endGesture(XAirAddress.soloSourceTrim) }
                    )
                }
                .panel()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Source", subtitle: "Raw index")
                    HStack(spacing: 10) {
                        Stepper(value: Binding(get: { monitor.source },
                                               set: { client.setMonitorSource($0) }),
                                in: 0...14) { EmptyView() }
                            .labelsHidden()
                        Text("\(monitor.source)")
                            .font(Theme.value(13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("0 is the solo bus; higher values tap other points in the desk.")
                            .font(Theme.label(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                }
                .panel()

                if client.hasAnySolo {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Soloed strips")
                        ChipGrid(columns: 4) {
                            ForEach(client.state.stripOrder.filter { client.state.strip($0).solo },
                                    id: \.self) { id in
                                ToggleChip(title: client.state.strip(id).displayName,
                                           isOn: true, tint: Theme.solo, expands: true) {
                                    client.setSolo(id, false)
                                }
                            }
                        }
                        Button {
                            client.clearAllSolos()
                        } label: {
                            Text("Clear all solos")
                                .font(Theme.label(11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(Capsule().fill(Theme.solo))
                        }
                        .buttonStyle(.plain)
                    }
                    .panel()
                }
            }
        }
    }
}
