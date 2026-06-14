# KisMac3 — Release, Signing & Notarization (Milestone 14 / S8.x)

This is the operator guide for producing a distributable, **Developer ID
signed + hardened-runtime + notarized** KisMac3 build, and for the CI that
guards every push.

Two halves:

- **S8.1 (this scaffolding) — DONE, cert-independent.** Entitlements, the
  `scripts/` pipeline, the GitHub Actions CI, and these docs. Everything is in
  place and verified to *degrade gracefully* without the signing certificate.
- **S8.2 (the real signed run) — BLOCKED on credentials.** The actual
  `codesign` / `notarytool` calls need the Developer ID certificate (team
  `DMP42GVPJ3`) and an App Store Connect API key, which are **not on this
  machine** (ENV-1 in `docs/build-triage.md`). Provide them per
  ["What you must provide"](#what-you-must-provide-s82), then run
  `scripts/release.sh`.

---

## TL;DR

```sh
# One-time: install the Developer ID cert into your login Keychain, then:
cp .secrets/appstoreconnect.env.example .secrets/appstoreconnect.env
chmod 600 .secrets/appstoreconnect.env
$EDITOR .secrets/appstoreconnect.env            # fill in real values
# put AuthKey_<KEY_ID>.p8 in .secrets/private_keys/ (chmod 600)

scripts/release.sh --preflight   # check prerequisites only
scripts/release.sh               # build -> sign -> notarize -> staple -> DMG
```

Without credentials, every script prints exactly what is missing and exits
non-zero **without building or signing anything** — safe to run anywhere.

---

## Pipeline overview

```
scripts/release.sh   (orchestrator; preflights then runs each step)
 ├─ build_release.sh  xcodebuild archive (Release, ENABLE_HARDENED_RUNTIME=YES)  -> dist/KisMac2.xcarchive
 ├─ sign_export.sh    xcodebuild -exportArchive (developer-id)                   -> dist/export/KisMac2.app
 ├─ notarize.sh       xcrun notarytool submit --wait + xcrun stapler staple      (app)
 ├─ make_dmg.sh       hdiutil create (UDZO) + DMG Artwork background + codesign  -> dist/KisMac2.dmg
 └─ notarize.sh       notarize + staple                                          (dmg)
```

- `scripts/lib.sh` — shared helpers: path config, env loading, and the
  credential **preflight**. It never prints a secret value, only NAMES and
  present/MISSING status.
- All build artifacts land under `dist/` (gitignored). Secrets live under
  `.secrets/` (gitignored except the `.example` template).

Every script reads its inputs from the environment / `.secrets/appstoreconnect.env`
and accepts overrides via env vars (`CONFIGURATION`, `ARCHIVE_PATH`,
`DMG_PATH`, `CODESIGN_IDENTITY`, `DEVELOPMENT_TEAM`, …). See the header comment
of each script.

---

## Hardened runtime & entitlements

- `KisMac2.entitlements` (repo root) is referenced by the **Release**
  configuration (`CODE_SIGN_ENTITLEMENTS`), and `ENABLE_HARDENED_RUNTIME = YES`
  is set for Release. Both are **inert for the unsigned verification build**
  (`CODE_SIGNING_ALLOWED=NO`), so the signing-disabled Release build stays
  green; they take effect only when a real identity signs the app.
- **Not sandboxed.** KisMac needs raw libpcap/BPF, IOKit, CoreWLAN,
  CoreBluetooth and the Apple80211 private framework — none of which work under
  the App Sandbox. There is **no** `com.apple.security.app-sandbox` key, by
  design.
- Entitlements included (minimal, each justified inline in the file):
  - `com.apple.security.personal-information.location` — CoreLocation GPS
    tagging (S1.2; pairs with `NSLocationWhenInUseUsageDescription`).
  - `com.apple.security.device.bluetooth` — BLE inventory (S3.1; pairs with
    `NSBluetoothAlwaysUsageDescription`).
  - `com.apple.security.device.usb` — USB/HID inventory via IOKit (S3.2).
- **Library validation is left ENABLED.** The bundled frameworks
  (`BIGL.framework`, `BIGeneric.framework`) and the GBStorage code are signed
  with the **same** team by `sign_export.sh`, so
  `com.apple.security.cs.disable-library-validation` is **not** needed and is
  left commented out. Only enable it if you must load a framework signed by a
  *different* team identity — and document why here.

---

## ⚠️ Known limitation — live pcap/BPF capture under a Developer-ID app

A plain Developer-ID, hardened-runtime KisMac build **cannot do live Wi-Fi
capture out of the box**. Opening a BPF device (`/dev/bpfN`) for live monitor
capture requires elevated access:

- The BPF nodes are root-owned; a normal user process is denied
  (`pcap_open` reports `permissionMissing` — confirmed on this machine in
  S1.1/S1.3).
- The historical fixes (a `chmod`-the-bpf helper, the `ChmodBPF` launch daemon,
  or running the app as root) are exactly the kind of privileged side-channel a
  hardened-runtime, notarized distribution is meant to avoid.

**Consequence:** the signed/notarized DMG ships an app that is fully functional
for everything *except* live BPF capture — i.e. **offline pcap/pcapng import
(S2.2), the modern protocol decode (S2.1), crypto (S2.3), the native
inventories (BLE/USB/LAN/interfaces, S3.x), Kismet remote ingest (S2.4), and
CoreWLAN scanning (Location-gated)** all work. Live local monitor-mode capture
needs **root or a privileged helper tool** that is out of scope for S8.1.

This is the release-side statement of the parity-matrix 🔍 rows: monitor mode /
channel switching / handshake capture remain `unknownRequiresActiveProbe` and
are **not** claimed to work under a plain Developer-ID app. A future slice may
add a signed, separately-notarized privileged helper (SMAppService /
`SMJobBless`-style) to grant BPF access; until then, document live capture as
requiring elevated privileges.

---

## Installation & first-run permissions (for end users)

1. Open `KisMac2.dmg`, drag **KisMac2** to **Applications**.
2. First launch: macOS Gatekeeper verifies the Developer ID signature +
   notarization ticket (stapled, so it works offline).
3. Grant permissions when prompted (each maps to an Info.plist usage string):
   - **Location** (`NSLocationWhenInUseUsageDescription`) — required for
     CoreWLAN to reveal BSSIDs during scanning and for GPS network tagging.
   - **Bluetooth** (`NSBluetoothAlwaysUsageDescription`) — BLE inventory.
   - **Local Network** (`NSLocalNetworkUsageDescription` + `NSBonjourServices`)
     — passive Bonjour/mDNS service discovery.
   - **pcap / BPF (live capture)** — see the limitation above; needs elevated
     privileges, not a TCC prompt.
4. Permissions can be reviewed/reset in **System Settings → Privacy & Security**.

---

## What you must provide (S8.2)

To run the real signed/notarized release, supply on the signing machine:

1. **Developer ID Application certificate + private key** for team
   `DMP42GVPJ3`, imported into your login Keychain. Create/export via
   *Xcode → Settings → Accounts → Manage Certificates*, or export a `.p12`
   from the team's developer account and `security import` it. Verify with:
   ```sh
   security find-identity -v -p codesigning   # should list "Developer ID Application: … (DMP42GVPJ3)"
   ```
2. **`.secrets/appstoreconnect.env`** (copied from the `.example`, `chmod 600`):
   - `DEVELOPMENT_TEAM=DMP42GVPJ3`
   - `CODESIGN_IDENTITY=Developer ID Application: <name> (DMP42GVPJ3)`
   - `ASC_API_KEY_ID=`, `ASC_API_ISSUER_ID=`, `ASC_API_KEY_PATH=`
3. **App Store Connect API key** (`.p8`) created at *App Store Connect → Users
   and Access → Integrations → App Store Connect API*, saved at
   `.secrets/private_keys/AuthKey_<KEY_ID>.p8` (`chmod 600`), with
   `ASC_API_KEY_PATH` pointing at it.

Never commit any of these. `.secrets/` is gitignored (only the `.example` is
tracked); secrets come from env / Keychain only.

---

## CI (GitHub Actions)

`.github/workflows/build.yml` runs on every push/PR on a `macos-15` runner:

1. Checkout **with submodules** (+ a defensive `submodule update --init
   --recursive`).
2. `shellcheck` the release scripts.
3. **Signing-disabled clean Debug build**
   (`CODE_SIGNING_ALLOWED=NO …`) — asserts `BUILD SUCCEEDED`.
4. **Headless self-test smoke**: launches the built app with the passive /
   CPU-only `KISMAC_*_SELFTEST` suites enabled (cap, proto, crypto,
   pcap-import, safety, active-gate, USB-inventory, interface-inventory),
   captures stdout, and fails the job if any suite logs a failure.

CI is intentionally **unsigned and secret-free** so it runs on forks and any
runner. The workflow comments mark exactly where GitHub repository secrets
(Developer ID `.p12` + ASC API key) would plug into a separate, protected
release workflow that calls `scripts/release.sh` — that is deliberately **not**
wired here.

**Travis migration:** the legacy `.travis.yml` (Xcode 8.3 / macOS 10.12 SDK,
long dead) is deprecated — its content is now a breadcrumb pointing here. The
README build badge should be updated to the GitHub Actions status when the repo
is pushed.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No signing certificate "Mac Development" … team DMP42GVPJ3` | ENV-1: no Developer ID cert in the Keychain. Install it (see above). For verification-only builds, add `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. |
| Preflight says a var is `MISSING` | Fill it in `.secrets/appstoreconnect.env` (or export it). The message lists every missing item. |
| `notarytool` rejects: "The binary is not signed with a valid Developer ID" / "does not have hardened runtime enabled" | Re-export via `sign_export.sh` (it sets the runtime flag and verifies it). Confirm `ENABLE_HARDENED_RUNTIME=YES` for Release. |
| `hdiutil create … is deprecated` warning | Harmless on macOS 27 — the DMG is still produced and verifies (`hdiutil verify`). Apple's suggested `diskutil image create` replacement can be adopted in a later slice. |
| App launches but live capture finds nothing | Expected — live BPF capture needs elevated privileges (see the limitation section). Offline import + the native surfaces still work. |
| Stapled app still warns on first launch | Ensure notarization *succeeded* (notarytool `Accepted`) before stapling, and that you stapled the same artifact you distribute (both the `.app` and the `.dmg`). |

---

## Verification done for S8.1 (no certificate needed)

- Clean **Release** build (signing disabled) **green** with the hardened-runtime
  + entitlements settings added (they are inert when signing is off).
- `shellcheck -x scripts/*.sh` — clean, no findings.
- Each script run **without credentials** exits non-zero with the remediation
  message and does nothing destructive.
- `make_dmg.sh` produces a valid DMG from the unsigned build product
  (`hdiutil verify` passes) — proves the packaging path independently of the
  cert.
- `.secrets/` is gitignored (real env + `.p8` ignored, only `.example`
  tracked); no secret value is committed anywhere.
