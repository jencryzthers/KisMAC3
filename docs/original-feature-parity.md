# KisMac3 — Original KisMAC Parity Audit (Milestone 0)

Deliverable for **Milestone 0** of `docs/modernization-plan.md`. Inventories every
legacy KisMAC2 capability before it is replaced or removed, with source files,
current runtime status, MacBook (built-in-Wi-Fi) status, external-adapter status,
required permissions, test steps, and a final parity decision.

Produced by `kismac-program-lead` from a five-cluster code audit of the
`setup/subagent-orchestration` branch. Evidence is `file:line`-cited inline; this
is a synthesis, not a re-derivation — re-audit a feature before acting on it.

> **Build-confirmed correction (post-S0.6, see `docs/build-triage.md`).** The static
> audit predicted several *compile-breakers*. A green build on Xcode 26.5 / macOS 27.0
> proved otherwise: **the KisMac2 Debug build succeeds with 0 hard errors.** The
> "removed API" items below are in fact **deprecated-but-present** (warnings), and
> `WirelessCryptMD5` **still ships in the private `Apple80211` framework and links**.
> Rows and blockers affected by this are corrected inline and flagged `[corrected]`.

## Decision vocabulary

| Tag | Meaning |
|-----|---------|
| ✅ `working` | Implemented and expected to function on a supported target (pending validation). |
| 🔧 `modernized` | Must be re-implemented with a modern macOS API; the path is clear and feasible. |
| 🔌 `hardware-required` | Only works with specific external hardware (USB Wi-Fi adapter, GPS puck, etc.). |
| 🚫 `macOS-blocked` | Modern macOS prevents the behavior on MacBook built-in hardware. |
| 🗑 `removed` | Intentionally dropped, with reason. |
| 🔍 `needs-probe` | **Disposition deferred to the Milestone 1 hardware probe.** Per the non-negotiables, we do **not** claim support until the probe proves it on a real machine. |

`MacBook` = behavior on built-in Wi-Fi/Bluetooth/sensors. `Adapter` = behavior with supported external hardware.

---

## Cross-cutting blockers (affect many features)

These recur throughout and should be tackled as shared infrastructure, not per-feature:

1. **Monitor-mode capture path is dead.** Passive capture relies on `libpcap` over a BPF device whose permissions are forced by a privileged `/bin/chmod 0777 /dev/bpf*` helper (`WaveDriverAirportExtreme.m:182-190`), plus CoreWLAN channel/monitor calls that modern macOS restricts. The whole passive chain (passive scan, channel hop, hidden-SSID, live capture) is gated on this → **`needs-probe`**.
2. **All injection/deauth needs legacy USB adapters.** Transmit goes through the deprecated IOKit USB user-client API (`IOUSBDeviceInterface197`/`IOUSBInterfaceInterface220`) in `USBJack` (`WaveDriverUSB.mm`, `*Jack.mm`). No DriverKit equivalent exists; the built-in card cannot inject (`pcap_inject` commented out). → **`hardware-required`** + driver rewrite.
3. **Bundled crypto = PolarSSL** (`Subprojects/polarssl`, end-of-life, now mbedTLS) + local DES/FCS. Cracking math is sound but should migrate to CommonCrypto/CryptoKit for performance, signing, and notarization.
4. **Private Apple80211 dependency `[corrected]`.** `WaveNetWEPWordlist.m:341` calls `WirelessCryptMD5` from the **private** `Apple80211` framework. Contrary to the original prediction, this symbol **still ships and links on macOS 27** (the app builds), and `Apple80211` is linked in the pbxproj (4 refs). It is a *private-API dependency*, not a dead one — a notarization/longevity risk that the `objc-appkit-reviewer` rule ("no private API dependency") flags. Migrate off it; don't treat it as removed. (`WirelessEncrypt` call sites remain commented out.)
5. **Deprecated (not removed) APIs everywhere `[corrected]`:** all of these currently **compile as warnings** on Xcode 26.5 — `NSDate descriptionWithCalendarFormat:`, `NSKeyedUnarchiver unarchiveObjectWith…` (insecure), `NSBeginAlertSheet`/`NSRunCriticalAlertPanel`, `IOMasterPort`, `gethostbyname`/`inet_addr`, Carbon Speech/QuickTime Music, OpenGL (BIGL), private `_toolbarView` SPI. They are tech-debt/modernization targets, **not** build blockers (295 deprecation warnings in KisMac2 sources per `docs/build-triage.md`).
6. **No entitlements / no Info.plist usage strings.** No `*.entitlements`, no `NSLocationWhenInUseUsageDescription`, no `NSBluetoothAlwaysUsageDescription`, no Automation/Contacts strings, no `com.apple.security.network.client`. Every Location/Network/Contacts use currently fails closed on modern macOS.
7. **Dead bundled Growl + dead remote endpoints.** `Resources/Growl.framework` is still linked/CodeSignOnCopy'd though code no longer references it. `kismac-ng.org`/`trac`/`forum`, TerraServer/Expedia/Map24/Census map providers, and the crash-report endpoint are all defunct.
8. **Audio-feedback regression.** Sounds/geiger/voice prefs (`PrefsSounds.m`) have **zero runtime consumers** — the "alert on network found" behavior is already lost in the legacy tree.

