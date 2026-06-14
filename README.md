[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat)](https://www.apple.com/macos/)
[![Status](https://img.shields.io/badge/status-work%20in%20progress-orange.svg?style=flat)](#-work-in-progress--not-a-working-release)
[![License](https://img.shields.io/badge/license-GPL%202.0-brightgreen.svg?style=flat)](http://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

# KisMAC3

> ## 🚧 Work in progress — NOT a working release
>
> **KisMAC3 is an active modernization, not finished software. Do not expect a usable
> wireless-auditing app yet.** It builds, launches, and the offline/analysis plumbing
> works, but major pieces are incomplete: the new **Golden Gate** UI runs on **demo data
> only** (not wired to real scanning), there is **no signed/notarized release**, and live
> Wi-Fi capture / active features are gated/unimplemented. See **[Status](#status)** and
> **[Roadmap / next steps](#roadmap--next-steps)** below. Use it for development and
> evaluation only.

**KisMAC3** is a modern-macOS revival of the classic **KisMAC** / **KisMAC2** wireless
stumbling and security-auditing tool. KisMAC2 stopped being maintained around 2016 and
targeted OS X 10.9–10.12 (32/64-bit, old AppKit, deprecated/removed APIs); KisMAC3 ports
it forward to build, run, and behave correctly on current macOS and Xcode, with a
capability-driven, safety-gated architecture.

> ⚠️ **Authorized use only.** KisMAC is a wireless security tool. KisMAC3 keeps all
> active/offensive functionality (injection, deauthentication, AP simulation) disabled
> unless an explicitly **authorized campaign scope** is configured, and gates everything
> through a central capability engine. Use it only on networks and devices you own or are
> authorized to assess.

## What changed in KisMAC3

This is a substantial modernization of the legacy tree, not a cosmetic bump:

- **Builds & runs on current macOS / Xcode again.** Fixed the build (a broken
  `Update vendors.db` script phase), removed dead/abandoned code (bundled Growl, an
  i386-only Carbon MIDI plugin, a dead server-export transport, and a crash reporter that
  uploaded your Address Book email to a defunct endpoint), and migrated ~200 deprecated
  AppKit/Foundation call sites. Debug **and** Release (universal arm64 + x86_64) build green.
- **Capability engine** — a single source of truth that decides whether each feature is
  available on *this* Mac/OS and, if not, **why** (permission missing, unsupported
  hardware, unsupported adapter, macOS-blocked, parser missing, or no authorized scope).
  The UI and drivers ask the engine; they never guess at hardware support.
- **Hardware capability probe** — a non-disruptive probe that reports what the built-in
  Wi-Fi actually allows (interface, bands 2.4/5/6 GHz, PHY, Location state, pcap/BPF
  access); persisted per Mac model + OS. No guessed status.
- **Modern Location flow** (CoreLocation authorization + remediation) replacing the
  deprecated delegate path.
- **Modern 802.11 decode** — WPA2 / WPA3-SAE / OWE / Enterprise / PMF and Wi-Fi 6 / 6E / 7
  metadata from imported frames, with a fixture corpus and bounds-checked parsing.
- **First-class offline pcap/pcapng import** — analyze captures with zero live-capture
  capability.
- **Crypto modernized** — WEP/WPA/LEAP cracking math moved from end-of-life PolarSSL to
  Apple **CommonCrypto** (PBKDF2 / MD4 / MD5 / SHA-1), plus several real bug fixes.
- **Safety guardrails** — authorized-campaign scope, append-only audit log, always-available
  emergency stop, identifier redaction (MAC/SSID/hostname/BLE), local-only defaults, and
  opt-in-off server export. Injection / deauth / AP require an injection-capable adapter
  **and** an in-scope campaign **and** are audited — all fail closed.
- **Native MacBook surfaces** — BLE inventory (CoreBluetooth), USB/HID/serial inventory
  (IOKit), LAN/Bonjour discovery (Network.framework), and local interface inventory — all
  read-only and privacy-redacted.
- **Secure projects** — `.kismac` files load via secure coding (hostile input fails closed)
  and support optional passphrase encryption (PBKDF2 + AES-256, encrypt-then-MAC).
- **Release pipeline scaffolding** — hardened-runtime entitlements, signing/notarization/DMG
  scripts, and CI (see `docs/release.md`).

Every subsystem ships a headless self-test (`KISMAC_*_SELFTEST=1`) for validation without a
GUI or special hardware.

## Build

```sh
git clone --recursive https://github.com/jencryzthers/KisMAC3.git
cd KisMAC3
git submodule update --init --recursive   # if you didn't clone with --recursive

# Quick local build into ./build/ (signing disabled — no Developer ID needed):
scripts/build.sh                 # incremental Debug build
scripts/build.sh --clean --run   # clean build, then launch
scripts/build.sh --release       # universal Release build

# …or open the workspace and build the KisMac2 scheme:
open KisMac2.xcworkspace
```

The product lands in `build/` (gitignored), with a convenience symlink `build/KisMac2.app`.
For a **signed + notarized** build, see `scripts/release.sh` and `docs/release.md` (requires
a Developer ID certificate).

Toolchain validated: Xcode 26.5 / macOS 27 / Apple Silicon.

## Status

- ✅ Builds (Debug + Release) and launches on current macOS; capability-gated end-to-end.
- ✅ Offline analysis (pcap/pcapng import, protocol decode, cracking, reporting) works today.
- 🔜 **Signed/notarized distribution** — pipeline is scaffolded; needs a Developer ID cert.
- 🧪 **Modern "Golden Gate" UI** — a native SwiftUI redesign (all views + Preferences) ships
  and opens on launch, but it's currently a **visual preview on demo data** (see below); the
  legacy window remains the functional app.
- 🔜 **Live Wi-Fi capture / active radio features** — gated behind the hardware probe and,
  where the built-in card can't, an external adapter. Real permission grants
  (Location/Bluetooth/Local-Network) require a signed build.
- ℹ️ Validated on Apple Silicon; Intel validation pending.

## ⚠️ Golden Gate interface — preview status

KisMAC3 ships a native **SwiftUI "Golden Gate"** redesign (dark Liquid-Glass; unified
toolbar, Networks / Details / Graph / Map, and an 8-tab Preferences window). It **opens
automatically on launch** (set `KISMAC_GOLDENGATE_AUTOSHOW=0` to suppress, or use the
**Window → "Golden Gate Interface"** menu item / ⌥⌘G).

**It is currently a faithful visual preview running on the design's demo data** (10 mocked
networks) — it is **not yet wired to the real scan / capability engine.** So today:

- **Golden Gate window** = the exact new design, animations included, but **placeholder data**.
- **Legacy main window** = the **functional** app (real scanning, cracking, capture, etc.).

**Next step** (not done yet): wire Golden Gate to the real data layer already built (capability
engine + scan + pcap import) and retire the legacy window, so the new UI becomes the actual,
functional application. Until then, treat Golden Gate as a UI preview.

## Roadmap / next steps

**None of the items below are done** — this is the work that stands between the current
state and a real, shippable KisMAC3. Roughly in priority order:

1. **Wire the Golden Gate UI to real data** — replace the demo seed with the live capability
   engine + scan results + pcap import, make the toolbar Scan actually drive capture, then
   retire the legacy window so the new UI *is* the functional app. (Biggest item; until this
   lands, Golden Gate is a visual preview only.)
2. **Signed + notarized release** — the build/sign/notarize/DMG/CI pipeline is scaffolded
   (`scripts/`, `docs/release.md`) but has never run: it needs a **Developer ID certificate**.
   Without it there is no distributable/Gatekeeper-passing app.
3. **Live Wi-Fi capture & active features** — monitor mode, channel hopping, handshake
   capture, deauth, injection, AP/evil-twin are **gated/unimplemented**: built-in Wi-Fi is
   BPF-permission-gated and can't transmit; these need a hardware probe confirmation and an
   external USB adapter, and stay scope-gated + audited. Lab execution is not built.
4. **Real permission grants & Intel validation** — Location / Bluetooth / Local-Network only
   yield real data under a **signed build** (TCC); everything is validated on Apple Silicon
   only — **Intel-Mac validation is pending**.
5. **UI fidelity pass** — the SwiftUI rewrite was built without on-device visual iteration;
   it needs a real pixel/layout review (resize behavior, glass, animations).
6. **Deprecation finish-up** — remaining legacy debt (NSDrawer → split view, OpenGL/BIGL
   graphs → Metal, Carbon Speech) and the residual build warnings.

## Documentation

- `docs/modernization-plan.md` — the milestone roadmap.
- `docs/original-feature-parity.md` — every legacy feature with its modern disposition.
- `docs/task-slices.md` — the executable work plan + status.
- `docs/build-triage.md` — build/toolchain notes.
- `docs/release.md` — signing, notarization, and packaging.

## Lineage & license

KisMAC3 continues the line of **KisMAC** (Michael Roßberg / Geoffrey Kruse, kismac-ng.org;
unmaintained since ~2011) → **KisMAC2** (Vitalii Parovishnyk / IGRSoft; unmaintained since
~2016) → **KisMAC3** (this modern port). Parts are based on aircrack by Christophe Devine.

Licensed under the **GNU General Public License, version 2** (see `LICENSE.txt`).
