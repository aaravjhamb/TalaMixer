//
//  EQSection.swift
//  TalaMixer
//
//  Parametric EQ: a live response curve with draggable band handles, plus
//  numeric controls for the selected band.
//
//  The curve is an approximation of the desk's filter shapes, not a measurement
//  of them. It is there to make the shape legible; the numbers below it are the
//  authority.
//

import SwiftUI

// MARK: - Response approximation

extension EQBandState {
    /// This band's contribution, in dB, at the given frequency.
    func contribution(atHz f: Double) -> Double {
        let f0 = max(20, frequencyHz)
        let g = gainDB

        switch type {
        case .peaking, .vintage:
            // Vintage bands are gentler, so widen the effective Q.
            let effectiveQ = type == .vintage ? Swift.max(0.3, q * 0.7) : q
            let detune = f / f0 - f0 / f
            return g / (1 + pow(effectiveQ * detune, 2))

        case .lowShelf:
            return g / (1 + pow(f / f0, 2))

        case .highShelf:
            return g / (1 + pow(f0 / f, 2))

        case .lowCut:
            // 12 dB/octave below the corner.
            guard f < f0 else { return 0 }
            return Swift.max(-30, -12 * log2(f0 / f))

        case .highCut:
            guard f > f0 else { return 0 }
            return Swift.max(-30, -12 * log2(f / f0))
        }
    }
}

/// Log-frequency and dB axis mapping, shared by the curve and its handles.
private enum EQAxis {
    static let minHz: Double = 20
    static let maxHz: Double = 20_000
    static let maxDB: Double = 18

    static func x(forHz hz: Double, width: CGFloat) -> CGFloat {
        let clamped = min(maxHz, max(minHz, hz))
        return CGFloat(log(clamped / minHz) / log(maxHz / minHz)) * width
    }

    static func hz(forX x: CGFloat, width: CGFloat) -> Double {
        let t = Double(max(0, min(width, x)) / max(1, width))
        return minHz * pow(maxHz / minHz, t)
    }

    static func y(forDB db: Double, height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(db / maxDB) * (height / 2)
    }

    static func db(forY y: CGFloat, height: CGFloat) -> Double {
        Double((height / 2 - y) / (height / 2)) * maxDB
    }
}

private let bandColors: [Color] = [
    Color(red: 0.93, green: 0.78, blue: 0.42),   // gold
    Color(red: 0.58, green: 0.78, blue: 0.52),   // sage
    Color(red: 0.91, green: 0.53, blue: 0.38),   // terracotta
    Color(red: 0.93, green: 0.89, blue: 0.78),   // ivory
    Color(red: 0.74, green: 0.55, blue: 0.82),   // plum
    Color(red: 0.47, green: 0.76, blue: 0.72),   // teal
]

// MARK: - Section

struct EQSection: View {
    @Environment(XAirClient.self) private var client
    let stripID: StripID

    @State private var selectedBand = 1

    private var strip: StripState { client.state.strip(stripID) }
    private var eq: EQState { strip.eq }

    private var band: EQBandState? { eq[selectedBand] }

