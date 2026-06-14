# Golden Gate UI — native SwiftUI rewrite

A native SwiftUI rewrite of the KisMAC interface, themed after the macOS
"Golden Gate" (Tahoe / Liquid Glass) dark redesign: a unified glass toolbar
with a leading segmented switcher (Networks / Details / Graph / Map), a green→red
Scan capsule, and a bottom status bar. Dark appearance only.

## Status

**Stage 1 — shell + integration: DONE.**

- Design system, data model + seed + 1100ms scanning engine, shared atoms, the
  window shell (toolbar / segmented switcher / status bar), and stub content views.
- Swift enabled in the `KisMac2` app target; the SwiftUI window is hosted in an
  AppKit `NSWindow` and opened from the existing Obj-C startup via a Window-menu item.

**Stage 2 — Networks + Details views: DONE.**

- `GGNetworksView` — scrolling table (`ScrollView` + `LazyVStack`) with a sticky
  header, zebra striping, hover, accent selection (soft bg + inset accent bar),
  and a "fresh" green flash when a row's `lastSeen` updates during a scan. SSID
  cell shows a lock icon + hidden-italic styling; signal column animates
  `GGSignalBars` + a dBm value; `GGEncPill` for encryption; packets/bytes are
  right-aligned tabular; a live Ch/Re dot tracks `lastSeenLive`. Rows filter by
  `state.searchQuery` (via `filteredNetworks`) and a tap sets `selectedID` +
  switches to `.details`, matching the shell's routing.
- `GGDetailsView` — split layout (inspector ~46%, min 360pt, via `GeometryReader`):
  accent rounded-icon header + SSID title + mono BSSID sub; scrollable property
  groups (Identity / Signal / Packets) of uppercased headings + `PropRow` k/v;
  and a comment box (NSTextView-backed `GGCommentEditor`) bound through
  `state.setComment`. Right side is the clients panel — a header count + a
  clients table (MAC mono / vendor / `GGSignalBars` / sent / recv / IP / last)
  or an empty-state when none.
- Both reuse `GGSignalBars` / `GGEncPill` from `GGComponents`, the
  `signalColor` / `dbm` mappers + ink/hairline/panel tokens from `GGTheme`, and
  `GGFormat` (num / bytes / relTime). The two Stage-1 stubs were removed from
  `GGStubViews.swift`.

**Stage 3 — Graph + Map views: DONE.**

- `GGGraphView` — rolling multi-series line chart drawn with SwiftUI `Canvas`:
  grid + baseline + mono axis labels (left = 0..100×unit-mul, bottom = `-Ns`/`now`),
  one consistently-colored line per network (top-5 by signal, `GGGraphPalette`),
  a filled area + glow under each line + a leading-edge dot, and a wrapping
  legend (custom `GGFlowLayout`) of swatch + SSID above. A per-network rolling
  sample buffer (`[Int: [Double]]`, keyed by network id) is seeded from
  `avgSignal` and advanced by a `Timer` gated on `state.isScanning` at the same
  1.1s cadence as the model tick; each advance does a clamped random-walk blended
  toward the network's baseline signal and trims to the selected window's sample
  count (15s/30s/60s/5min → ~14/27/55/273 samples). Static when idle. Unit
  Bytes/Packets only scales the axis labels (the seed model has no per-second
  byte/packet series), matching the design.
- `GGMapView` — radar map `ZStack`: dark radial bg, a faint 60px blue grid
  (`Canvas`), three blurred green-tinted landmass blobs, AP markers projected
  from lat/lng around the GPS center (`SCALE = 16000` px/deg), signal-colored via
  `GGTheme.signalColor` with a radius scaled by signal and a white outline when
  selected; while scanning each marker gets a pulsing expanding ring
  (`GGMarkerRing`, 2.4s) and a rotating conic `AngularGradient` sweep (4s linear)
  plays over faint concentric rings. A glowing GPS dot sits at center. A glass
  HUD bottom-left (`.ultraThinMaterial`, mono Position/Elevation/Time with the
  clock advancing 1s/tick while scanning), a 3-col glass zoom/pan cluster
  bottom-right driving `zoom`/`pan` state, and a top-left legend. Tapping a
  marker sets `selectedID` + switches to `.details` (same routing as Networks).