---

## Cluster 1 — Wi-Fi capture core

| Feature | Key source | Current status | MacBook | Adapter | Decision |
|---|---|---|---|---|---|
| Built-in AirPort (active scan) | `WaveDriverAirport.m`, `WaveScanner.mm:116` | Works via CoreWLAN `scanForNetworksWithName:` | Location-gated scan | n/a | 🔧 `modernized` (CWWiFiClient, Location auth, throttle the busy-loop) |
| AirPort Extreme (passive/monitor) | `WaveDriverAirportExtreme.m` | Monitor via pcap+chmod BPF hack | unknown on modern OS | likely via adapter | 🔍 `needs-probe` (built-in likely 🚫) |
| Passive scan mode | `WaveScanner.mm:136` | Frame loop over monitor source | depends on monitor | adapter | 🔍 `needs-probe`; 🔧 via imported pcap |
| Active scan mode | `WaveScanner.mm:116`, `WaveDriverAirport.m:137` | CoreWLAN list scan | Location-gated | n/a | 🔧 `modernized` |
| Channel hopping | `WaveDriver.m:285`, `WaveScanner.mm:394` | Timer + `setWLANChannel:` | restricted on modern OS | adapter | 🔍 `needs-probe` (built-in likely 🚫) |
| Hidden SSID discovery | `WaveNet.mm:1300-1342` | Passive byproduct only | depends on monitor | adapter | 🔍 `needs-probe`; 🔧 via imported pcap |
| Packet capture & pcap dump | `WaveDriverAirportExtreme.m:177`, `WavePcapDump.m` | libpcap live + dump | depends on monitor | adapter | 🔍 `needs-probe` (live); 🔧 import/export of pcap |
| Packet reinjection | `WavePluginInjecting.m`, `WaveDriverUSB.mm:195`, `*Jack.mm` | USB adapters only | no built-in path | legacy USB + DriverKit rewrite | 🔌 `hardware-required` (built-in 🚫) |
| Deauthentication | `WavePluginDeauthentication.m`, `WaveScanner.mm:610` | USB adapters only | no built-in path | legacy USB + DriverKit rewrite | 🔌 `hardware-required` (built-in 🚫) |

**Permissions:** Location (SSID/BSSID visibility) for any scan; root/authorized-helper for BPF; IOKit USB device access + supported adapter for inject/deauth.

**Test steps:**
- Active scan: launch, start scan, confirm AP list populates with BSSIDs *after* granting Location; deny Location → BSSIDs hidden with a clear reason (no silent failure).
- Passive/monitor/channel-hop/live-capture: run the **Milestone 1 probe** on real Intel + Apple Silicon MacBooks; record monitor-mode/channel-set/datalink support; do **not** mark working until the probe reports it.
- Inject/deauth: with a supported USB adapter present → "Test Injection" succeeds; without adapter → action is disabled with a capability reason (never a crash). These are active features → require `security-abuse-reviewer` sign-off and authorized-campaign scope.

