# KisMac3 — Task Slices & Acceptance Matrix

Owner: `kismac-program-lead`. This turns the `docs/modernization-plan.md` milestone
roadmap into small, independently-shippable task slices, ordered by dependency, each
with a single implementation owner, an independent reviewer, a validation owner
(the PR gate from `docs/subagent-orchestration.md`), explicit acceptance criteria,
and the upstream parity decisions from `docs/original-feature-parity.md`.

**Sizing:** each slice is meant to be one PR — roughly 1–3 days of focused work.
Larger milestones are split. Slices marked **[blocked]** must not start until their
dependencies land.

**Reading the table:** `Impl` = implementation agent, `Rev` = reviewer, `Val` =
validation agent (all defined in `.claude/agents/`). `Deps` = slice IDs that must
land first.

---

## Wave 0 — Baseline (do first, mostly sequential)

These get the project compiling and observable on current Xcode before any feature
work. They unblock everything else.

> **Wave 0 build invocation (env note from S0.1):** this machine has no `DMP42GVPJ3`
> dev signing cert (iCloud-hosted repo), so default `xcodebuild` fails at provisioning.
> For all Wave 0 builds, disable signing —
> `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` — or set a
> local team. Signing itself is owned by **S8.x** (tracked as ENV-1 in `docs/build-triage.md`).
> Toolchain observed: Xcode 26.5, macOS 27.0, arm64, SDK 26.5, deployment target 13.0.

### S0.1 — Compile baseline: inventory & triage build failures — ✅ DONE (`b34b732`)
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** objc-appkit-reviewer · **Val:** xcode-build-validator · **Deps:** —
- **Scope:** Attempt a clean build of `KisMac2.xcworkspace` on current Xcode (after `git submodule update --init --recursive`). Catalogue every error/warning into a triage list; do **not** fix yet. Confirm submodules (`BIGeneric`, `BIGL`, `polarssl`) build.
- **Acceptance:** A committed `docs/build-triage.md` listing each failure with file:line and a proposed owner slice. `xcode-build-validator` confirms the error list is reproducible.
- **Outcome:** `docs/build-triage.md` committed. BIGL/BIGeneric subprojects build (123 warnings, all OpenGL/Carbon deprecation → S5.x). The KisMac2 target aborts at its **first** phase (`Update vendors.db` run-script) due to a Python `IndentationError` introduced by the pre-existing WIP commit `9372017` — so the S0.3/S0.4 compile-breakers are real-in-source but **not yet build-confirmed** (masked behind the script failure). This spawned **S0.6**. **S0.1 must be RE-RUN after S0.6 + S0.2 land** to capture the build-confirmed compiler errors.

### S0.6 — Fix the `OUItoVendorDB.py` "Update vendors.db" build-script phase
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** objc-appkit-reviewer · **Val:** xcode-build-validator · **Deps:** S0.1
- **Scope:** Repair the Python `IndentationError` at `Resources/Generic/OUItoVendorDB.py:49` (de-indent the `if filesize:` progress block to sit inside the `while` download loop). This is the **first** build phase of the KisMac2 target, so it must pass before any source compiles — the true first build-unblocker. (Root cause: the WIP commit `9372017` added an over-indented line; verify the rest of that WIP Python change is sound while here.)
- **Acceptance:** `python3 -m py_compile Resources/Generic/OUItoVendorDB.py` clean; the `Update vendors.db` phase succeeds (or is confirmed to fetch/skip correctly offline); the KisMac2 build proceeds past it to the compile phase. `xcode-build-validator` confirms the build now reaches source compilation.

### S0.2 — Remove dead bundled Growl framework
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** release-reviewer · **Val:** xcode-build-validator · **Deps:** S0.1
- **Scope:** Strip `Resources/Growl.framework` from the Frameworks + CopyFiles build phases and from disk; confirm no code references remain (Growl removal already committed in `9372017`).
- **Acceptance:** Builds with no Growl references; `otool -L` on the product shows no Growl; app launches. Parity: notifications row stays 🔧.

### S0.3 — Fix compile-breaking removed APIs
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** objc-appkit-reviewer · **Val:** xcode-build-validator · **Deps:** S0.1
- **Scope:** Replace `NSDate descriptionWithCalendarFormat:`/`NSCalendarDate` (export paths in `WaveStorageController.m:327,477,513`), and quarantine the unlinkable `WirelessCryptMD5`/`WirelessEncrypt` "Apple" WEP wordlist verbs (`WaveNetWEPWordlist.m`) per the 🗑 decision. Replace `NSBeginAlertSheet`/`NSRunCriticalAlertPanel` in touched files with `NSAlert`.
- **Acceptance:** Project compiles past these errors; the three removed WEP verbs are disabled with a clear "unsupported (removed Apple API)" path, not a crash. `xcode-build-validator` reports a successful Debug build.