- Both reuse `GGTheme` tokens + `signalColor`, `GGAppState` (graphUnit /
  graphWindow / isScanning / networks / gps), and the dark-glass aesthetic. The
  two stubs were removed from `GGStubViews.swift`.

**Stage 4 — Preferences (8 tabs): DONE.**

- `GGPreferencesView` — a glass floating panel presented as an overlay over the
  main content (dim backdrop + `.prefs-win` glass card with a `prefIn`-style
  scale/offset/opacity entrance). A title bar (traffic lights — the red dot
  closes — + a centered "KisMAC Preferences") sits above a single-row 8-tab
  toolbar (`.ptab` icon-over-label, active = accent fill), then a scrollable body
  switching content per selected tab. Closing clears `state.showPreferences`
  (red traffic light, or the backdrop tap wired in `GGRootView`).
- **All 8 tabs** implemented faithfully to `prefs.jsx`:
  - **Scanning** — "Capture Engine" section label, a group-card of three
    toggle-rows (active driver scanning / hop channels / keep everything, with
    sub-descriptions), divider, then a Dwell-time select.
  - **Filter** — the BSSID list (centered header, 190pt scroll area with zebra
    rows + accent selection, or an empty-state), plus the actions row: a
    `remove` button (disabled until a row is selected), a mono text input, and an
    `add` button. Add validates the `xx:xx:xx:xx:xx:xx` MAC regex and dedupes
    (upper-cased); remove drops the selected row.
  - **Sounds** — a 2-col field grid (WEP on/off sounds, play-every stepper +
    sound select, speak-SSIDs voice), divider, and a `GGCheck` with a long
    description.
  - **Driver** — capture-device select, channels mono text input, and an
    injection toggle-row group-card.
  - **GPS** — 3-field grid (device / baud / trace color), divider, reconnect
    toggle-row.
  - **Map** — map-source + default-zoom selects, divider, show-waypoints /
    color-by-signal toggle-rows.
  - **Traffic** — measure + time-window selects, divider, stack-series toggle-row.
  - **General** — "General Options" section label, a padded group-card with two
    `GGCheck`s (don't ask to save / terminate on main-window close).
- **Reusable controls** built in the same file: `GGSwitch` (42×25 track + 20pt
  knob, accent when on, spring animation), `GGCheck` (22pt rounded checkbox +
  title + optional small desc), `GGSelect` (Menu popup with the accent
  up/down chevron), a stepper box (numeric-filtered `TextField`), `GGField`
  (label-over-control), `GGGroupCard`, `GGToggleRow`, `GGSectionLabel`,
  `GGPrefDivider`. All reuse `GGTheme` tokens + fonts.
- **Prototype caveat:** field values live in a local `GGPrefsState`
  (`ObservableObject` of `@Published` values) and are **not** persisted to
  `NSUserDefaults` — this matches the design prototype's `useState` behavior.
- The Stage-1 Preferences stub was removed from `GGStubViews.swift` (that file is
  now an empty placeholder kept only to preserve target membership).

The full Golden Gate UI — all five content views (Networks / Details / Graph /
Map) **plus** the 8-tab Preferences window — is now implemented.

> Pixel fidelity is unverified: the build is validated headlessly (compiles /
> links / launches / opens / switches tabs without crashing); exact rendering
> against the web mock was not visually compared.

## Files (`Sources/GoldenGate/`)

| File | Role |
|------|------|
| `GGTheme.swift` | Design tokens (accent/inks/hairlines/signal/encryption colors), fonts, glass material helpers (`.ultraThinMaterial` + `NSVisualEffectView`). |
| `GGModel.swift` | `GGNetwork`/`GGClient` models, seed data, `GGAppState` (`ObservableObject`) + the 1100ms scan tick (signal jitter, channel hop, packet/byte growth). |
| `GGComponents.swift` | Shared atoms: traffic lights, signal bars, encryption pill, segmented switcher, Scan capsule, icon buttons. |
| `GGRootView.swift` | The window content: glass toolbar, contextual trailing controls, content router, status bar, prefs overlay. |
| `GGNetworksView.swift` | Networks table: sticky header, striping, hover, selection, fresh-row flash, search filtering; tap selects + routes to Details. |
| `GGDetailsView.swift` | Details split: inspector (header + property groups + comment box) and clients panel (table or empty-state); `GGCommentEditor` NSTextView wrapper + UTC `fullTime` formatter. |
| `GGGraphView.swift` | Live rolling multi-series `Canvas` chart: grid/baseline/mono axis labels, per-network color line + area + leading dot, wrapping legend (`GGFlowLayout`); `[Int:[Double]]` rolling buffer advanced by a scanning-gated `Timer`, trimmed to the window. |
| `GGMapView.swift` | Radar map `ZStack`: radial bg, grid, landmass blobs, lat/lng-projected signal-colored markers (pulsing ring + conic sweep while scanning), GPS dot, glass HUD/zoom/legend; tap marker → Details. |
| `GGPreferencesView.swift` | Preferences overlay window: titlebar + 8-tab toolbar + scrollable per-tab body (Scanning/Filter/Sounds/Driver/GPS/Map/Traffic/General); reusable `GGSwitch`/`GGCheck`/`GGSelect`/`GGField`/`GGGroupCard`/`GGToggleRow`/`GGSectionLabel`/`GGPrefDivider`; local `GGPrefsState` (prototype values, not persisted). |
| `GGStubViews.swift` | Now an empty placeholder (all content views moved out: Networks/Details Stage 2, Graph/Map Stage 3, Preferences Stage 4); kept only to preserve target membership. |
| `GGWindowController.swift` | `@objc(KGGoldenGateWindowController)` AppKit hosting controller. |

## How to open

- **In the running app:** Window menu → **Golden Gate Interface** (`⌥⌘G`).
- **At launch (for testing):** set `KISMAC_GOLDENGATE_AUTOSHOW=1` in the environment;
  the window opens automatically during `applicationDidFinishLaunching:`.

The Golden Gate window is **additional** — it does not replace or disturb the
existing main KisMAC window.

## Integration details

- **Swift enabled** on both Debug + Release of the `KisMac2` target:
  `SWIFT_VERSION = 5.0`, `SWIFT_OPTIMIZATION_LEVEL` (`-Onone` Debug / `-O` Release),
  `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES`, `PRODUCT_MODULE_NAME = KisMac2`.
- The Obj-C → Swift bridge uses the generated header `#import "KisMac2-Swift.h"`,
  imported from `ScanController.m`.
- `-[ScanController applicationDidFinishLaunching:]` calls `-setupGoldenGateInterface`,
  which lazily instantiates `KGGoldenGateWindowController`, adds the Window-menu
  item targeting `-showWindow`, and (optionally) auto-shows the window.
- `-showWindow` lazily builds a ~1320×840 dark-appearance `NSWindow` whose
  `contentViewController` is an `NSHostingController(rootView: GGRootView())`.
  The controller holds a strong reference so the window survives.

### Note on Clang modules

The task spec suggested `CLANG_ENABLE_MODULES = YES` / `DEFINES_MODULE = YES`.
Under Xcode 26.5's explicit-modules build, enabling clang modules forces the
legacy bundled `BIGL.framework` headers (which assume a textual Cocoa include)
to be compiled as a standalone module, which fails (`NSOpenGLView`/`BOOL`
unknown). Those settings are **not** required for the Obj-C → Swift direction
used here (Obj-C imports the generated `-Swift.h`; Swift imports no project
Obj-C), so clang modules are left **off** (`CLANG_ENABLE_MODULES = NO`,
`CLANG_ENABLE_EXPLICIT_MODULES = NO`) to preserve the legacy framework's
textual include path. Swift still compiles and the generated header is still
produced.

## Build / verify

```sh
xcodebuild -workspace KisMac2.xcworkspace -scheme KisMac2 -configuration Debug \
  clean build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Self-tests (no regressions): `KISMAC_CAP_SELFTEST=1 KISMAC_PROTO_SELFTEST=1` → 12/12 PASS.