    var body: some View {
        VStack(spacing: 14) {
            headerRow

            EQCurve(
                bands: eq.bands,
                selectedBand: $selectedBand,
                isEnabled: eq.on,
                meters: client.state.meters,
                onDrag: { band, hz, db in
                    client.setEQFrequency(stripID, band: band,
                                          wire: P.eqFrequency.wire(fromValue: hz))
                    client.setEQGain(stripID, band: band,
                                     wire: P.eqGain.wire(fromValue: db))
                },
                onDragEnd: { band in
                    client.endGesture(stripID.eqAddress(band: band, "f"))
                    client.endGesture(stripID.eqAddress(band: band, "g"))
                }
            )
            .frame(height: 230)
            .panel(Theme.Metric.cornerLarge, padding: 10)
            .onAppear { client.beginRTA() }
            .onDisappear { client.endRTA() }

            bandSelector

            if let band {
                bandControls(band)
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            SectionHeader("Parametric EQ", subtitle: "\(eq.bands.count) band")
            Spacer(minLength: 0)

            if stripID.hasGraphicEQ {
                SegmentedControl(
                    options: XAirEQMode.allCases.map { .init(value: $0, label: $0.displayName) },
                    selection: eq.mode
                ) { client.setEQMode(stripID, $0) }
                .frame(width: 170)
            }

            ToggleChip(title: eq.on ? "EQ ON" : "EQ OFF", isOn: eq.on, tint: Theme.active, width: 84) {
                client.setEQOn(stripID, !eq.on)
            }
        }
    }

    // MARK: Band selection

    private var bandSelector: some View {
        HStack(spacing: 6) {
            ForEach(eq.bands) { item in
                let isSelected = item.band == selectedBand
                let color = bandColors[(item.band - 1) % bandColors.count]
                Button {
                    Haptics.tap()
                    selectedBand = item.band
                } label: {
                    VStack(spacing: 2) {
                        Text("\(item.band)")
                            .font(Theme.label(12, weight: .bold))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.85) : color)
                        Text(item.type.shortName)
                            .font(Theme.label(8, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.65) : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? color : Theme.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isSelected ? color : Theme.stroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Band controls

    private func bandControls(_ band: EQBandState) -> some View {
        let color = bandColors[(band.band - 1) % bandColors.count]

        return VStack(spacing: 14) {
            SectionHeader("Band \(band.band)", subtitle: band.type.shortName) {
                Button {
                    client.resetEQBand(stripID, band: band.band)
                } label: {
                    Text("Flatten")
                        .font(Theme.label(10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            SegmentedControl(
                options: XAirEQBandType.allCases.map { .init(value: $0, label: $0.shortName) },
                selection: band.type,
                tint: color
            ) { client.setEQBandType(stripID, band: band.band, $0) }

            HStack(spacing: 22) {
                Knob(title: "Freq",
                     scale: P.eqFrequency,
                     wire: band.frequencyWire,
                     tint: color,
                     format: { XAirFormat.frequencyWithUnit($0) },
                     onChange: { client.setEQFrequency(stripID, band: band.band, wire: $0) },
                     onEnded: { client.endGesture(stripID.eqAddress(band: band.band, "f")) })

                Knob(title: "Gain",
                     scale: P.eqGain,
                     wire: band.gainWire,
                     tint: color,
                     format: { XAirFormat.gain($0) },
                     resetWire: P.eqGain.wire(fromValue: 0),
                     onChange: { client.setEQGain(stripID, band: band.band, wire: $0) },
                     onEnded: { client.endGesture(stripID.eqAddress(band: band.band, "g")) })
                    .opacity(band.type.usesGain ? 1 : 0.35)
                    .allowsHitTesting(band.type.usesGain)

                Knob(title: "Q",
                     scale: .linear(0, 1),
                     wire: band.qWire,
                     tint: color,
                     format: { _ in XAirFormat.q(band.q) },
                     onChange: { wire in
                         // Q travels inverted on the wire; go through the setter
                         // so the inversion lives in exactly one place.
                         client.setEQQ(stripID, band: band.band, q: P.q(fromWire: wire))
                     },
                     onEnded: { client.endGesture(stripID.eqAddress(band: band.band, "q")) })
                    .opacity(band.type.isBell ? 1 : 0.35)
                    .allowsHitTesting(band.type.isBell)

                Spacer(minLength: 0)
            }
        }
        .panel()
    }
}

// MARK: - Curve

private struct EQCurve: View {
    let bands: [EQBandState]
    @Binding var selectedBand: Int
    let isEnabled: Bool
    let meters: MeterStore
    let onDrag: (Int, Double, Double) -> Void
    let onDragEnd: (Int) -> Void

    @State private var dragOrigin: (hz: Double, db: Double)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                grid(size: size)
                rta(size: size)
                curve(size: size)
                handles(size: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .well(Theme.Metric.cornerMedium)
    }

    /// The live spectrum, drawn faint behind the response curve. The desk's
    /// RTA bins are already log-spaced 20 Hz – 20 kHz, matching the x axis.
    private func rta(size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
            let bins = meters.rtaBins
            Canvas { context, canvasSize in
                guard bins.count > 1 else { return }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: canvasSize.height))
                for (i, db) in bins.enumerated() {
                    let x = CGFloat(i) / CGFloat(bins.count - 1) * canvasSize.width
                    // Spectrum floor at -80 dBFS up to the top of the plot.
                    let t = ((db + 80) / 80).clampedToUnit
                    let y = canvasSize.height * (1 - CGFloat(t))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
                path.closeSubpath()
                context.fill(path, with: .color(Theme.gold.opacity(0.13)))
                context.stroke(path, with: .color(Theme.gold.opacity(0.28)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Grid

    private func grid(size: CGSize) -> some View {
        let majorFrequencies: [Double] = [100, 1000, 10_000]
        let minorFrequencies: [Double] = [30, 50, 200, 300, 500, 2000, 3000, 5000, 15_000]
        let gains: [Double] = [12, 6, 0, -6, -12]

        return ZStack {
            ForEach(minorFrequencies, id: \.self) { hz in
                let x = EQAxis.x(forHz: hz, width: size.width)
                Rectangle()
                    .fill(Theme.stroke.opacity(0.5))
                    .frame(width: 1, height: size.height)
                    .position(x: x, y: size.height / 2)
            }
            ForEach(majorFrequencies, id: \.self) { hz in
                let x = EQAxis.x(forHz: hz, width: size.width)
                Rectangle()
                    .fill(Theme.strokeStrong)
                    .frame(width: 1, height: size.height)
                    .position(x: x, y: size.height / 2)
                Text(XAirFormat.frequency(hz))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .position(x: x + 14, y: size.height - 9)
            }
            ForEach(gains, id: \.self) { db in
                let y = EQAxis.y(forDB: db, height: size.height)
                Rectangle()
                    .fill(db == 0 ? Theme.strokeStrong : Theme.stroke.opacity(0.6))
                    .frame(width: size.width, height: db == 0 ? 1 : 0.5)
                    .position(x: size.width / 2, y: y)
                if db != 0 {
                    Text(String(format: "%+.0f", db))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: 14, y: y - 7)
                }
            }
        }
    }

    // MARK: Curve

    private func curve(size: CGSize) -> some View {
        let samples = 220
        var points: [CGPoint] = []
        points.reserveCapacity(samples)

        for i in 0..<samples {
            let x = CGFloat(i) / CGFloat(samples - 1) * size.width
            let hz = EQAxis.hz(forX: x, width: size.width)
            let db = bands.reduce(0.0) { $0 + $1.contribution(atHz: hz) }
            points.append(CGPoint(x: x, y: EQAxis.y(forDB: db, height: size.height)))
        }

        var line = Path()
        line.addLines(points)

        var fill = Path()
        fill.move(to: CGPoint(x: 0, y: EQAxis.y(forDB: 0, height: size.height)))
        fill.addLines(points)
        fill.addLine(to: CGPoint(x: size.width, y: EQAxis.y(forDB: 0, height: size.height)))
        fill.closeSubpath()

        return ZStack {
            fill.fill(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            line.stroke(
                isEnabled ? Theme.accent : Theme.textTertiary,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .opacity(isEnabled ? 1 : 0.45)
        .clipped()
    }

    // MARK: Handles

    private func handles(size: CGSize) -> some View {
        ForEach(bands) { band in
            let color = bandColors[(band.band - 1) % bandColors.count]
            let isSelected = band.band == selectedBand
            let x = EQAxis.x(forHz: band.frequencyHz, width: size.width)
            let y = EQAxis.y(forDB: band.type.usesGain ? band.gainDB : 0, height: size.height)

            ZStack {
                Circle()
                    .fill(color.opacity(isSelected ? 0.95 : 0.55))
                    .frame(width: isSelected ? 26 : 20, height: isSelected ? 26 : 20)
                    .overlay(
                        Circle().stroke(Color.white.opacity(isSelected ? 0.9 : 0.4),
                                        lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: color.opacity(0.6), radius: isSelected ? 7 : 3)
                Text("\(band.band)")
                    .font(Theme.label(11, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = (band.frequencyHz, band.gainDB)
                            selectedBand = band.band
                        }
                        guard let origin = dragOrigin else { return }

                        let originX = EQAxis.x(forHz: origin.hz, width: size.width)
                        let newHz = EQAxis.hz(forX: originX + value.translation.width,
                                              width: size.width)

                        let originY = EQAxis.y(forDB: origin.db, height: size.height)
                        let newDB = EQAxis.db(forY: originY + value.translation.height,
                                              height: size.height)
                            .clamped(to: -15...15)

                        onDrag(band.band, newHz, band.type.usesGain ? newDB : origin.db)
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onDragEnd(band.band)
                    }
            )
        }
    }
}
