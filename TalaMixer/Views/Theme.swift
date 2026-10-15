//
//  Theme.swift
//  TalaMixer
//
//  The visual language, matched to Tala Shruti: warm near-black surfaces, a
//  single gold accent used sparingly, serif headings with italic lowercase
//  section labels, and generous, calm spacing.
//
//  The full design system — palette contrast ratios, type scale, component
//  rules, accessibility requirements — is documented in DESIGN.md.
//

import SwiftUI

enum Theme {

    // MARK: Surfaces

    /// Warm near-black.
    static let background = Color(red: 0.051, green: 0.045, blue: 0.033)
    static let surface = Color(red: 0.098, green: 0.088, blue: 0.070)
    static let surfaceRaised = Color(red: 0.145, green: 0.130, blue: 0.104)
    static let surfaceSunken = Color(red: 0.028, green: 0.025, blue: 0.018)

    static let stroke = Color(red: 0.93, green: 0.78, blue: 0.42).opacity(0.09)
    static let strokeStrong = Color(red: 0.93, green: 0.78, blue: 0.42).opacity(0.22)

    // MARK: Text

    static let textPrimary = Color(red: 0.95, green: 0.93, blue: 0.87)
    static let textSecondary = Color(red: 0.66, green: 0.62, blue: 0.54)
    /// Lightest text that still clears WCAG AA (≥4.5:1) on every surface tier.
    static let textTertiary = Color(red: 0.57, green: 0.54, blue: 0.47)

    // MARK: Semantics

    /// The gold. Selected states, accents, solo.
    static let gold = Color(red: 0.93, green: 0.78, blue: 0.42)
    /// A dim gold wash for medium-emphasis selected states.
    static let goldSoft = gold.opacity(0.16)

    static let accent = gold
    static let mute = Color(red: 0.92, green: 0.34, blue: 0.30)
    static let solo = gold
    static let active = gold
    static let warning = Color(red: 0.95, green: 0.60, blue: 0.25)

    // MARK: Metering

    static let meterLow = Color(red: 0.42, green: 0.76, blue: 0.45)
    static let meterMid = gold
    static let meterHigh = Color(red: 0.94, green: 0.36, blue: 0.28)

    // MARK: Metrics

    enum Metric {
        static let stripWidth: CGFloat = 96
        static let stripSpacing: CGFloat = 8
        static let cornerLarge: CGFloat = 18
        static let cornerMedium: CGFloat = 13
        static let cornerSmall: CGFloat = 9
        static let faderCapHeight: CGFloat = 34
        static let scaleColumnWidth: CGFloat = 34
        /// Clearance for the floating tab bar at the bottom of tab pages.
        static let tabBarClearance: CGFloat = 92
    }

    // MARK: Type

    /// Serif display type, as in Tala Shruti's headings.
    static func title(_ size: CGFloat = 26, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The italic lowercase section label ("practice tools").
    static func sectionLabel(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }

    static func label(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func value(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Dynamic Type

/// A system font that tracks the user's Dynamic Type setting.
///
/// The static `Theme` fonts above are fixed-size on purpose: the fader bank is
/// laid out like a hardware desk, where geometry (strip width, cap height, the
/// dB ruler) can't reflow. Everything that *reads* rather than *mixes* — page
/// titles, section labels, descriptions, the onboarding flow — uses these
/// scaling modifiers instead.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let italic: Bool

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         relativeTo style: Font.TextStyle,
         italic: Bool = false) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.italic = italic
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        content.font(italic ? font.italic() : font)
    }
}

extension View {
    /// Serif display type that scales with Dynamic Type.
    func themeTitle(_ size: CGFloat = 26, weight: Font.Weight = .semibold) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: .serif, relativeTo: .title2))
    }

    /// The italic lowercase serif section label, scaling.
    func themeSectionLabel(_ size: CGFloat = 13) -> some View {
        modifier(ScaledSystemFont(size: size, weight: .regular, design: .serif,
                                  relativeTo: .subheadline, italic: true))
    }

    /// Reading text — descriptions, help copy, subtitles — scaling.
    func themeBody(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: .default, relativeTo: .footnote))
    }
}

// MARK: - Hit targets

extension View {
    /// Guarantees the HIG-minimum 44×44 pt touch target without growing the
    /// visual footprint of a small control.
    func minimumHitTarget() -> some View {
        self
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Reusable surface treatments

extension Theme {
    /// Card fill: a whisper of light falling from above, so surfaces read as
    /// physical panels rather than flat rectangles.
    static let cardFill = LinearGradient(
        colors: [Color(red: 0.128, green: 0.115, blue: 0.090), surface],
        startPoint: .top, endPoint: .bottom
    )

    /// Card edge: lit at the top, falling away to nothing — the same light.
    static let cardEdge = LinearGradient(
        colors: [gold.opacity(0.22), gold.opacity(0.04)],
        startPoint: .top, endPoint: .bottom
    )
}

extension View {
    /// A raised card: the default container for a group of controls.
    func panel(_ corner: CGFloat = Theme.Metric.cornerLarge, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Theme.cardEdge, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
            )
    }

    /// A recessed well — used behind faders, meters and sliders.
    func well(_ corner: CGFloat = Theme.Metric.cornerSmall) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Theme.surfaceSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section header

/// Italic lowercase serif, the way Tala Shruti labels its sections.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var accessory: AnyView?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = nil
    }

    init<A: View>(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> A) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.lowercased())
                .themeSectionLabel()
                .foregroundStyle(Theme.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(title)
            if let subtitle {
                Text(subtitle)
                    .themeBody(11)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if let accessory { accessory }
        }
    }
}

// MARK: - Press feedback

/// Cards and big buttons settle slightly under the finger — the whole app
/// feels touchable instead of painted on.
struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75),
                       value: configuration.isPressed)
    }
}

// MARK: - Haptics

/// Light touch feedback for detents and switch presses. No-ops where the
/// hardware can't do it.
enum Haptics {
    #if canImport(UIKit)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    static func detent() {
        #if canImport(UIKit)
        rigid.impactOccurred(intensity: 0.6)
        #endif
    }

    static func tap() {
        #if canImport(UIKit)
        light.impactOccurred(intensity: 0.5)
        #endif
    }
}
