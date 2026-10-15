//
//  Meter.swift
//  TalaMixer
//
//  Level metering.
//
//  Meters update ~20×/second. Driving that through `@Observable` would
//  invalidate the whole mixer on every frame, so `MeterStore` sits outside
//  observation and these views refresh themselves from a `TimelineView`.
//

import SwiftUI

/// A single meter column. The colour gradient is anchored to absolute dB
/// positions and then masked, so a given colour always means the same level.
struct MeterBar: View {
    var db: Double
    var peakDB: Double = MeterFrame.floorDB
    var width: CGFloat = 6
    var showsPeak: Bool = true

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let fill = CGFloat(XAirMeterScale.position(forDB: db)) * height
            let peak = CGFloat(XAirMeterScale.position(forDB: peakDB)) * height

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.surfaceSunken)

                // Full-height gradient, revealed only up to the current level.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.gradient)
                    .frame(height: height)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: fill)
                    }

                if showsPeak, peakDB > MeterFrame.floorDB + 1 {
                    Rectangle()
                        .fill(peakDB >= -0.6 ? Theme.meterHigh : Color.white.opacity(0.85))
                        .frame(height: 1.5)
                        .offset(y: -min(height - 1.5, max(0, peak)))
                }
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(width: width)
        // Refreshes ~20×/s; exposing that to VoiceOver would be pure noise.
        // Levels are readable from each strip's fader element instead.
        .accessibilityHidden(true)
    }

    /// Green to about -18 dB, amber through -6, red at the top.
    private static let gradient = LinearGradient(
        stops: [
            .init(color: Theme.meterLow, location: 0),
            .init(color: Theme.meterLow, location: XAirMeterScale.position(forDB: -18)),
            .init(color: Theme.meterMid, location: XAirMeterScale.position(forDB: -9)),
            .init(color: Theme.meterHigh, location: XAirMeterScale.position(forDB: -2)),
            .init(color: Theme.meterHigh, location: 1),
        ],
        startPoint: .bottom, endPoint: .top
    )
}

/// A meter that keeps itself refreshed from the store.
struct LiveMeter: View {
    let store: MeterStore
    let index: Int?
    var rightIndex: Int?
    var width: CGFloat = 6
    var refreshRate: Double = 24

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / refreshRate)) { _ in
            HStack(spacing: 2) {
                MeterBar(db: store.level(at: index),
                         peakDB: store.peak(at: index),
                         width: width)
                if let rightIndex {
                    MeterBar(db: store.level(at: rightIndex),
                             peakDB: store.peak(at: rightIndex),
                             width: width)
                }
            }
        }
    }
}

/// A compact horizontal level readout, used on the preamp page.
struct HorizontalMeter: View {
    var db: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let fill = CGFloat(XAirMeterScale.position(forDB: db)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSunken)
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Theme.meterLow, location: 0),
                                .init(color: Theme.meterLow, location: XAirMeterScale.position(forDB: -18)),
                                .init(color: Theme.meterMid, location: XAirMeterScale.position(forDB: -9)),
                                .init(color: Theme.meterHigh, location: XAirMeterScale.position(forDB: -2)),
                                .init(color: Theme.meterHigh, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width)
                    .mask(alignment: .leading) { Rectangle().frame(width: fill) }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Gain-reduction style readout for the dynamics page, drawn right-to-left.
struct ReductionMeter: View {
    /// 0 = no reduction, 1 = fully closed.
    var amount: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Capsule().fill(Theme.surfaceSunken)
                Capsule()
                    .fill(Theme.warning.opacity(0.85))
                    .frame(width: geo.size.width * CGFloat(amount.clampedToUnit))
            }
        }
        .frame(height: height)
    }
}
