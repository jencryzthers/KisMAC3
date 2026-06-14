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
6. **No entitlements / no Info.plist usage strings.** *(partly resolved)* `NSLocationWhenInUseUsageDescription` was added in **S1.2**, `NSBluetoothAlwaysUsageDescription` in **S3.1**, and `NSLocalNetworkUsageDescription` + `NSBonjourServices` (20 passive DNS-SD types) in **S3.3** (honest wording: passive local service inventory for authorized auditing, local-only). Still missing: `*.entitlements`, Automation/Contacts strings, `com.apple.security.network.client` (the latter only matters under the App Sandbox = S8.x). Location/Bluetooth now surface a real auth prompt + remediation instead of failing closed silently.
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
| Packet reinjection | `WavePluginInjecting.m`, `WaveDriverUSB.mm:195`, `*Jack.mm`; gated `[S4.2]` `WaveScanner.mm -tryToInject:`/`-injectionTest:withClient:` + `-[ScanController allowActiveOperation:…]` | USB adapters only | no built-in path | legacy USB + DriverKit rewrite | 🔌 `hardware-required` (built-in 🚫); **gated on adapter + scope + audit `[S4.2]`** |
| Deauthentication | `WavePluginDeauthentication.m`, `WaveScanner.mm:610`; gated `[S4.2]` `-deauthenticateNetwork:atInterval:`/`-setDeauthingAll:` + `-[ScanController allowActiveOperation:…]` | USB adapters only | no built-in path | legacy USB + DriverKit rewrite | 🔌 `hardware-required` (built-in 🚫); **gated on adapter + scope + audit `[S4.2]`** |

**Permissions:** Location (SSID/BSSID visibility) for any scan; root/authorized-helper for BPF; IOKit USB device access + supported adapter for inject/deauth.

**Test steps:**
- Active scan: launch, start scan, confirm AP list populates with BSSIDs *after* granting Location; deny Location → BSSIDs hidden with a clear reason (no silent failure).
- Passive/monitor/channel-hop/live-capture: run the **Milestone 1 probe** on real Intel + Apple Silicon MacBooks; record monitor-mode/channel-set/datalink support; do **not** mark working until the probe reports it.
- Inject/deauth: with a supported USB adapter present → "Test Injection" succeeds; without adapter → action is disabled with a capability reason (never a crash). These are active features → require `security-abuse-reviewer` sign-off and authorized-campaign scope. **`[S4.2]` implemented:** gated on adapter + scope + audit at both the engine (3-way: `unsupportedAdapter`/`activeLabScopeMissing`/`available`) and a hard op-site guard that also requires the **target** in scope and audits every attempt/refusal; fails closed. Real transmit still needs real USB hardware (deferred).

> **Safety guardrails `[S4.1]` (Milestone 9):** the authorized-campaign **scope** (SSIDs/BSSIDs/clients/adapters/channels/time window), **append-only audit log**, always-available **emergency stop**, and **redaction** settings now exist (`Sources/Campaigns/KMCampaign{,Scope}.{h,m}`, `Sources/Safety/KM{CampaignManager,AuditLog,RedactionSettings,PrivacySettings}.{h,m}`). The capability engine's active/offensive gate (apMode/frameInjection/deauth) is wired to the **real** scope provider (`KMActiveCampaignScopeProvider`) via `-[ScanController rebuildCapabilityEngine]` → it is available ONLY with an explicitly authorized, in-window, non-emergency-stopped campaign and **fails closed by default** (no campaign → `activeLabScopeMissing`). Emergency stop immediately deactivates scope (all active features fail closed at once) and is audited. Privacy defaults: local-only storage ON, **server export opt-in OFF by default**, project-encryption flag present (crypto = S6.x). Verified by `KISMAC_SAFETY_SELFTEST=1` (35/35 PASS). Actually gating the 🔌 inject/deauth/AP features behind capability **and** scope is **S4.2**; this slice provides the machinery only and adds no turnkey abuse path.

