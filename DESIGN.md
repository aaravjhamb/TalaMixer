# TalaMixer design system

TalaMixer (project name `TalaMixer` internally) follows the Tala Shruti design language — warm near-black surfaces,
a single gold accent used sparingly, serif headings with italic lowercase
section labels — adapted to a professional mixing surface and aligned with
Apple's Human Interface Guidelines. Everything here is implemented in
`TalaMixer/Views/Theme.swift`; this document explains the intent and the
rules for extending it.

## Principles

1. **The desk is the interface.** The mixer surface borrows its geometry from
   hardware: fixed strip widths, a shared dB ruler, ON/SOLO where your thumbs
   expect them. Familiarity beats novelty on a live show.
2. **Gold means "look here".** One accent colour, used only for selection,
   activity and solo. If everything is gold, nothing is.
3. **Never surprise a live signal.** Drags are relative, taps never jump a
   fader, destructive states (OFF, mute) are red and unmistakable.
4. **Calm chrome, live content.** Surfaces are quiet and warm; the moving
   things (meters, fills, the status dot) carry the energy.

## Color

All colours are defined once in `Theme`. Never use raw `Color(red:…)` in a view.

### Surfaces

| Token | Value | Role |
|---|---|---|
| `background` | `#0D0B08` | App background |
| `surface` | `#191612` | Cards, panels, tab bar |
| `surfaceRaised` | `#25211B` | Buttons and chips resting on a card |
| `surfaceSunken` | `#070604` | Wells behind faders, meters, sliders |
| `stroke` / `strokeStrong` | gold @ 9% / 22% | Hairline card and chip borders |
| `cardFill` | vertical gradient, lighter above `surface` | Card fill: light falling from above |
| `cardEdge` | gold 22% → 4%, top to bottom | Card border, lit at the top by the same light |

Cards are never flat: `cardFill` + `cardEdge` + a soft black drop shadow is the
standard raised treatment (built into `.panel()`). A live/selected card may
swap `cardEdge` for a stronger gold gradient (45% → 10%). The launch screen
uses the `LaunchBackground` asset (same warm black as `background`) so launch
hands off seamlessly into the app.

### Text

| Token | Value | Contrast on `surface` | Use |
|---|---|---|---|
| `textPrimary` | `#F2EDDE` | 13.9:1 | Titles, values |
| `textSecondary` | `#A89E8A` | 6.8:1 | Labels, inactive controls |
| `textTertiary` | `#918A78` | 4.6:1 | Captions, hints — the floor; never dim further |

`textTertiary` is tuned to clear WCAG AA (≥4.5:1) on every surface tier. If a
new colour is added, verify contrast before shipping it.

### Semantics

| Token | Value | Meaning |
|---|---|---|
| `gold` | `#EDC76B` | Selection, accent, solo, activity |
| `goldSoft` | gold @ 16% | Medium-emphasis selected wash |
| `mute` | `#EB574D` | Channel OFF, mute groups, disconnect |
| `warning` | `#F29940` | Demo desk, sends-on-fader, gain reduction |
| `meterLow / meterMid / meterHigh` | green / gold / red | Absolute level bands: green to −18 dB, gold through −9, red above −2 |

Meter colours are anchored to absolute dB positions — a given colour always
means the same level, everywhere in the app.

On gold or red fills, text is `Color.black.opacity(0.85)`; never white.

## Typography

Two tiers, chosen by what the text is for:

**Reading text scales; mixing text doesn't.** Page titles, section labels,
descriptions and the onboarding flow use the scaling modifiers and follow the
user's Dynamic Type setting. The fader bank keeps fixed sizes because its
geometry is hardware-like and cannot reflow mid-show.

| Style | API | Face | Used for |
|---|---|---|---|
| Title | `.themeTitle(size)` | Serif, semibold | Page and card headings (scales) |
| Section label | `.themeSectionLabel(size)` | Serif italic, lowercase | "mixing tools", "the desk" (scales) |
| Body | `.themeBody(size)` | Sans, medium | Descriptions, help copy, subtitles (scales) |
| Label | `Theme.label(size)` | Sans, semibold | Control captions in fixed layouts |
| Value | `Theme.value(size)` | Sans, monospaced digits | dB readouts — digits don't jitter |
| Mono | `Theme.mono(size)` | Monospaced | IP addresses, OSC paths, the dB ruler |

Rules:
- Section labels are always lowercase serif italic; give them a proper
  `.accessibilityLabel` in normal case so VoiceOver doesn't inherit styling.
- 11 pt is the minimum for anything meant to be read. Smaller sizes are
  allowed only for decorative rulers/badges, which must be
  `.accessibilityHidden(true)`.
