//
//  Fader.swift
//  TalaMixer
//
//  The vertical fader.
//
//  Two deliberate behaviours:
//   • Dragging is *relative* to where the finger landed, not absolute. Tapping
//     a fader can therefore never jump the level — which matters when the desk
//     is live and the tap was meant for a different strip.
//   • Travel is linear in the wire value, exactly like the physical desk, so the
//     printed dB scale is non-linear in the same way theirs is.
//

import SwiftUI

/// Shared geometry so the fader and its dB scale line up exactly.
enum FaderGeometry {
    static let capHeight: CGFloat = Theme.Metric.faderCapHeight

    static func travel(in height: CGFloat) -> CGFloat {
        max(1, height - capHeight)
    }

    /// Vertical centre of the cap for a given wire value.
    static func y(forWire wire: Double, in height: CGFloat) -> CGFloat {
        (1 - CGFloat(wire.clampedToUnit)) * travel(in: height) + capHeight / 2
    }
}

struct VerticalFader: View {
    var wire: Double
    var tint: Color
    var isMuted: Bool = false
    var isEnabled: Bool = true
    /// Spoken name for VoiceOver — the strip this fader belongs to.
    var accessibilityLabel: String = "Fader"

    var onChange: (Double) -> Void
    var onEnded: () -> Void = {}

    /// How close to unity counts as "at unity" for the detent.
    private let detentWindow = 0.011

    @State private var dragOrigin: Double?
    @State private var isDetented = false
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let capY = FaderGeometry.y(forWire: wire, in: height)
            let unityY = FaderGeometry.y(forWire: XAirScale.unityWire, in: height)
            // The track is inset so its ends sit under the cap's travel extremes.
            let trackInset = FaderGeometry.capHeight / 2 - 4
            let fillHeight = max(0, (height - trackInset) - capY)

            ZStack(alignment: .top) {
                // Track
                Capsule()
                    .fill(Theme.surfaceSunken)
                    .overlay(Capsule().stroke(Color.black.opacity(0.55), lineWidth: 1))
                    .frame(width: 9)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, trackInset)

                // Level fill: from the bottom of travel up to the cap.
                //
                // Bottom-aligned rather than offset — `.offset` is a render-time
                // transform, so clipping an offset view cuts it at the original
                // layout frame and the fill comes up short.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isMuted
                                    ? [Theme.mute.opacity(0.30), Theme.mute.opacity(0.55)]
                                    : [tint.opacity(0.55), tint],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 9, height: fillHeight)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, trackInset)
                .opacity(isEnabled ? 1 : 0.35)

                // Unity mark
                Rectangle()
                    .fill(Theme.textTertiary.opacity(0.7))
                    .frame(width: width * 0.5, height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: unityY)

                // Cap
                FaderCap(tint: isMuted ? Theme.mute : tint,
                         isDragging: isDragging,
                         isDetented: isDetented)
                    .frame(width: width, height: FaderGeometry.capHeight)
                    .offset(y: capY - FaderGeometry.capHeight / 2)
                    .animation(isDragging ? nil : .interpolatingSpring(stiffness: 320, damping: 26),
                               value: wire)
            }
            .frame(width: width, height: height)
            .overlay(
                // Vertical drags move the fader; a horizontal drag genuinely
                // fails the recognizer, so the bank scrolls instead.
                AxisLockedPan(
                    axis: .vertical,
                    onChanged: { translation in handleDrag(translation, height: height) },
                    onEnded: {
                        dragOrigin = nil
                        isDragging = false
                        isDetented = false
                        onEnded()
                    },
                    onDoubleTap: { snapToUnity() }
                )
            )
            .allowsHitTesting(isEnabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(XAirFormat.decibelsWithUnit(XAirScale.faderDecibels(fromWire: wire))
                            + (isMuted ? ", muted" : ""))
        .accessibilityAdjustableAction { direction in
            // ±1 dB per step near unity; the wire taper makes low levels coarser,
            // matching how the physical fader travels.
            let db = XAirScale.faderDecibels(fromWire: wire)
            switch direction {
            case .increment: onChange(XAirScale.wire(fromFaderDecibels: min(10, db + 1)))
            case .decrement: onChange(XAirScale.wire(fromFaderDecibels: max(-90, db - 1)))
            @unknown default: return
            }
            onEnded()
        }
    }

    private func handleDrag(_ translation: CGSize, height: CGFloat) {
        let origin = dragOrigin ?? wire
        if dragOrigin == nil {
            dragOrigin = origin
            isDragging = true
        }

        let travel = FaderGeometry.travel(in: height)
        let delta = -Double(translation.height) / Double(travel)
        var next = (origin + delta).clampedToUnit

        // Detent at unity so 0 dB is findable without looking.
        if abs(next - XAirScale.unityWire) < detentWindow {
            next = XAirScale.unityWire
            if !isDetented {
                isDetented = true
                Haptics.detent()
            }
        } else {
            isDetented = false
        }

        onChange(next)
    }

    private func snapToUnity() {
        Haptics.detent()
        onChange(XAirScale.unityWire)
        onEnded()
    }
}

// MARK: - Cap

private struct FaderCap: View {
    let tint: Color
    let isDragging: Bool
    let isDetented: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.34), Color(white: 0.17)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isDragging ? tint.opacity(0.9) : Color.white.opacity(0.22),
                            lineWidth: isDragging ? 2 : 1)
            )
            .overlay(
                // The grip line, tinted so the strip colour reads at a glance.
                Capsule()
                    .fill(tint)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
                    .shadow(color: tint.opacity(isDetented ? 0.9 : 0.45), radius: isDetented ? 6 : 3)
            )
            .shadow(color: .black.opacity(0.55), radius: isDragging ? 8 : 4, y: 2)
    }
}

// MARK: - dB scale

/// The shared dB ruler drawn once beside the bank rather than per strip.
struct FaderScale: View {
    private let marks: [Double] = [10, 5, 0, -5, -10, -20, -30, -40, -60]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ForEach(marks, id: \.self) { db in
                    let y = FaderGeometry.y(forWire: XAirScale.wire(fromFaderDecibels: db),
                                            in: geo.size.height)
                    HStack(spacing: 3) {
                        Text(db == 0 ? "0" : String(format: "%.0f", db))
                            .font(Theme.mono(9))
                            .foregroundStyle(db == 0 ? Theme.textSecondary : Theme.textTertiary)
                        Rectangle()
                            .fill(db == 0 ? Theme.textSecondary : Theme.textTertiary.opacity(0.6))
                            .frame(width: db == 0 ? 7 : 4, height: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: y - 5)
                }

                Text("-∞")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: geo.size.height - FaderGeometry.capHeight / 2 - 5)
            }
        }
        .frame(width: Theme.Metric.scaleColumnWidth)
        // Decorative ruler; fader values are spoken by the faders themselves.
        .accessibilityHidden(true)
    }
}
