//
//  SnapshotsView.swift
//  TalaMixer
//
//  The desk's 64 snapshot slots.
//
//  Recall is destructive and instant, so it always goes through a confirmation —
//  a mis-tap here during a show would be very audible.
//

import SwiftUI

struct SnapshotsView: View {
    @Environment(XAirClient.self) private var client

    @State private var pendingRecall: Int?
    @State private var pendingSave: Int?
    @State private var renaming: Int?
    @State private var draftName = ""

    /// Strips protected from recall: their settings are captured before the
    /// snapshot loads and written back once the desk has settled. App-side, so
    /// it works regardless of what the firmware's own scopes support.
    @State private var safes: Set<StripID> = []
    @AppStorage("snapshotSafes") private var storedSafes = ""

    var body: some View {
        PageScaffold("Snapshots", subtitle: "the mixer\u{2019}s 64 save slots") {
            VStack(spacing: 16) {
                currentPanel
                safesPanel
                grid
            }
        }
        .syncOnSession(client) { client.syncSnapshots() }
        .onAppear(perform: loadSafes)
        .confirmationDialog(
            pendingRecall.map { "Recall snapshot \($0)?" } ?? "",
            isPresented: Binding(get: { pendingRecall != nil },
                                 set: { if !$0 { pendingRecall = nil } }),
            titleVisibility: .visible
        ) {
            if let index = pendingRecall {
                Button("Recall \(name(for: index))", role: .destructive) {
                    recall(index)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(safes.isEmpty
                 ? "This overwrites the current mix on the desk immediately."
                 : "This overwrites the desk immediately. The \(safes.count) safed strips keep their current settings.")
        }
        .confirmationDialog(
            pendingSave.map { "Save over snapshot \($0)?" } ?? "",
            isPresented: Binding(get: { pendingSave != nil },
                                 set: { if !$0 { pendingSave = nil } }),
            titleVisibility: .visible
        ) {
            if let index = pendingSave {
                Button("Overwrite \(name(for: index))", role: .destructive) {
                    client.saveSnapshot(index)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The desk's current state replaces whatever is stored in this slot.")
        }
        .alert("Rename snapshot", isPresented: Binding(get: { renaming != nil },
                                                    set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Save") {
                if let index = renaming { client.renameSnapshot(index, name: draftName) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Recall with safes

    private func recall(_ index: Int) {
        // Capture the safed strips as they sound right now…
        let kept: [(StripID, StripSettings)] = safes.map {
            ($0, StripSettings.capture(from: client.state.strip($0)))
        }

        client.loadSnapshot(index)

        // …and write them back once the recall and its resync have settled.
        guard !kept.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            for (id, settings) in kept {
                client.apply(settings, to: id, sections: .all)
            }
        }
    }

    // MARK: Safes

    private var safeCandidates: [StripState] {
        client.state.stripOrder
            .filter { $0.family == .inputs || $0.family == .buses }
            .map { client.state.strip($0) }
    }

    private var safesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("recall safes",
                          subtitle: safes.isEmpty ? "none active"
                                                  : "\(safes.count) protected from recall")

            ChipGrid(columns: 6) {
                ForEach(safeCandidates) { strip in
                    let isSafe = safes.contains(strip.id)
                    ToggleChip(title: strip.displayName, isOn: isSafe,
                               tint: Theme.gold, expands: true) {
                        if isSafe { safes.remove(strip.id) } else { safes.insert(strip.id) }
                        persistSafes()
                    }
                }
            }
        }
        .panel()
    }

    private func loadSafes() {
        guard safes.isEmpty, !storedSafes.isEmpty else { return }
        let addresses = Set(storedSafes.split(separator: ",").map(String.init))
        safes = Set(client.state.stripOrder.filter { addresses.contains($0.address) })
    }

    private func persistSafes() {
        storedSafes = safes.map(\.address).sorted().joined(separator: ",")
    }

    // MARK: Current

    private var currentPanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CURRENT SNAPSHOT")
                    .font(Theme.label(9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                Text(client.state.currentSnapshot > 0
                     ? "\(client.state.currentSnapshot) · \(name(for: client.state.currentSnapshot))"
                     : "None recalled this session")
                    .font(Theme.label(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                client.syncSnapshots()
            } label: {
                Text("Reload names")
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
        .panel()
    }

    // MARK: Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Slots", subtitle: "Tap to recall · long-press for more")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(1...64, id: \.self) { index in
                    slotTile(index)
                }
            }
        }
        .panel()
    }

    private func slotTile(_ index: Int) -> some View {
        let isCurrent = client.state.currentSnapshot == index
        let isEmpty = name(for: index) == "—"

        return Button {
            pendingRecall = index
        } label: {
            HStack(spacing: 8) {
                Text(String(format: "%02d", index))
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(isCurrent ? Color.black.opacity(0.7) : Theme.textTertiary)
                Text(name(for: index))
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.black.opacity(0.9)
                                     : (isEmpty ? Theme.textTertiary : Theme.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isCurrent ? Theme.accent : Theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isCurrent ? Theme.accent : Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Recall") { pendingRecall = index }
            Button("Save current mix here") { pendingSave = index }
            Button("Rename…") {
                draftName = client.state.snapshotNames[index] ?? ""
                renaming = index
            }
        }
    }

    private func name(for index: Int) -> String {
        let stored = (client.state.snapshotNames[index] ?? "").trimmingCharacters(in: .whitespaces)
        return stored.isEmpty ? "—" : stored
    }
}