> **Active-op gate `[S4.2]` (Milestone 9):** inject/deauth/AP are now gated on **adapter + scope + audit** at two layers. (1) The capability engine gained an **adapter-presence input** (`KMAdapterPresenceProviding`; real impl `KMWaveDriverAdapterPresenceProvider` backed by `-[WaveDriver allowsInjection]`, fail-closed default NO), making the offensive trio a **3-way**: no injection-capable adapter ⇒ `unsupportedAdapter`; adapter but no campaign scope ⇒ `activeLabScopeMissing`; adapter **and** authorized in-window scope ⇒ `available`. The built-in MacBook card reports NO adapter, so on a stock Mac these stay `unsupportedAdapter`. (2) A **hard op-site guard** `-[ScanController allowActiveOperation:feature:target:targetIsClient:]` is invoked at the ACTUAL `WaveScanner` op entry points (`-tryToInject:`, `-deauthenticateNetwork:atInterval:`, `-injectionTest:withClient:`, `-setDeauthingAll:`) and **fails closed**: it requires the engine to report the feature `available` (else NSAlert + DBNSLog + audited refusal) **and** the target to be in campaign scope (`scopeContainsBSSID:` for the AP / `scopeContainsClientMAC:` for a targeted client) — out-of-scope ⇒ refused + audited even with adapter+scope. Broadcast deauth-all passes a nil target ⇒ fails closed (can't be constrained to one scoped BSSID). On allow, a `KMAuditLog` active-operation entry is recorded before execution. Emergency stop drops scope ⇒ all refuse at once. **No transmit on built-in hardware and no turnkey path** — the GATE only; real transmit still needs a real USB adapter (deferred, hardware). Verified by `KISMAC_ACTIVEGATE_SELFTEST=1` (full matrix PASS incl. target-out-of-scope refusal + audit, e-stop fail-closed); no regressions.

> **Native BLE inventory `[S3.1]` (Milestone 2):** new MacBook-native CoreBluetooth surface in `Sources/Bluetooth/` — **previously unimplemented** (the engine's `bleScan`/`bleGattEnumeration` rows said "not yet implemented (S3.x)"). `KMBluetoothScanner` wraps `CBCentralManager` for a **passive BLE advertisement scan** (`scanForPeripheralsWithServices:nil`), accumulating one `KMBluetoothDevice` per peripheral identifier (UUID, local name, advertised service UUIDs, manufacturer data + parsed 16-bit company id, latest RSSI, connectability, observation count, first/last-seen). **Authorization** is read via the **class-level `CBManager.authorization`** (no radio spin / no prompt) and mapped to a clear state (authorized/denied/notDetermined/restricted) with remediation; `NSBluetoothAlwaysUsageDescription` added to `Info.plist`. **GATT enumeration** (`-enumerateGATTForDeviceIdentifier:timeout:completion:` → `KMGATTProfile` of services + characteristics) runs **only for a user-selected device** — **NEVER auto-connects** (privacy/safety); the interactive picker is S5.x. **Capability wiring:** the engine gained a `KMBluetoothPermissionProviding` input (real impl `KMBluetoothPermissionProvider` backed by `+[KMBluetoothScanner currentAuthorizationState]`, fail-closed default NOT-authorized), injected by `-[ScanController capabilityEngine]`/`-rebuildCapabilityEngine`. `bleScan` & `bleGattEnumeration` now resolve **honestly**: authorized ⇒ `available`; denied/notDetermined ⇒ `permissionMissing`; restricted ⇒ `macOSBlocked`. **Privacy:** local-only; BLE identifiers are sensitive — `KMBluetoothDevice`'s default `-description` and `-redactedDescriptionWithSettings:` mask the identifier + name via the S4.1 `KMRedactionSettings`, and the scanner's own logs redact identifiers; no off-device export. On **Mac15,8 / macOS 27 / arm64** the live CoreBluetooth auth is `notDetermined` ⇒ engine `bleScan = unavailable/permissionMissing`. Verified by `KISMAC_BLE_SELFTEST=1` (scanner init + auth read/map + engine 3-way gating across mocked authorizations and this machine's live auth + model redaction — all PASS). **Needs a signed build + a human Bluetooth grant** to exercise actual advertisements + GATT connect/enumerate (can't be granted headlessly for an unsigned ad-hoc binary); the self-test runs a brief live scan only when authorized. No regressions.

> **Native USB/HID/serial inventory `[S3.2]` (Milestone 2):** new MacBook-native IOKit surface in `Sources/HardwareInventory/` — **previously unimplemented** (the engine's `usbInventory`/`hidInventory`/`serialInventory` rows said "Native surface not yet implemented (S3.x)"). `KMHardwareInventory` does **one-shot, read-only** IORegistry enumeration: USB via `IOServiceMatching(kIOUSBDeviceClassName)` (IOUSBHostDevice fallback) → `KMUSBDevice` (idVendor/idProduct, vendor+product string descriptors, bDeviceClass/SubClass, USB serial, locationID + service path, negotiated Device Speed); HID via `kIOHIDDeviceKey` → `KMHIDDevice` (primary usagePage/usage → category Keyboard/Pointing device/Game controller/Consumer-remote, VID/PID, product, manufacturer, transport, serial); serial via `kIOSerialBSDServiceValue` → `KMSerialDevice` (IOTTYBaseName, `/dev/cu.*` callout + `/dev/tty.*` dialin paths, a USB-UART/GPS heuristic — ties to the serial-GPS path). **READ-ONLY / no permission:** the collector reads registry properties only (`IORegistryEntrySearchCFProperty`) — it **never** `IOServiceOpen`s, claims, configures, or writes any device, and macOS needs no authorization for registry reads, so the engine reports these **unconditionally available** (no longer "not implemented"). **Privacy:** USB/HID serials are stable hardware identifiers and are treated as sensitive — masked via the S4.1 `KMRedactionSettings`; each model's default `-description` is redacted and exposes `-redactedDescriptionWithSettings:`; serial-port device paths are not personal identifiers so they stay intact. On **Mac15,8 / macOS 27 / arm64** live enumeration: **usb=10, hid=30, serial=3**. Verified by `KISMAC_USBINV_SELFTEST=1` (REALLY enumerates this machine — IOKit needs no permission — logs counts + a redacted sample, asserts no crash, HID > 0 built-in keyboard/trackpad, serial not dumped raw, and engine usb/hid/serialInventory available — all PASS). **Deferred:** S5.x USB/HID/serial workspace UI; optional IOKit hotplug notifications (one-shot enumeration is the must-have, done). No regressions.

> **Native LAN discovery (Bonjour/mDNS/DNS-SD) `[S3.3]` (Milestone 2):** new MacBook-native Network.framework surface in `Sources/LAN/` — **previously unimplemented** (the engine's `lanDiscovery`/`bonjourInventory` rows said "Native surface not yet implemented (S3.x)"). `KMLANDiscovery` does **passive** service discovery on the **modern `nw_browser`** over a curated 20-type DNS-SD set (`_http`/`_https`/`_ssh`/`_sftp-ssh`/`_smb`/`_afpovertcp`/`_nfs`/`_ipp`/`_ipps`/`_printer`/`_pdl-datastream`/`_airplay`/`_raop`/`_companion-link`/`_rfb`/`_device-info`/`_homekit`/`_hap`/`_googlecast`/`_workstation`, all `._tcp`, domain `local.`) → one `KMLANService` per instance (name, type, domain, resolved host/port/IP addresses). Each instance is resolved via a short-lived `nw_connection` **cancelled at `ready` before any application data is sent** (passive resolution, NOT a probe). **PASSIVE ONLY / NO STEALTH:** only listens to mDNS announcements the OS already receives; `-pingSweepIsImplemented` honestly returns **NO** — the opt-in, default-OFF, rate-limited active sweep is a documented future hook, deliberately not built here. **Local Network privacy:** `NSLocalNetworkUsageDescription` (honest: passive local service inventory for authorized auditing, local-only) + `NSBonjourServices` (the 20 browsed types) added to `Info.plist`; macOS has no queryable Local-Network auth API, so the static engine reports these **available** (passive browsing is always permitted to attempt) and `KMLANDiscovery` surfaces the live posture via `-localNetworkState` (unknown→active once results flow, denied if the browser fails — UI can show permissionMissing remediation). **Privacy:** local-only; instance names/hostnames sensitive — masked via the S4.1 `redactHostname:`; IPs masked under the `redactHostnames` toggle (IPv4 keeps first octet, IPv6 a short prefix); `KMLANService` default `-description` is fully redacted, with `-redactedDescriptionWithSettings:`. On **Mac15,8 / macOS 27 / arm64 (unsigned ad-hoc)** the browser reaches `state=active` but enumerates **0 services** — the Local Network TCC grant requires a signed/registered app, so live results are signing-gated. Verified by `KISMAC_LAN_SELFTEST=1` (browser start/stop, ~3s passive browse, redacted sample, engine reports lanDiscovery/bonjourInventory available-or-permissionMissing — both honest PASSes — and no active/stealth path — all PASS). **Needs a signed build + a human Local Network grant** to enumerate real services. **Deferred:** opt-in rate-limited active ping sweep; S5.x LAN/Bonjour workspace UI. No regressions.

> **Local interface inventory `[S3.4]` (Milestone 2 — "Local interface inventory: Wi-Fi, Ethernet, Thunderbolt bridge, VPN, loopback, AWDL/peer interfaces when visible, and active IP configuration"):** new MacBook-native surface in `Sources/LAN/` — **previously absent** (KisMAC had no general local-interface inventory). `KMInterfaceInventory +currentInterfaces` enumerates every local interface via **`getifaddrs(3)`**, coalescing the per-family entries into one `KMNetworkInterface` per BSD name with: classified type (Wi-Fi / Ethernet / Thunderbolt-bridge / VPN(utun/ipsec/ppp) / AWDL-peer(awdl/llw) / loopback / other), up/running/broadcast/p2p/loopback flags, the link-layer MAC where present, IPv4/IPv6 addresses + IPv4 netmasks, and `isPrimary`. Primary/active status comes from **SystemConfiguration** (`State:/Network/Global/IPv4` `PrimaryInterface`, the default-route interface); the en* Wi-Fi-vs-Ethernet split is hardened by cross-checking **CoreWLAN**'s default interface name. **READ-ONLY / LOCAL-ONLY:** reads the kernel interface table + SCDynamicStore global state — no interface configured, no traffic, no host probe; macOS requires no authorization, so this is an always-available read-only data feature (no Milestone-3 capability row exists for it and none was invented). `SystemConfiguration.framework` was linked (it was not previously). **Privacy:** the link-layer MAC is masked via the S4.1 MAC transform (OUI kept) and the IPs via the hostname/IP transform (IPv4 first octet / IPv6 prefix kept), mirroring `KMLANService`; `KMNetworkInterface` default `-description` is fully redacted, with `-redactedDescriptionWithSettings:`. Verified by `KISMAC_IFACE_SELFTEST=1` (`KMInterfaceInventorySelfTest`): enumerate THIS machine, log a REDACTED per-interface summary, assert no crash, `lo0` present+loopback+up, ≥1 `en*` present, ≤1 primary flagged and matching SystemConfiguration's `PrimaryInterface`, the coalesced name set equals the `getifaddrs` ground truth, and no raw MAC leak — **all PASS**. On **Mac15,8 / macOS 27 / arm64**: 33 interfaces matching `ifconfig -l`, primary `en10` matching `route -n get default`, en0=Wi-Fi (CoreWLAN-confirmed), awdl0/llw0=AWDL, utun*=VPN, bridge0/en[2-6]=Thunderbolt-bridge, lo0=loopback — i.e. the inventory **matches `ifconfig`/system for the known setup** (the acceptance criterion). Unlike LAN/BLE this works fully headlessly and unsigned (no TCC grant needed). **Deferred:** S5.x interface workspace UI; optional SCDynamicStore live-change notifications. No regressions. **This completes Wave 3 (native MacBook surfaces, Milestone 2 breadth).**

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
