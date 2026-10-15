//
//  Controls.swift
//  TalaMixer
//
//  Shared controls. Every continuous control drags *relatively* — a touch never
//  jumps a value to where the finger landed. On a live desk that distinction is
//  the difference between a nudge and an accident.
//

import SwiftUI

// MARK: - Buttons

/// The channel ON switch. Lit gold-washed when the strip is passing audio,
/// solid red when it's off — like the ON button on a hardware desk.
struct OnButton: View {
    let isOn: Bool
    /// Muted by a mute group rather than its own switch.
    var isDimmed: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(isOn ? "ON" : "OFF")
                .font(Theme.label(11, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(isOn ? Theme.gold : Color.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .fill(isOn ? Theme.goldSoft : Theme.mute)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                                .stroke(isOn ? Theme.gold.opacity(0.55) : Theme.mute, lineWidth: 1)
                        )
                        .shadow(color: isOn ? .clear : Theme.mute.opacity(0.45), radius: 6)
                )
                .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Channel on")
        .accessibilityValue(isDimmed ? "muted by group" : (isOn ? "on" : "off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// The chunky SOLO-style button on a fader strip.
struct MixButton: View {
    let title: String
    let isOn: Bool
    var tint: Color
    var isDimmed: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(Theme.label(11, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                        .fill(isOn ? tint : Theme.surfaceRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall, style: .continuous)
                                .stroke(isOn ? tint : Theme.stroke, lineWidth: 1)
                        )
                        .shadow(color: isOn ? tint.opacity(0.5) : .clear, radius: 6)
                )
                .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A compact on/off chip. Selected = gold pill with dark text, as in Tala Shruti.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var tint: Color = Theme.gold
    var width: CGFloat?
    /// Stretch to fill the available width. Set this inside a grid, where
    /// intrinsic sizing leaves ragged gaps between cells.
    var expands: Bool = false
    /// Spoken name when the visible title is too terse for VoiceOver ("1").
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(Theme.label(12, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 13)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(width: width)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isOn ? tint : Theme.surfaceRaised)
                        .overlay(Capsule().stroke(isOn ? tint.opacity(0.9) : Theme.stroke, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A segmented picker in the Tala style: pill track, gold pill for selection.
struct SegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        var label: String
        var id: Value { value }
    }

    let options: [Option]
    let selection: Value
    var tint: Color = Theme.gold
    var onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    Haptics.tap()
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                        .font(Theme.label(12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            Capsule().fill(isSelected ? tint : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Theme.surfaceSunken)
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        )
    }
}

// MARK: - Continuous controls

/// A labelled horizontal parameter slider, gold-filled like Tala's tempo slider.
struct ParameterSlider: View {
    let title: String
    let scale: XAirScale
    let wire: Double
    var tint: Color = Theme.gold
    var format: (Double) -> String
    /// Where a double-tap sends the value.
    var resetWire: Double?
    /// Draw the fill outward from the centre — right for gain-style parameters.
    var bipolar: Bool = false
    var onChange: (Double) -> Void
    var onEnded: () -> Void = {}

    @State private var dragOrigin: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text(format(scale.value(fromWire: wire)))
                    .font(Theme.value(12))
                    .foregroundStyle(Theme.textPrimary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let position = CGFloat(wire.clampedToUnit) * w

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceSunken)
                        .frame(height: 4)
                        .overlay(Capsule().stroke(Color.black.opacity(0.4), lineWidth: 0.5))

                    if bipolar {
                        let centre = w / 2
                        Capsule()
                            .fill(tint)
                            .frame(width: abs(position - centre), height: 4)
                            .offset(x: min(position, centre))
                        Rectangle()
                            .fill(Theme.textTertiary.opacity(0.6))
                            .frame(width: 1, height: 10)
                            .offset(x: w / 2)
                    } else {
                        Capsule()
                            .fill(tint)
                            .frame(width: position, height: 4)
                    }

                    Circle()
                        .fill(tint)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .offset(x: min(w - 18, max(0, position - 9)))
                }
                .frame(height: 24)
                .overlay(
                    AxisLockedPan(
                        axis: .horizontal,
                        onChanged: { translation in
                            let origin = dragOrigin ?? wire
                            if dragOrigin == nil { dragOrigin = origin }
                            let delta = Double(translation.width) / Double(max(1, w))
                            onChange((origin + delta).clampedToUnit)
                        },
                        onEnded: {
                            dragOrigin = nil
                            onEnded()
                        },
                        onDoubleTap: {
                            guard let resetWire else { return }
                            Haptics.detent()
                            onChange(resetWire)
                            onEnded()
                        }
                    )
                )
            }
            .frame(height: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(scale.value(fromWire: wire)))
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            switch direction {
            case .increment: onChange((wire + step).clampedToUnit)
            case .decrement: onChange((wire - step).clampedToUnit)
            @unknown default: return
            }
            onEnded()
        }
    }
}

/// A rotary control.
///
/// Responds to drag on both axes (up or right raises the value) so it stays
/// usable inside a vertically scrolling page — a purely vertical drag gesture
/// fights the scroll view. `minimumDistance` is non-zero for the same reason.
struct Knob: View {
    let title: String
    let scale: XAirScale
    let wire: Double
    var tint: Color = Theme.gold
    var format: (Double) -> String
    var resetWire: Double?
    var diameter: CGFloat = 64
    var onChange: (Double) -> Void
    var onEnded: () -> Void = {}