- No advisory-note boxes. Help copy is plain tertiary text under a section
  header, never a bordered callout.

## Layout

| Token | Value |
|---|---|
| Strip width / spacing | 96 / 8 pt |
| Corner radii | 18 (cards) · 13 (rows) · 9 (small controls); always `.continuous` |
| Card padding | 16–20 pt |
| Page margins | 22–24 pt horizontal |
| Tab bar clearance | 92 pt bottom padding on every tab page |

Containers: `.panel()` for a raised card, `.well()` for the recessed track
behind a fader/meter/slider. Don't hand-roll these.

## Components

All in `Views/Components/`. Reuse before inventing.

- **`OnButton` / `MixButton`** — strip switches. ON = gold wash, OFF = solid
  red with a glow. Expose `.isToggle` + on/off value to VoiceOver.
- **`ToggleChip`** — capsule chip; selected = gold pill, dark text. Pass
  `accessibilityLabel:` when the visible title is terse ("1" → "Mute group 1").
- **`SegmentedControl`** — pill track, gold pill selection, `.isSelected` trait.
- **`ParameterSlider` / `Knob`** — relative-drag continuous controls with
  double-tap reset and VoiceOver adjustable actions (2% wire steps).
- **`VerticalFader`** — relative drag, 0 dB haptic detent, double-tap to
  unity; VoiceOver adjusts in 1 dB steps and speaks "−3.0 dB, muted".
- **`RoundIconButton`** — icon-only, so `label:` is required; hit area padded
  to 44 pt regardless of visual size.
- **`MeterBar` family** — hidden from VoiceOver (20 Hz updates are noise);
  levels are spoken by the owning fader instead.
- **`SectionHeader`**, **`Badge`**, **`ChipGrid`**, **`PageScaffold`** /
  **`PanelScaffold`** — page chrome. Scaffold titles carry `.isHeader`.

## Simplified mode

Simplified is also the free tier: full mode is a StoreKit auto-renewable
subscription (`LicenseStore`), and while unlicensed the app behaves as if the
SIMPLE chip were locked on — views gate on `simplified || !license.isFull`.

A persisted toggle (`@AppStorage("simplifiedMode")`, the SIMPLE chip on Home)
that strips the surface down to what a stand-in operator needs: Home and
Mixer tabs only, strips widened to 124 pt, ON/OFF and fader — no solo, no
DCA/mute-group row, no effects or snapshots pages. The bank keeps inputs,
returns and the mix masters (wedge/IEM/FX levels); only DCAs are hidden. The
mix / FX send selector stays (relabelled "listening to"), because adjusting
wedges and effect sends is what the iPad gets handed over for. Every strip's
simple sheet can rename it (channels and mixes alike). Tapping a channel opens
`SimpleChannelView` instead of the full detail: input gain, a three-knob
low/mid/high EQ (first, middle and last parametric bands), one-knob
compressor and gate, and a "mixes" list — one slider per monitor/FX send
(gold for wedges and IEMs, amber for effects). The one-knob convention: the
knob is *amount*, zero switches the block off. Views read the flag
themselves; anything advanced a new view adds should hide behind
`!simplified`.

## Interaction

- **Relative drags everywhere.** Touching a control never jumps its value.
- **Haptics**: `Haptics.tap()` on every switch press; `Haptics.detent()` at
  0 dB and on double-tap resets. Nothing else vibrates.
- **Press feedback**: cards and large buttons use the `Pressable` button style
  (settles to 98% with a short spring). Strip switches stay instant — they're
  hardware buttons, not cards.
- **Motion**: springs on value snaps (`interpolatingSpring`) and the tab bar's
  gold pill, which slides between tabs via `matchedGeometryEffect`. Meters and
  fills move by data, not animation.
- **Hit targets**: 44×44 pt minimum, via `.minimumHitTarget()` when the visual
  is smaller. Exception: strip controls (96 pt wide × 30 pt tall) trade height
  for density, like the hardware they mirror.

## Accessibility checklist for new views

- Icon-only buttons have `.accessibilityLabel`.
- Toggles expose `.isToggle` + `accessibilityValue`; selections `.isSelected`.
- Continuous controls implement `.accessibilityAdjustableAction` and speak
  real units (dB, Hz, ms), not wire values.
- Decorative dots, rulers and live meters are `.accessibilityHidden(true)`;
  status is spoken as part of a combined element.
- Reading text uses the scaling modifiers; verify at AX3 that nothing clips.
- Text meets 4.5:1 on its actual background; stay within the `Theme` tokens
  and this is automatic.
