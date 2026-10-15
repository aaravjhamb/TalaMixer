# TalaMixer

A custom iPad mixing surface for the Behringer XR18 (and the rest of the X-Air /
M-Air family), speaking the mixer's native OSC protocol over Wi-Fi.

## Running it

Open `TalaMixer.xcodeproj`, pick your iPad, and run. On first launch you'll get
the connection panel:

- **Found on this network** — the app broadcasts `/xinfo` and lists whatever
  answers. Tap to connect.
- **Enter an address** — the mixer's IP, if you'd rather be explicit.
- **Start demo desk** — a full XR18 simulated inside the app. Every control
  works and the meters move. Good for learning the layout, or checking the app
  on a plane.

iOS will ask for local network permission the first time. Without it, nothing
can reach the desk.

> Only one control app at a time gets smooth updates from an X-Air. Quit X AIR /
> Mixing Station before connecting.

## What's here

**Home** — serif greeting, the desk connection card with live main-LR meters,
and a grid of tool cards. Navigation is a floating pill tab bar:
Home / Mixer / Effects / Scenes / Tools.

**Mixer surface** — all 21 strips (16 channels, aux return, 4 FX returns, 6
buses, 4 FX sends, 4 DCAs, main LR) in one scrolling bank with the master pinned
right. ON/OFF and SOLO sit at the top of each strip. Mute groups (with a
membership editor), DCA mutes and quick-jump chips across the top.
Sends-on-fader: pick any mix or FX send from the selector and the bank flips to
that mix.

**Per channel** — name and colour, DCA and mute-group assignment, pan, LR
assign, automix; preamp (gain, 48 V, polarity, low cut, USB source and trim);
4-band parametric EQ with a draggable response curve (6-band plus a 31-band
graphic EQ on buses and LR); gate/expander and compressor with full sidechain;
all 10 bus and FX sends.

**Panels** — FX rack with named parameters for the common engines, the desk's
64 snapshots with app-side recall safes, routing and preamps, USB recorder with
a virtual-soundcheck shortcut, monitor/solo bus, an all-meters overview with a
live RTA, and an OSC inspector.

**Pro niceties** — RTA overlaid on every channel EQ, copy/paste of channel
processing between strips (scoped: everything / EQ / dynamics / sends), and
named channel presets (EQ + gate + comp) stored on the iPad.

## How it fits together

```
OSC/         OSC 1.0 codec, UDP transport, broadcast discovery
Protocol/    XR18 topology, parameter scales, enums, meter decoding
State/       Observable mirror of the desk, sharded per strip
Client/      Subscriptions, state sync, rate limiting, typed setters
Views/       SwiftUI surface
```

A few decisions worth knowing about:

- **Wire values, not decibels.** Every level is stored as the raw 0–1 float the
  desk uses. A round trip through the mixer is lossless, and fader travel matches
  the physical desk because the taper is the desk's own.
- **State is sharded per strip.** `StripState` is one `@Observable` object per
  strip, so a fader move invalidates one column instead of the whole bank.
- **Meters bypass observation entirely.** They arrive ~20×/second; `MeterStore`
  sits outside `@Observable` and meter views refresh from a `TimelineView`.
- **Outbound writes are coalesced** to 50 Hz per address, so a fader drag can't
  swamp the mixer.
- **Echoes are suppressed for 250 ms** after a local write, so the desk can't
  fight a finger mid-drag. Releasing re-queries the address to resync.
- **Sync is tiered.** Connecting pulls only what the bank draws (~400 addresses,
  paced so the desk doesn't drop replies). A channel's full parameter set is
  fetched when you open it.
- **Drags are relative.** Touching a fader never jumps the level to where your
  finger landed. Double-tap for unity; there's a haptic detent at 0 dB.

## Protocol status

Everything the mixer view and channel strip use is derived from confirmed X-Air
behaviour: `/ch/NN/…`, `/bus/N/…`, `/rtn/aux`, `/fxsend/N`, `/lr`, `/dca/N`,
`/headamp/NN`, `/config/mute/N`, the `/xremote` keep-alive, and `/meters/1`.
Note the addressing is deliberately inconsistent in the firmware — channels and
bus sends are zero-padded two digits, buses and DCAs are single digit, and the
aux return has no index at all.

These follow the X32 convention, which the X-Air is understood to share, but
could not be confirmed from a primary X-Air source:

| Area | Paths | Where to fix |
|---|---|---|
| Solo switches | `/-stat/solosw/NN`, `/-stat/clearsolo` | `XAirAddress.soloSwitch` / `soloIndex` |
| Scenes | `/-snap/load`, `/-snap/save`, `/-snap/NN/name` | `XAirAddress` snapshot section |
| USB recorder | `/-stat/tape/*` | `XAirAddress` tape section |
| FX engine names | index → name ordering | `XAirFXCatalog.unverifiedNames` |
| Input source, insert slot | value → source mapping | shown raw in the UI |

The **OSC Inspector** exists for exactly this. Turn logging on, query one of the
listed paths, and see whether the desk answers. Each is used in one place, so a
correction is a one-line edit. The FX view always shows the raw type index next
to the name, so a mismatch there is visible immediately.

Two things worth verifying on your desk before a show that depends on them:
saving a scene (recall is well established, saving less so), and the recorder
transport.

## Notes

- Deployment target is iOS 26.0. The template's 26.5 was lowered because no
  26.5 simulator runtime is installed here; it only widens compatibility.
- The screen is kept awake while a desk is connected.
- Landscape is the intended orientation, but portrait works.