---

## Cluster 2 — Crypto & cracking

| Feature | Key source | Current status | MacBook | Adapter | Decision |
|---|---|---|---|---|---|
| WEP weak-IV detection | `WavePacket.mm:718`, `WaveNet.mm:965`, `WaveWeakContainer.m` | Functional, manual malloc tables | CPU-only | n/a | 🔧 `modernized` (ARC/buffer cleanup) |
| WEP brute force (low/alpha/all) | `WaveNetWEPCrack.m:38,161,290` | Functional, single-thread | CPU-only | n/a | 🔧 `modernized` |
| WEP Newsham 21-bit | `WaveNetWEPCrack.m:405` | Functional | CPU-only | n/a | 🔧 `modernized` |
| WEP weak scheduling (FMS/KoreK) `[S2.3]` | `AirCrackWrapper.m`, `WaveNetWEPWeakCrack.m` | **Reachable again** — tautology guard fixed (`||`→`&&`, `ScanControllerScriptable.m:766`) so a 40/104-bit/all key length actually launches the FMS/KoreK attack; `keyLenAll` copy-paste fixed (`WaveNetWEPWeakCrack.m:101` now tries `keyLen104bit`) | CPU-only | n/a | ✅ `working` (S2.3 — 2 reachability/copy-paste bugs fixed; AirCrack engine still links PolarSSL — out of crack-call-path scope) |
| WPA handshake detection | `WavePacket.mm:944`, `WaveClient.m:131` | Functional (offset parsing) | passive capture | adapter | 🔧 `modernized` |
| Modern security decode (WPA3-SAE/transition, OWE, Enterprise, PMF) `[S2.1]` | `Sources/Core/KMProtocolMetadata.{h,m}`, `WavePacket.mm parseTaggedData:`, `WaveNet.mm parsePacket:` | **Decodes on imported pcaps** — RSN IE (48) + vendor WPA IE (221) → WPA2/WPA2-Ent/WPA3-SAE/WPA3-Transition/WPA3-Ent/OWE + PMF (MFPC/MFPR); display strings via `-[WaveNet securityString]` | offline decode of imported frames | offline | ✅ `working` (S2.1 — imported-pcap decode only; **not** a live-monitor claim; 11 protocol fixtures + `KISMAC_PROTO_SELFTEST`) |
| Modern PHY/generation decode (Wi-Fi 4/5/6/6E/7) `[S2.1]` | `Sources/Core/KMProtocolMetadata.{h,m}` | **Decodes on imported pcaps** — HT(45)/VHT(191)/HE(ext35)/6 GHz(ext59)/EHT(ext108) → Wi-Fi 4/5/6/6E/7 + channel width; via `-[WaveNet phyString]` | offline decode of imported frames | offline | ✅ `working` (S2.1 — HE/EHT width not parsed; see `Tests/Fixtures/README.md` limitations) |
| WPA wordlist cracking `[S2.3]` | `WaveNetWPACrack.m`, `WPA.m` | **CommonCrypto** — PMK via `CCKeyDerivationPBKDF` (kCCPBKDF2 / kCCPRFHmacAlgSHA1, 4096, SSID salt); HMAC-MD5/SHA1 MIC via `CC_MD5`/`CC_SHA1`. PolarSSL no longer called. 64-bit strict-aliasing UB **eliminated** (the hand-rolled `fastF`/`prepared_hmac_sha1` digest XOR through `(NSInteger*)` casts was deleted, not patched). `fgets`/empty-line wordlist bounds hardened | CPU-only | n/a | ✅ `working` (S2.3 — CommonCrypto migration; aliasing + wordlist bounds fixed; PMK matches IEEE 802.11i vector, asserted by `KISMAC_CRYPTO_SELFTEST`) |
| LEAP capture + crack `[S2.3]` | `WavePacket.mm:1033`, `WaveNetLEAPCrack.m`, `LEAP.m` | **CommonCrypto** — `NtPasswordHash` MD4 via `CC_MD4`; DES (`DESSupport.c`) kept as the MS-CHAP attack primitive. PolarSSL no longer called. Empty-line `wrd[i-1]` underflow + unchecked `fgets` hardened | CPU-only | n/a | ✅ `working` (S2.3 — MD4→CommonCrypto, DES kept; wordlist bounds fixed; NtPasswordHash + DES round-trip asserted by `KISMAC_CRYPTO_SELFTEST`) |
| WEP "Apple" wordlist (40/104/MD5) `[S2.3]` | `WaveNetWEPWordlist.m:341`, `WaveHelper.m WirelessCryptMD5` | **MD5 keying migrated to CommonCrypto** (`CC_MD5`), dropping PolarSSL from this crack path. The wordlist-driver private-`Apple80211` `WirelessCryptMD5` dependency note still stands for the live key-injection path | CPU-only | n/a | 🔧 `modernized` (S2.3 — MD5 derivation on CommonCrypto; private-API longevity risk on the injection path unchanged) |

