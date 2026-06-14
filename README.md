[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-GPL%202.0-brightgreen.svg?style=flat)](http://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

# KisMAC3

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
- 🔜 **Modern UI** (sidebar/dashboard, Metal graphs, the BLE/USB/LAN workspaces) — the data
  layer is in place; the GUI rewrite is in progress.
- 🔜 **Live Wi-Fi capture / active radio features** — gated behind the hardware probe and,
  where the built-in card can't, an external adapter. Real permission grants
  (Location/Bluetooth/Local-Network) require a signed build.
- ℹ️ Validated on Apple Silicon; Intel validation pending.

## Documentation

- `AGENTS.md` — engineering source of truth (conventions, build, safety non-negotiables).
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
