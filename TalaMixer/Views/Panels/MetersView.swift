//
//  MetersView.swift
//  TalaMixer
//
//  The all-meters overview: every strip's level in one glance, plus the RTA.
//

import SwiftUI

struct MetersContent: View {
    @Environment(XAirClient.self) private var client

    var body: some View {
        VStack(spacing: 16) {
            rtaPanel
            meterPanel("inputs", family: .inputs)
            HStack(alignment: .top, spacing: 16) {
                meterPanel("returns", family: .returns)
                meterPanel("mixes", family: .buses)
            }
            HStack(alignment: .top, spacing: 16) {
                meterPanel("fx sends", family: .fxSends)
                mainPanel
            }
        }
        .onAppear { client.beginRTA() }
        .onDisappear { client.endRTA() }
    }

    // MARK: RTA

    private var rtaPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("spectrum", subtitle: "20 Hz – 20 kHz · main LR")

            TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
                let bins = client.state.meters.rtaBins
                Canvas { context, size in
                    guard bins.count > 1 else {
                        // Nothing yet — draw the baseline so the panel reads as intentional.
                        var base = Path()
                        base.move(to: CGPoint(x: 0, y: size.height - 1))
                        base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                        context.stroke(base, with: .color(Theme.stroke), lineWidth: 1)
                        return
                    }
                    let barWidth = size.width / CGFloat(bins.count)
                    for (i, db) in bins.enumerated() {
                        let t = ((db + 80) / 80).clampedToUnit
                        let h = size.height * CGFloat(t)
                        let rect = CGRect(x: CGFloat(i) * barWidth,
                                          y: size.height - h,
                                          width: barWidth * 0.75,
                                          height: h)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                     with: .color(Theme.gold.opacity(0.75)))
                    }
                }
                .frame(height: 150)
            }
            .well(Theme.Metric.cornerMedium)

            HStack {
                ForEach(["20", "100", "500", "2k", "10k", "20k"], id: \.self) { label in
                    Text(label)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                    if label != "20k" { Spacer() }
                }
            }
        }
        .panel()
    }

    // MARK: Strip meters

    private func meterPanel(_ title: String, family: StripID.Family) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(client.state.strips(in: family)) { strip in
                        meterColumn(strip)
                    }
                }
            }
        }
        .panel()
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("main")
            HStack(alignment: .bottom, spacing: 10) {
                meterColumn(client.state.strip(.main))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel()
    }

    private func meterColumn(_ strip: StripState) -> some View {
        let left = XAirMeterLayout.index(in: .all, for: strip.id, model: client.state.model)
        let right = XAirMeterLayout.rightIndex(in: .all, for: strip.id, model: client.state.model)

        return VStack(spacing: 5) {
            LiveMeter(store: client.state.meters,
                      index: left,
                      rightIndex: right,
                      width: right == nil ? 8 : 5)
                .frame(height: 110)

            Text(strip.displayName)
                .font(Theme.label(9, weight: .semibold))
                .foregroundStyle(strip.isMuted ? Theme.textTertiary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        // A fixed column keeps rows from stretching the page; the row scrolls
        // sideways instead when a bank is wide.
        .frame(width: 52)
    }
}