    @State private var dragOrigin: Double?

    /// 270° of sweep, opening at the bottom: 7:30 through 12:00 to 4:30.
    private let sweep: Double = 0.75
    /// Rotation for the arcs. A `Circle` trim starts at 3 o'clock, so 135°
    /// clockwise puts the start of travel at 7:30.
    private let arcRotation: Double = 135
    /// The pointer starts life aimed at 12 o'clock, so it needs the sweep
    /// centred on that instead.
    private let pointerStart: Double = -135
    private let pointerSweep: Double = 270

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceSunken)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))

                // Track arc
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Theme.surfaceRaised, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(arcRotation))
                    .padding(5)

                // Value arc
                Circle()
                    .trim(from: 0, to: sweep * wire.clampedToUnit)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(arcRotation))
                    .padding(5)

                // Pointer
                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: 2.5, height: diameter * 0.24)
                    .offset(y: -diameter * 0.20)
                    .rotationEffect(.degrees(pointerStart + pointerSweep * wire.clampedToUnit))

                Circle()
                    .fill(
                        LinearGradient(colors: [Color(red: 0.20, green: 0.18, blue: 0.14),
                                                Color(red: 0.11, green: 0.10, blue: 0.08)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .padding(diameter * 0.28)
                    .overlay(
                        Circle().stroke(Theme.stroke, lineWidth: 1)
                            .padding(diameter * 0.28)
                    )
            }
            .frame(width: diameter, height: diameter)
            .overlay(
                // Drag sideways to turn — a vertical drag scrolls the page.
                // Once engaged, both axes contribute so diagonals feel natural.
                AxisLockedPan(
                    axis: .horizontal,
                    onChanged: { translation in
                        let origin = dragOrigin ?? wire
                        if dragOrigin == nil { dragOrigin = origin }
                        let delta = (Double(translation.width)
                                     - Double(translation.height)) / 260
                        onChange((origin + delta).clampedToUnit)
                    },
                    onEnded: {
                        dragOrigin = nil
                        onEnded()
                    },
                    onDoubleTap: {
                        guard let resetWire else { return }
                        Haptics.detent()
                        onChange(resetWire)
                        onEnded()
                    }
                )
                .clipShape(Circle())
            )

            VStack(spacing: 1) {
                Text(format(scale.value(fromWire: wire)))
                    .font(Theme.value(12))
                    .foregroundStyle(Theme.textPrimary)
                Text(title.lowercased())
                    .font(Theme.sectionLabel(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(scale.value(fromWire: wire)))
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            switch direction {
            case .increment: onChange((wire + step).clampedToUnit)
            case .decrement: onChange((wire - step).clampedToUnit)
            @unknown default: return
            }
            onEnded()
        }
    }
}

// MARK: - Layout helpers

/// A wrapping grid of equal-width chips.
struct ChipGrid<Content: View>: View {
    var columns: Int
    var spacing: CGFloat = 7
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            content
        }
    }
}

/// A read-only badge, e.g. the raw index beside an FX name.
struct Badge: View {
    let text: String
    var tint: Color = Theme.textTertiary

    var body: some View {
        Text(text)
            .font(Theme.mono(9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}

/// A round icon button in the Tala style: dark circle, gold glyph.
///
/// Icon-only, so `label` is required for VoiceOver. The tappable area is
/// padded out to 44 pt even when the visible circle is smaller.
struct RoundIconButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 36
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.8) : Theme.gold)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(prominent ? Theme.gold : Theme.surfaceRaised)
                        .overlay(Circle().stroke(prominent ? Theme.gold : Theme.stroke, lineWidth: 1))
                )
                .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
