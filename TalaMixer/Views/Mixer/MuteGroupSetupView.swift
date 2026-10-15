//
//  MuteGroupSetupView.swift
//  TalaMixer
//
//  Mute group membership editor: pick a group, then toggle which strips it
//  mutes. Engaging the group from the mixer's mute row then pulls all its
//  members down at once.
//

import SwiftUI

struct MuteGroupSetupView: View {
    @Environment(XAirClient.self) private var client

    @State private var group = 1

    var body: some View {
        PanelScaffold("Mute groups", subtitle: "channels in each group", sizing: .form) {
            VStack(spacing: 16) {
                groupPicker
                testPanel
                membersPanel
            }
        }
    }

    // MARK: Group selection

    private var groupPicker: some View {
        SegmentedControl(
            options: (1...client.state.model.muteGroupCount).map {
                .init(value: $0, label: "Group \($0)")
            },
            selection: group,
            tint: Theme.mute
        ) { group = $0 }
    }

    /// Live toggle for the selected group, so the edit can be heard immediately.
    private var testPanel: some View {
        let isOn = client.state.muteGroups.indices.contains(group - 1)
            && client.state.muteGroups[group - 1]
        let members = memberStrips.count

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Group \(group)")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.textPrimary)
                Text(members == 1 ? "1 strip assigned" : "\(members) strips assigned")
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            ToggleChip(title: isOn ? "MUTED" : "LIVE",
                       isOn: isOn,
                       tint: Theme.mute,
                       width: 92) {
                client.toggleMuteGroup(group)
            }
        }
        .panel()
    }

    // MARK: Members

    private var assignableStrips: [StripState] {
        client.state.stripOrder
            .filter { $0.hasGroupAssign }
            .map { client.state.strip($0) }
    }

    private var memberStrips: [StripState] {
        assignableStrips.filter { $0.muteGroupMask.hasGroupBit(group) }
    }

    private var membersPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("members", subtitle: "tap to add or remove") {
                Button {
                    for strip in memberStrips {
                        client.setMuteGroupAssignment(strip.id, group: group, on: false)
                    }
                } label: {
                    Text("Clear all")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(memberStrips.isEmpty ? 0.35 : 1)
                .disabled(memberStrips.isEmpty)
            }

            ForEach(StripID.Family.allCases.filter { family in
                assignableStrips.contains { $0.id.family == family }
            }) { family in
                VStack(alignment: .leading, spacing: 8) {
                    Text(family.rawValue.lowercased())
                        .font(Theme.sectionLabel(12))
                        .foregroundStyle(Theme.textTertiary)

                    ChipGrid(columns: 4) {
                        ForEach(assignableStrips.filter { $0.id.family == family }) { strip in
                            let isMember = strip.muteGroupMask.hasGroupBit(group)
                            memberChip(strip, isMember: isMember)
                        }
                    }
                }
            }
        }
        .panel()
    }

    private func memberChip(_ strip: StripState, isMember: Bool) -> some View {
        Button {
            Haptics.tap()
            client.setMuteGroupAssignment(strip.id, group: group, on: !isMember)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(strip.color == .off ? Theme.textTertiary : strip.color.tint)
                    .frame(width: 7, height: 7)
                Text(strip.displayName)
                    .font(Theme.label(12, weight: isMember ? .bold : .medium))
                    .foregroundStyle(isMember ? Color.black.opacity(0.85) : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                    .fill(isMember ? Theme.mute : Theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                            .stroke(isMember ? Theme.mute : Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