**Permissions:** none for the math (runs on captured data); wordlist file read via NSOpenPanel (security-scoped under sandbox).

**Test steps:** drive each attack from a fixture capture with a known key → assert recovered key matches (`protocol-fixture-test-agent`). Specifically regression-test the weak-scheduling path that the tautology guard currently disables (build-confirmed at `ScanControllerScriptable.m:718-719`). For the three "Apple" WEP wordlist verbs, confirm they still function via the private Apple80211 path, then track their migration off the private symbol (do not ship a private-API dependency through notarization).

---

## Cluster 3 — Capture I/O & external integration

| Feature | Key source | Current status | Decision |
|---|---|---|---|
| Kismet drone/client `[S2.4]` | `WaveDriverKismet.m`, `WaveDriverKismetDrone.m`, `Sources/WaveDrivers/KMKismetTransport.{h,m}` | **Transport modernized onto Network.framework `NWConnection`** (plaintext TCP) — replaces raw BSD `socket`/`connect`/blocking `read`; IPv4+IPv6; non-blocking pull via a bounded buffer; **no silent failure** (refused/unreachable/timeout/drop → `NSAlert`+log, never hangs). Bugs fixed: drone `memset`-after-set zeroing `sin_addr`, `inet_addr` IPv4-only, blocking `read`/`select` on the capture flow, over-broad `@try` masking errors, payload over-read clamp. Protocol still the **legacy ~2006** `*NETWORK:`/drone-v9 streams. `kismetRemoteCapture` capability now reports **available** (user-initiated remote source, fails closed). | ✅ `working` (S2.4 — legacy plaintext only; validated against a local mock server via `KISMAC_KISMET_SELFTEST` + `Tests/Fixtures/mock_kismet_server.py`). **⚠️ Modern Kismet 3.x (REST/websocket/JSON over TLS) is NOT supported — a separate future slice needing a live server to validate. `com.apple.security.network.client` deferred to S8.x sandboxing.** |
| Import pcap / dump | `WaveScanner.mm:443`, `ScanControllerScriptable.m:386`, `BridgeController.m:importPCPFile:` | `pcap_open_offline` reuses parse pipeline; File→Import→PCAP Dump wired to `readPCAPDump:` (offline/passive); **pcapng reads transparently** | ✅ `working` (S2.2 — File-menu action restricted to pcap/pcapng/cap/dump; golden fixture + headless self-test `KISMAC_PCAP_IMPORT_SELFTEST`; modern-decode enrichment lands with S2.1) |
| Import Kismet XML / NetStumbler | `KismetXMLImporter.m`, `WaveStorageController.m:262` | NSXMLParser / text parse | 🔧 `modernized` (harden untrusted parsing) |
| Native `.kismac` load | `WaveStorageController.m:83`, BIGeneric | BICompressor + insecure unarchiver fallback | 🔧 `modernized` (secure-coding unarchiver) |
| Export (NS / KML / MacStumbler / PDF / JPEG) | `WaveStorageController.m:456-807`, `ScanControllerMenus.m` | C stdio writers | 🔧 `modernized` (**won't compile** — `descriptionWithCalendarFormat:`; fix buffer overflows in KML) |
| Decrypt capture workflow | (= crack vs captures) | See Cluster 2 | 🔧 `modernized` (no separate frame-decrypt feature exists) |
| Server export of captures | `ScanControllerMenus.m:273` (empty stub), `HTTPStream.m` (dead) | Non-functional | 🗑 `removed` (stub + dead transport + dead endpoint) |
| Crash-report upload | `CrashReportController.m:88` | POSTs logs + Address Book email to dead `kismac-ng.org` over HTTP | 🗑 `removed` (privacy + dead endpoint; replace later if wanted, opt-in) |

**Permissions:** outbound network (Kismet) → `com.apple.security.network.client` *only under App Sandbox; app is currently unsandboxed so no entitlement is needed/added — see S2.4/S8.x*; file read/write via panels; crash reporter used Contacts (`ABAddressBook`).

**Test steps:** import a known pcap → network/client counts match a golden value (`capture-validation-agent`); round-trip `.kismac` save/open with no data loss (`report-export-test-agent`); each export opens in its target app; **Kismet (S2.4): connect against the local mock server (`Tests/Fixtures/mock_kismet_server.py`) via `KISMAC_KISMET_SELFTEST=1` and confirm the modernized transport ingests the fixture networks + a refused connection fails closed with a reason — DONE/PASS. A modern Kismet 3.x server is a separate future slice (no live server available).** Confirm server-export and crash-upload paths are gone, not silently failing.

---

## Cluster 4 — GPS, mapping & graphing

| Feature | Key source | Current status | MacBook | Adapter | Decision |
|---|---|---|---|---|---|
| Serial GPS | `GPSController.m:1122`, `PrefsGPS.m` | termios @ hardcoded 4800; IOKit enum | via USB-serial puck | 🔌 puck | 🔧 `modernized` (`IOMainPort`, configurable baud) |
| GPSd | `GPSController.m:1241,829` | **Legacy `PMVTAQ` protocol — dead vs modern gpsd** | network | network | 🔧 `modernized` (rewrite to gpsd JSON) |
| NMEA parsing | `GPSController.m:520` | `$GP*` only | n/a | puck | 🔧 `modernized` (add `$GN/$GL/$GA` multi-GNSS; enable checksum) |
| Map import from server | `MapDownload.m` | **All provider URLs dead; HTTP/ATS-blocked** | n/a | n/a | 🗑 `removed` → replace with MapKit |
| Map calibration | `MapView.m:286-343` | Two-point linear, sound | works | n/a | 🔧 `modernized` (port off BIGeneric) |
| Waypoint plotting | `MapView.m`, `PointView.*` | Custom BIGeneric views | works | n/a | 🔧 `modernized` |
| Current-position tracking | `GPSController.m:1384`, `MapViewPrivate.m:82` | CoreLocation present but **no auth, no Info.plist string, deprecated delegate** | needs CL auth | puck/GPSd | 🔧 `modernized` (auth flow, usage string, `didUpdateLocations:`) |
| Traffic graphing | `TrafficController.mm`, BIGL | OpenGL-based (deprecated) | works | n/a | 🔧 `modernized` (Metal / SwiftUI Charts) |
| Per-channel packet counts | `WaveNet.mm:886,1506` | Pure counting | works | n/a | ✅ `working` |

**Permissions:** Location (CoreLocation) — currently unrequested; serial device access (hardened runtime); network (GPSd).

**Test steps:** feed recorded NMEA (incl. multi-GNSS) → assert parsed fix (`protocol-fixture-test-agent`); CoreLocation path → assert auth prompt appears and denial shows remediation (`macbook-native-validation-agent`); calibrate a known map image and assert pixel↔coordinate mapping at reference points; render graph for a fixture session without OpenGL.

---

## Cluster 5 — App, session, UI & automation

| Feature | Key source | Current status | Decision |
|---|---|---|---|
| Save/open `.kismac` sessions | `WaveStorageController.m`, `ScanControllerScriptable.m` | Bespoke (not NSDocument); insecure unarchiver | 🔧 `modernized` (secure coding; consider NSDocument) |
| Notifications | `GrowlController.m` | Growl removed → `NSUserNotification` (deprecated); most methods stubbed; only scan-start fires | 🔧 `modernized` (UserNotifications framework; strip bundled Growl.framework from pbxproj) |
| Sounds / geiger / voice | `PrefsSounds.m`, `BISpeechController.m` | Configurable but **no runtime consumer** (regression); Carbon Speech | 🔧 `modernized` (restore audio feedback via AVSpeechSynthesizer/AVFoundation) — or 🗑 if descoped |
| MIDI plugin | `WavePluginMidi.m` | `#ifdef __i386__` Carbon QuickTime → no-op on modern builds | 🗑 `removed` |
| AppleScript automation | `ScanControllerScriptable.m`, Info.plist `NSAppleScriptEnabled` | Scriptable category present but **no `.sdef`/terminology, no AE registration** | 🔧 `modernized` (author `.sdef`; Automation usage string) |
| Preference panes (7: Scanning, Traffic, Filter, Sounds, Driver, GPS, Map; Advanced disabled) | `PrefsController.m`, `Resources/XIBs` | Private `_toolbarView` SPI; Advanced half-wired | 🔧 `modernized` (rebuild; re-wire or remove Advanced) |
| Menu commands | `MainMenu.xib`, `ScanControllerMenus.m` | Deprecated sheets, manual fullscreen, dead Help/Forum URLs, `/test.tiff` debug write | 🔧 `modernized` |
| Help book | `Resources/Help/...`, `updateHelpIndex.command` | Stale content (KisMAC 0.3.x), dead links, obsolete `.helpindex` toolchain | 🔧 `modernized` (rewrite) or 🗑 (replace with online docs) |

**Permissions:** Notifications authorization; Automation (Apple Events) TCC for AppleScript; file access via panels.

**Test steps:** save/open round-trip (`report-export-test-agent`); trigger a notification and confirm it appears with authorization handled; run a sample AppleScript verb and confirm it resolves; open every pref pane without crash (`ui-smoke-test-agent`); walk the menu bar for dead/again-crashing items.

---

## Parity scorecard (counts)

- 🔧 `modernized`: the large majority — most features have a clear modern path.
- 🔍 `needs-probe`: built-in passive/monitor/channel-hop/hidden-SSID/live-capture (6) — **blocked on Milestone 1**.
- 🔌 `hardware-required`: injection, deauth (built-in 🚫).
- 🗑 `removed`: server export, crash upload, MIDI, server map download (4). *(The "Apple" WEP wordlist attacks were reclassified 🗑→🔧 after the build proved `WirelessCryptMD5` still links.)*
- ✅ `working` (pending validation): active-scan plumbing, pcap import, per-channel counts. **Whole-app build: green on Xcode 26.5 / macOS 27 (0 hard errors).**

## What this unblocks

1. The 🔍 set is the entire justification for **Milestone 1 (hardware probe)** — nothing in the passive/monitor family may be claimed until it runs on real Intel + Apple Silicon MacBooks.
2. The 🗑 set should be deleted/quarantined early (dead Growl framework, dead endpoints, i386 MIDI) to shrink the surface and clear notarization blockers.
3. Build stabilization (Milestone 4 / Wave 0) is **further along than predicted**: the app already builds green (post-S0.6). What remains is *deprecation cleanup* (≈295 KisMac2 warnings) and *dead-code/private-API removal* — not fixing compile errors. S0.2–S0.5 are re-scoped accordingly in `docs/task-slices.md`.