### S0.4 — Quarantine dead i386/Carbon code
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** objc-appkit-reviewer · **Val:** xcode-build-validator · **Deps:** S0.1
- **Scope:** Remove the `#ifdef __i386__` MIDI plugin (`WavePluginMidi.m`, 🗑) and the dead `HTTPStream`/`exportToServer:` stub + crash-report upload (🗑). Leave hooks documented.
- **Acceptance:** Builds clean; menu items for removed features are gone or disabled with a reason; no dead-endpoint network calls remain. `security-abuse-reviewer` confirms the crash-upload privacy path is gone.

### S0.5 — Clean Debug + Release build green
- **Milestone:** 4 · **Impl:** legacy-objc-porting-agent · **Rev:** objc-appkit-reviewer · **Val:** xcode-build-validator · **Deps:** S0.6, S0.2, S0.3, S0.4
- **Scope:** Resolve remaining triage items to reach a warning-summarized clean build for both configurations; confirm Apple Silicon + Intel (or document which is unavailable).
- **Acceptance:** `xcode-build-validator`: clean Debug **and** Release build, product is the expected architecture, app launches outside Xcode (unsigned dev run). This is the **compile-baseline gate** for all later waves.

---

## Wave 1 — Capability foundation (the spine of the port)

### S1.1 — MacBook hardware capability probe — ✅ DONE (Apple Silicon) / partial validation (`2a96c99`)
- **Milestone:** 1 · **Impl:** macbook-capability-agent · **Rev:** macos-api-reviewer · **Val:** macbook-hardware-validation-agent · **Deps:** S0.5 (proceeded on the already-green **Debug** baseline post-S0.6; full S0.5 not required to compile)
- **Scope:** Implement the probe from Milestone 1: Apple Wi-Fi interface visibility, Location-permission state, CoreWLAN scan support, 2.4/5/6 GHz visibility, pcap open, monitor-like capture, datalink, channel switching, AP/SoftAP, frame injection, exposed PHY/security metadata. Persist results per Mac model + OS version. New `Sources/Capabilities/*`, `Sources/WaveDrivers/WaveDriverAirport*`, `Sources/Core/WaveHelper.m`, `Resources/Info.plist`.
- **Acceptance:** Runs on real Intel + Apple Silicon MacBooks and emits a persisted capability report with **no guessed status** (`macbook-hardware-validation-agent`). This report is what resolves every 🔍 `needs-probe` row in the parity matrix.
- **Outcome:** Implemented `Sources/Capabilities/KMHardwareProbe.{h,m}` + `KMHardwareCapability.{h,m}` (non-disruptive only, per safety), `NSLocationWhenInUseUsageDescription` added, probe runs async at launch and persists `~/Library/Application Support/KisMac3/hardware-probe-<model>-<os>.json`. Build green, app launches, report verified. **Scope decisions:** disruptive ops (monitor/channel-switch/AP/injection) are **reported `unknownRequiresActiveProbe`, not executed** (would drop the Wi-Fi link); did not touch `WaveDriverAirport*`/`WaveHelper.m` (the standalone probe didn't need them). **On Mac15,8 / macOS 27 / arm64:** Wi-Fi iface ✓, Location `permissionMissing` (NotDetermined → S1.2), CoreWLAN scan API-available (Location-gated), **2.4/5/6 GHz all supported**, PHY metadata ✓, **`pcap.open` permissionMissing (`/dev/bpf0` denied)** — live capture is BPF-permission-gated, not impossible. **Remaining:** Intel-MacBook validation + a future *consented active probe* to resolve the disruptive 🔍 rows (monitor/channel/AP/injection still `unknownRequiresActiveProbe`). Minor: `kCLAuthorizationStatusAuthorizedWhenInUse` macOS handling to confirm in S1.2.

### S1.2 — Info.plist permission strings + Location auth flow — ✅ DONE (`df49aba`)
- **Milestone:** 1/2 · **Impl:** macbook-capability-agent · **Rev:** macos-api-reviewer · **Val:** macbook-native-validation-agent · **Deps:** S0.5
- **Scope:** Add `NSLocationWhenInUseUsageDescription` (+ Bluetooth/Contacts strings as features land), wire `CLLocationManager` authorization with `locationManagerDidChangeAuthorization` and `didUpdateLocations:` (replacing the deprecated delegate in `GPSController.m`). Surface remediation when denied.
- **Acceptance:** Granting Location reveals BSSIDs in active scan; denial shows exact remediation steps; no silent failure. `macbook-native-validation-agent` records auth/blocked status.
- **Outcome:** `GPSController` modernized — `-requestWhenInUseAuthorization` (modern API) fired when the CoreLocation source starts; `-locationManagerDidChangeAuthorization:` (macOS 11+) handles all transitions; deprecated `didUpdateToLocation:fromLocation:` → `didUpdateLocations:`; denial surfaces an `NSAlert` with System-Settings remediation (one-time, non-nagging). New `KisMACLocationAuthorizationChanged` notification + `-locationAuthorizationStatus`/`-isLocationAuthorized` so the capability layer observes live auth. Fixed the S1.1 probe's macOS *WhenInUse* misreport (the symbol is unavailable on the macOS SDK → recognize granted via Always OR raw value 4, applied in both probe and GPSController). Build green; the two deprecated CoreLocation-delegate warnings are gone; runtime confirmed the change-handler fires and `kCLErrorDenied` routes correctly. Reviewer fix: added `#import <Foundation/Foundation.h>` to the touched `KisMACNotifications.h` (was relying on the prefix header). **Needs signed build + human TCC grant to confirm** the Allow dialog appears/persists and that granting reveals BSSIDs (signing = S8.x). Pre-existing IDE flag `GPSController.h:87` (`waypoint` typedef via include order) left for S0.5 header hygiene — not a regression.

### S1.3 — Capability engine core — ✅ DONE (`6302540`)
- **Milestone:** 3 · **Impl:** capability-engine-agent · **Rev:** architecture-invariants-reviewer · **Val:** capability-test-agent · **Deps:** S1.1
- **Scope:** Implement `KMCapability` + `KMCapabilityEngine` (`Sources/Capabilities/*`): the single source of truth for the Milestone 3 capability list. Every disabled feature exposes the exact reason (permission / unsupported hardware / unsupported adapter / macOS-blocked / parser-missing / scope-missing).
- **Acceptance:** `capability-test-agent`: UI cannot enable a feature unless the engine says it can; each capability returns a correct enabled/disabled + reason given a mocked probe result. Architecture invariant: no UI or driver decides hardware support directly.
- **Outcome:** `KMCapability.{h,m}` + `KMCapabilityEngine.{h,m}`. Designated init takes **injected** inputs (S1.1 `KMHardwareCapability` array + fail-closed `KMNoActiveScopeProvider` + `KMProtocolParserRegistry`); decision logic never calls the probe → hardware-independent + testable. All 29 Milestone-3 capabilities mapped with correct state+reason; active/offensive ops fail closed on `activeLabScopeMissing`; modern decoders `protocolParserMissing` (S2.1); external modules `unsupportedAdapter`; S3.x surfaces reported not-implemented. **Tests:** no XCTest target exists in this legacy pbxproj, so a `+runSelfTestReturningFailures:` harness covers 4 mocked scenarios (all-green / bpf-denied / no-wifi / scoped+parser) — **runs and PASSes** (verified independently via `KISMAC_CAP_SELFTEST=1`). Build green, app launches. **Boundary:** the engine establishes the contract; **rewiring UI/drivers to query it is S1.4**, and an adapter-presence input for radio ops extends in S4.2. A real XCTest target is a worthwhile later add (self-test only for now).

### S1.4 — Route active-scan plumbing through the engine — ✅ DONE (`84a93ad`)
- **Milestone:** 3/4 · **Impl:** capability-engine-agent · **Rev:** architecture-invariants-reviewer · **Val:** capability-test-agent · **Deps:** S1.3
- **Scope:** Make the existing CoreWLAN active scan (🔧) the first consumer of the capability engine; gate the scan button + driver selection on capability + Location.
- **Acceptance:** With Location granted and CoreWLAN available, scan runs; otherwise the action is disabled with a reason. No `needs-probe` feature is exposed as available.
- **Outcome:** `ScanController` owns a cached `KMCapabilityEngine` (built from a live probe on a background queue, rebuilt on `KisMACLocationAuthorizationChanged`). `-startScan` consults the engine for `KMFeatureScan` **and** the active driver's mapped capability (`-capabilityKeyForActiveDriver`: passive AirportExtreme→monitor, USB→injection, Kismet→remote, built-in→scan) and blocks with an `NSAlert`+`DBNSLog` if unavailable. `BridgeController` adds `-validateToolbarItem:`/`-validateMenuItem:` so the Scan affordance is disabled (not click-then-fail). **Architecture invariant holds**: the controller asks the engine, never hardcodes hardware checks. Runtime-verified end-to-end (probe→engine→gate): on this machine scan is gated `permissionMissing` ("Active scan requires Location authorization"), and the auth-change observer rebuilds the engine. Build green. Reviewer fix: added `#import <Cocoa/Cocoa.h>` to `ScanController.h` (cleared a 30+ standalone-analysis error cascade across ScanController/Private/Scriptable headers; remaining `NSDrawer` warnings are pre-existing → S5.x). **Deferred to S5.x:** full PrefsDriver UI gating (only minimal scan-time driver gating done here). USB driver detected via `NSClassFromString` to avoid pulling C++ `USBJack` into a `.m`.

---

## Wave 2 — Protocol & capture (depends on capability engine)

### S2.1 — Modern protocol metadata model + fixtures **[blocked: S1.3]**
- **Milestone:** 5/6 · **Impl:** wifi-protocol-agent · **Rev:** wireless-protocol-reviewer · **Val:** protocol-fixture-test-agent · **Deps:** S1.3
- **Scope:** Wi-Fi 4/5/6/6E/7 metadata model; WPA2/WPA3/OWE/Enterprise/PMF parsing; tagged-parameter parsing; hidden-SSID/malformed-frame handling. Build the `Tests/Fixtures/` pcap corpus (WEP, WPA2, WPA3, OWE, Enterprise, PMF, hidden, 6/6E/7 beacons).
- **Acceptance:** `protocol-fixture-test-agent`: every protocol claim has ≥1 fixture or a documented API limitation; malformed frames don't crash; display strings correct. No overclaiming live support where only imported-pcap support exists.

### S2.2 — Imported pcap/pcapng as first-class offline mode **[blocked: S1.3]**
- **Milestone:** 7 · **Impl:** capture-backend-agent · **Rev:** capture-safety-reviewer · **Val:** capture-validation-agent · **Deps:** S1.3
- **Scope:** Wire a File-menu import action to `readPCAPDump:` (currently scriptable-only), verify pcapng, route parsed frames through the protocol model. Offline analysis must work with zero live-capture capability.
- **Acceptance:** Importing a golden pcap yields expected network/client counts (`capture-validation-agent`); pcapng verified or limitation documented.

### S2.3 — Crypto/cracking modernization **[blocked: S0.5]**
- **Milestone:** 6 · **Impl:** wifi-protocol-agent · **Rev:** wireless-protocol-reviewer · **Val:** protocol-fixture-test-agent · **Deps:** S0.5
- **Scope:** Migrate PMK/MIC/SHA1/MD5/MD4 from PolarSSL to CommonCrypto/CryptoKit (keep MD4/DES as LEAP attack primitives); fix the WPA 64-bit pointer-aliasing (`WaveNetWPACrack.m:115`), the weak-scheduling tautology guard (`ScanControllerScriptable.m:718`) and the `keyLen104` copy-paste bug; bounds-check wordlist readers.
- **Acceptance:** Each attack recovers the known key from a fixture capture; weak-scheduling path is reachable again; no buffer over-reads. (CPU-only; no hardware dependency.)

### S2.4 — Kismet remote/drone backend modernization **[blocked: S1.3]**
- **Milestone:** 7 · **Impl:** capture-backend-agent · **Rev:** capture-safety-reviewer · **Val:** capture-validation-agent · **Deps:** S1.3
- **Scope:** Rewrite `WaveDriverKismet*` raw sockets onto Network.framework; verify/refresh the protocol against a modern Kismet; add `com.apple.security.network.client`.
- **Acceptance:** Connects to a modern Kismet server in a lab and ingests networks (`capture-validation-agent`); plaintext-only, no silent capture failure.

---

## Wave 3 — Native MacBook surfaces (Milestone 2 breadth)

Each is an independent slice; **Impl:** macbook-native-surface-agent · **Rev:** privacy-reviewer · **Val:** macbook-native-validation-agent · **Deps:** S1.3.

- **S3.1 — BLE inventory** (CoreBluetooth advertisement scan + GATT for user-selected device). *Accept:* pass/fail/permission-blocked status; Bluetooth usage string + auth.
- **S3.2 — USB/HID/serial inventory** (IOKit, read-only). *Accept:* enumerates VID/PID/class/serial; serial pucks discoverable for GPS.
- **S3.3 — LAN discovery** (Bonjour/mDNS/DNS-SD passive; opt-in ping sweep, rate-limited). *Accept:* service inventory on the joined network; no stealth behavior; privacy review of host/IP handling.
- **S3.4 — Local interface inventory** (Wi-Fi/Ethernet/Thunderbolt/VPN/AWDL + IP config). *Accept:* matches `ifconfig`/system for a known setup.

---

## Wave 4 — Safety guardrails (gate for all active features)

### S4.1 — Campaign scope + audit log + emergency stop **[blocked: S1.3]**
- **Milestone:** 9 · **Impl:** privacy-safety-agent · **Rev:** security-abuse-reviewer · **Val:** safety-policy-test-agent · **Deps:** S1.3
- **Scope:** `Sources/Safety/*`, `Sources/Campaigns/*`: authorized-campaign model with scope (SSIDs/BSSIDs/clients/adapters/channels/time window), always-visible emergency stop, audit log, redaction settings, server-export opt-in (default off), local-only storage, project encryption option.
- **Acceptance:** `safety-policy-test-agent`: active features **fail closed** without scope; emergency stop halts; audit entries recorded; redaction applied. Mandatory `security-abuse-reviewer` sign-off.

### S4.2 — Gate inject/deauth/AP behind capability + scope **[blocked: S4.1, S1.1]**
- **Milestone:** 9 · **Impl:** privacy-safety-agent · **Rev:** security-abuse-reviewer + capture-safety-reviewer · **Val:** safety-policy-test-agent · **Deps:** S4.1, S1.1
- **Scope:** Wire the 🔌 `hardware-required` active features (inject/deauth, and any probe-confirmed monitor/AP) so they require both a capability=true and an authorized campaign scope.
- **Acceptance:** Without adapter → disabled with reason; with adapter but no scope → disabled; with both → allowed and audited. Tests fail closed.

---

## Wave 5 — UI, reporting, lab features, release

Outlined (expanded into slices when their dependencies are near):

- **S5.x — Modern macOS UI** (Milestone 8): sidebar/toolbar/dashboard, capability dashboard, inspector, permission/unsupported states. *Impl:* modern-macos-ui-agent · *Rev:* macos-hig-reviewer · *Val:* ui-smoke-test-agent · *Deps:* S1.3 + the data models. Includes porting traffic graph off deprecated OpenGL/BIGL and map off BIGeneric.
- **S6.x — Project/report/export** (Milestone 12): `.kismac` bundle with secure coding, unified report, evidence timeline with source labels, redaction/encryption. *Impl:* project-reporting-agent · *Rev:* privacy-reviewer + architecture-invariants-reviewer · *Val:* report-export-test-agent · *Deps:* S4.1.
- **S7.x — Authorized lab features** (Milestone 10): Pineapple-style workflows. *Impl:* pineapple-lab-features-agent · *Rev:* security-abuse-reviewer + capture-safety-reviewer · *Val:* authorized-lab-validation-agent. **[blocked]** — hard dependency: S4.1 + S1.3 + S1.1 must all land first.
- **S8.x — Signing/notarization/CI** (Milestone 14): Developer ID, hardened runtime, notarization, DMG, CI, submodule patch validation. *Impl:* release-engineering-agent · *Rev:* release-reviewer · *Val:* xcode-build-validator + notarization-validation-agent.

---

## Dependency summary

```
S0.1 → S0.6 → S0.2,S0.3,S0.4 → S0.5 ─┬─→ S1.1 ─┬─→ S1.3 ─┬─→ S1.4
       (re-run S0.1 after S0.6+S0.2)  │         │         │
                              │         │         ├─→ S2.1, S2.2, S2.4
                              ├─→ S1.2  │         ├─→ S3.1..S3.4
                              │         │         └─→ S4.1 ─→ S4.2 ─→ S7.x
                              └─────────┴─→ S2.3        S4.1 ─→ S6.x
                                                        S1.3 ─→ S5.x ─→ S8.x
```

Critical path: **S0.x (compile baseline) → S1.1 (probe) → S1.3 (capability engine)**.
Almost everything depends on the capability engine; the probe is what retires the
🔍 `needs-probe` rows. Start Wave 0 now.

## PR gate (every slice)

Per `docs/subagent-orchestration.md`: one implementation owner, one independent
reviewer, one validation owner, **plus** build evidence (`xcode-build-validator`) if
code changed, capability-matrix update if hardware/API behavior changed, parity-matrix
update (`docs/original-feature-parity.md`) if original behavior changed, `security-abuse-reviewer`
if active cyber functionality changed, `privacy-reviewer` if identifiers/locations/
captures/reports/exports changed.
