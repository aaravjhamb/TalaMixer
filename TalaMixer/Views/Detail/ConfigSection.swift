//
//  ConfigSection.swift
//  TalaMixer
//
//  Naming, colour, pan, bus/group assignment, insert and automix.
//

import SwiftUI

struct ConfigSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    @State private var draftName = ""
    @State private var hasLoadedName = false

    private var strip: StripState { client.state.strip(stripID) }

    var body: some View {
        VStack(spacing: 14) {
            identityPanel

            if stripID.hasPan || stripID.hasMainAssign {
                placementPanel
            }

            if stripID.hasGroupAssign {
                assignmentPanel
            }

            if stripID.hasAutomix {
                automixPanel
            }

            if stripID.hasInsert {
                insertPanel
            }

            if stripID.eqBandCount > 0 {
                presetsPanel
            }

            if case .dca(let n) = stripID {
                dcaMembersPanel(n)
            }
        }
        .onAppear {
            guard !hasLoadedName else { return }
            draftName = strip.name
            hasLoadedName = true
        }
        .onChange(of: strip.name) { previous, current in
            // The desk's name often lands after this panel opens. Adopt it,
            // unless the user has already typed something else.
            if draftName == previous { draftName = current }
        }
    }

    // MARK: Identity

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Name & colour", subtitle: "12 characters max")

            TextField("Channel name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .well(Theme.Metric.cornerSmall)
                .autocorrectionDisabled()
                .onChange(of: draftName) { _, newValue in
                    if newValue.count > 12 { draftName = String(newValue.prefix(12)) }
                }
                .onSubmit { client.setName(stripID, draftName) }

            HStack {
                Button {
                    client.setName(stripID, draftName)
                } label: {
                    Text("Apply name")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(draftName == strip.name)
                .opacity(draftName == strip.name ? 0.4 : 1)

                Spacer()
            }

            ChipGrid(columns: 8) {
                ForEach(XAirColor.allCases) { color in
                    Button {
                        Haptics.tap()
                        client.setColor(stripID, color)
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.isInverted ? color.tint : color.tint.opacity(0.28))
                            .frame(height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(strip.colorIndex == color.rawValue
                                            ? Theme.textPrimary : Theme.stroke,
                                            lineWidth: strip.colorIndex == color.rawValue ? 2 : 1)
                            )
                            .overlay(
                                Text(color.isInverted ? "●" : "○")
                                    .font(.system(size: 10))
                                    .foregroundStyle(color.tint.opacity(0.9))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel()
    }

    // MARK: Pan / LR

    private var placementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Placement")

            if stripID.hasPan {
                ParameterSlider(
                    title: "Pan",
                    scale: P.pan,
                    wire: strip.panWire,
                    format: { XAirFormat.pan($0) },
                    resetWire: 0.5,
                    bipolar: true,
                    onChange: { client.setPan(stripID, wire: $0) },
                    onEnded: { client.endGesture(stripID.panAddress) }
                )
            }

            if stripID.hasMainAssign {
                HStack(spacing: 8) {
                    ToggleChip(title: "TO MAIN LR",
                               isOn: strip.assignedToMain,
                               tint: Theme.active,
                               width: 130) {
                        client.setMainAssign(stripID, !strip.assignedToMain)
                    }
                    Text(strip.assignedToMain
                         ? "Feeding the main mix"
                         : "Removed from the main mix")
                        .font(Theme.label(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
            }
        }
        .panel()
    }

    // MARK: DCA / mute group assignment

    private var assignmentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Groups")

            VStack(alignment: .leading, spacing: 7) {
                Text("DCA")
                    .font(Theme.label(10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(1...client.state.model.dcaCount, id: \.self) { n in
                        let dca = client.state.strip(.dca(n))
                        ToggleChip(title: dca.displayName,
                                   isOn: strip.dcaMask.hasGroupBit(n),
                                   tint: Theme.accent) {
                            client.setDCAAssignment(stripID, dca: n,
                                                    on: !strip.dcaMask.hasGroupBit(n))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("MUTE GROUP")
                    .font(Theme.label(10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(1...client.state.model.muteGroupCount, id: \.self) { n in
                        ToggleChip(title: "Group \(n)",
                                   isOn: strip.muteGroupMask.hasGroupBit(n),
                                   tint: Theme.mute) {
                            client.setMuteGroupAssignment(stripID, group: n,
                                                          on: !strip.muteGroupMask.hasGroupBit(n))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .panel()
    }

    // MARK: Automix

    private var automixPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Automix", subtitle: client.state.automixEnabled ? "Enabled" : "Disabled") {
                ToggleChip(title: "MASTER",
                           isOn: client.state.automixEnabled,
                           tint: Theme.active,
                           width: 84) {
                    client.setAutomixEnabled(!client.state.automixEnabled)
                }
            }

            SegmentedControl(
                options: [.init(value: 0, label: "Off"),
                          .init(value: 1, label: "Group X"),
                          .init(value: 2, label: "Group Y")],
                selection: strip.automix.group
            ) { client.setAutomixGroup(stripID, $0) }

            ParameterSlider(
                title: "Weight",
                scale: P.automixWeight,
                wire: strip.automix.weightWire,
                format: { XAirFormat.gain($0) },
                resetWire: P.automixWeight.wire(fromValue: 0),
                bipolar: true,
                onChange: { client.setAutomixWeight(stripID, wire: $0) },
                onEnded: { client.endGesture(stripID.automixWeightAddress) }
            )
            .opacity(strip.automix.group == 0 ? 0.4 : 1)
            .allowsHitTesting(strip.automix.group != 0)
        }
        .panel()
    }

    // MARK: Insert

    private var insertPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Insert") {
                ToggleChip(title: strip.insert.on ? "ON" : "OFF",
                           isOn: strip.insert.on,
                           tint: Theme.active,
                           width: 62) {
                    client.setInsertOn(stripID, !strip.insert.on)
                }
            }

            HStack(spacing: 10) {
                Text("Slot")
                    .font(Theme.label(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Stepper(value: Binding(
                    get: { strip.insert.selection },
                    set: { client.setInsertSelection(stripID, $0) }
                ), in: 0...8) {
                    Text("\(strip.insert.selection)")
                        .font(Theme.value(13))
                        .foregroundStyle(Theme.textPrimary)
                }
                .labelsHidden()
                Text("\(strip.insert.selection)")
                    .font(Theme.value(13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            Text("Insert slots are shown by number. The desk does not publish which FX engine each slot maps to.")
                .font(Theme.label(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .panel()
    }

    // MARK: Presets

    @State private var presetNamePrompt = false
    @State private var presetName = ""

    /// EQ + gate + compressor bundles, saved on the iPad, applicable to any
    /// channel. Levels and sends deliberately stay out of presets.
    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("channel presets", subtitle: "eq · gate · compressor") {
                Button {
                    presetName = strip.displayName
                    presetNamePrompt = true
                } label: {
                    Text("Save current")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.gold))
                }
                .buttonStyle(.plain)
            }

            if client.presets.presets.isEmpty {
                Text("No presets saved. Save current stores this channel's EQ, gate and compressor for use on any channel.")
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(client.presets.presets) { preset in
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.gold)
                        Text(preset.name)
                            .font(Theme.label(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button {
                            Haptics.tap()
                            client.apply(preset.settings, to: stripID,
                                         sections: [.eq, .gate, .dynamics])
                        } label: {
                            Text("Apply")
                                .font(Theme.label(11, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 13)
                                .frame(height: 28)
                                .background(Capsule().fill(Theme.surfaceRaised))
                        }
                        .buttonStyle(.plain)
                        Button {
                            client.presets.delete(preset)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Theme.surfaceRaised))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panel()
        .alert("Save preset", isPresented: $presetNamePrompt) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                client.presets.save(name: name.isEmpty ? "Untitled" : name,
                                    settings: StripSettings.capture(from: strip))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: DCA members

    private func dcaMembersPanel(_ index: Int) -> some View {
        let members = client.state.stripOrder
            .filter { $0.hasGroupAssign }
            .map { client.state.strip($0) }
            .filter { $0.dcaMask.hasGroupBit(index) }

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Members", subtitle: "\(members.count) assigned")

            if members.isEmpty {
                Text("No strips are assigned to this DCA yet. Assign them from each channel's Groups panel.")
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ChipGrid(columns: 4) {
                    ForEach(members) { member in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(member.color == .off ? Theme.textTertiary : member.color.tint)
                                .frame(width: 7, height: 7)
                            Text(member.displayName)
                                .font(Theme.label(11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                    }
                }
            }
        }
        .panel()
    }
}
