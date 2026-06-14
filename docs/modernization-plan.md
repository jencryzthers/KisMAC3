# KisMac3 Modern macOS Port Plan

## Goal

Port KisMac3 into a fully functional modern macOS wireless auditing application, with MacBook built-in Wi-Fi as the primary supported hardware target and external adapters as optional capability expansion.

The port is not complete until every original KisMAC feature and every planned modern feature has one of these outcomes:

- `working`: implemented and validated on supported hardware.
- `modernized`: replaced with an equivalent modern macOS implementation.
- `hardware-required`: works only with specific external hardware.
- `macOS-blocked`: latest macOS prevents the behavior on MacBook hardware.
- `removed`: intentionally removed with a documented reason.

## Definition Of Done

- Builds on latest macOS and current Xcode.
- Launches outside Xcode as a signed app.
- Core recon works on MacBook built-in Wi-Fi.
- Every MacBook-native feature has a working implementation, a test result, or a documented macOS limitation.
- No user-facing action fails silently.
- Every feature is backed by the capability engine.
- Every original KisMAC feature has a parity decision and validation result.
- Every modern protocol parser has fixture coverage.
- Every active lab feature requires explicit authorized scope.
- Reports accurately distinguish collected evidence from OS or hardware limitations.

## Milestone 0: Original KisMAC Parity Audit

Inventory every legacy capability before replacing or removing behavior:

- Built-in AirPort and AirPort Extreme support.
- Passive and active scan modes.
- Channel hopping.
- Hidden SSID discovery.
- Packet capture and pcap dump.
- WEP weak IV detection, brute force, Newsham, weak scheduling, and 21-bit workflows.
- WPA handshake detection and wordlist cracking integration.
- LEAP challenge/response capture and cracking support.
- Packet reinjection and deauthentication.
- Kismet drone/client integration.
- GPS, GPSd, and NMEA support.
- Map import, calibration, waypoint plotting, and current-position tracking.
- Traffic graphing and per-channel packet counts.
- Save/open KisMAC sessions.
- Import/export/decrypt capture workflows.
- Notifications, sounds, and MIDI plugin behavior.
- AppleScript automation.
- Server export.
- All preference panes, menu commands, and help-documented workflows.

Deliverable: `docs/original-feature-parity.md` with source files, current runtime status, MacBook status, external adapter status, required permissions, test steps, and final decision.

## Milestone 1: MacBook Hardware Capability Probe

MacBook built-in Wi-Fi is mandatory for the core product. Build a probe that reports what the current Mac and macOS version actually allow.

Probe:

- Apple Wi-Fi interface visibility.
- Location permission state for SSID/BSSID visibility.
- CoreWLAN scan support.
- 2.4 GHz, 5 GHz, 6 GHz, Wi-Fi 6/6E/7 visibility where hardware supports it.
- pcap open support.
- monitor-like capture support.
- datalink support.
- channel switching support.
- AP/SoftAP support.
- frame injection support.
- supported PHY/security metadata exposed by macOS.

Deliverable: runtime diagnostics panel plus persisted probe results per Mac model and OS version.

## Milestone 2: MacBook-Native Feasible Feature Set

Implement every useful security-audit feature that should be feasible with MacBook hardware alone before requiring external radios or adapters.

MacBook-native wireless and network features:

- Wi-Fi network discovery through supported macOS APIs.
- Current connected network inventory: SSID, BSSID where available, channel, RSSI/noise, PHY mode, transmit rate, country code, and security metadata exposed by macOS.
- Nearby AP inventory where scan APIs expose it.
- 2.4 GHz, 5 GHz, and 6 GHz visibility where the MacBook chipset and regulatory domain support it.
- Wi-Fi 4/5/6/6E/7 metadata display when exposed by CoreWLAN or imported capture data.
- WPA2, WPA3, OWE, Enterprise, and PMF interpretation from scan metadata or imported frames.
- Location-permission guided Wi-Fi recon, including exact remediation steps when macOS hides SSID/BSSID data.
- Local interface inventory: Wi-Fi, Ethernet, Thunderbolt bridge, VPN, loopback, AWDL/peer interfaces when visible, and active IP configuration.
- LAN discovery for the currently joined network using non-invasive methods: ARP/neighbor table, mDNS/Bonjour, DNS-SD, local hostname inventory, and optional ping sweep when explicitly enabled.
- Passive local-network service inventory via Bonjour/mDNS and DNS-SD.
- Local TCP/UDP service checks against user-scoped hosts, with rate limits and no stealth behavior.
- Packet capture on supported interfaces where macOS permissions allow it.
- Imported pcap/pcapng analysis as a first-class offline mode.
- Wireless Diagnostics capture import if direct automation is unavailable.
- Kismet remote/drone connection over normal networking.

MacBook-native Bluetooth features:

- BLE advertisement scanning with CoreBluetooth.
- BLE device inventory: local name, service UUIDs, manufacturer data, RSSI, connectability where exposed, and timestamped observations.
- BLE GATT service and characteristic enumeration for user-selected devices where pairing/connection is permitted.
- BLE privacy analysis: address rotation observations, beacon identification, manufacturer payload decoding, and proximity trend reporting.
- Bluetooth permission diagnostics and remediation.
- Bluetooth report export.

MacBook-native USB and HID features:

- USB device inventory through IOKit: vendor ID, product ID, class, subclass, serial where exposed, interface descriptors, and connection path.
- HID device inventory: keyboards, pointing devices, game controllers, and presentation remotes.
- Serial device inventory for USB UART adapters and GPS receivers.
- Read-only diagnostics for attached adapters that could extend KisMac3 capabilities.
- Safe local HID test harness for KisMac3's own UI automation tests.

MacBook-native GPS, location, and mapping features:

- CoreLocation support using the MacBook location stack.
- External USB/Bluetooth GPS receiver support when presented as serial, NMEA, or a supported location source.
- GPSd client mode over local or remote network.
- Map import, calibration, waypoints, network plotting, and timeline playback.
- Geofenced campaign scope using map boundaries.

MacBook-native reporting and project features:

- `.kismac` project bundles.
- Local encrypted project storage option.
- Redaction controls for MAC addresses, SSIDs, hostnames, and Bluetooth identifiers.
- Unified report covering Wi-Fi, LAN, BLE, USB/HID, GPS/map, captures, and limitations.
- Evidence timeline with source labels: CoreWLAN, CoreBluetooth, pcap, Kismet, USB, user import, or manual note.
- AppleScript/Shortcuts-friendly automation for passive workflows: start scan, stop scan, import capture, export report, open project.

MacBook-native features that are not guaranteed until the probe proves them:

- Raw 802.11 monitor capture on built-in Wi-Fi.
- Channel hopping on built-in Wi-Fi.
- Handshake capture from built-in Wi-Fi.
- AP/SoftAP creation.
- Frame injection.
- Deauthentication.
- AP impersonation / evil-twin behavior.
- Captive portal hosting over Wi-Fi.

Not feasible with MacBook hardware alone:

- Sub-GHz radio receive/transmit.
- 125 kHz RFID read/write/emulation.
- 13.56 MHz NFC card read/write/emulation.
- Infrared learning/transmit.
- iButton / 1-Wire key read/write/emulation.
- GPIO, UART, SPI, or I2C hardware operations without an adapter.
- Acting as a USB BadUSB device against another host without dedicated device-mode hardware.

These can be added only through external hardware modules and must be represented as `hardware-required` capabilities.

## Milestone 3: Capability Engine

Create a central capability engine so the UI and workflows only expose features that are possible on the current system.

Capabilities:

- scan
- passive capture
- pcap import
- pcap export
- channel switching
- monitor mode
- AP mode
- frame injection
- deauth
- handshake capture
- Kismet remote capture
- GPS
- map plotting
- LAN discovery
- Bonjour/mDNS inventory
- BLE scan
- BLE GATT enumeration
- USB inventory
- HID inventory
- serial device inventory
- Wi-Fi 6/6E/7 decode
- WPA3 decode
- OWE decode
- Enterprise decode
- Sub-GHz external module
- NFC external module
- RFID external module
- IR external module
- iButton external module

Every disabled feature must show the exact reason: permission missing, unsupported MacBook hardware, unsupported adapter, macOS blocked, protocol parser missing, or active lab scope missing.

## Milestone 4: Core Runtime Stabilization

- Stabilize app launch, preferences, scan start/stop, view switching, capture import/export, and session save/open.
- Replace stale Growl dependencies with macOS notifications.
- Replace deprecated critical alert/sheet APIs with `NSAlert`.
- Remove or quarantine stale driver-loading assumptions that can no longer work on modern macOS.
- Add clear diagnostics for Apple80211/CoreWLAN/pcap failures.

## Milestone 5: Modern Data Model

Introduce a model layer that separates UI, capture, driver, and report state.

Core entities:

- `Adapter`
- `Capability`
- `Network`
- `Client`
- `SecurityProfile`
- `ProtocolMetadata`
- `Capture`
- `Handshake`
- `Campaign`
- `MapProject`
- `AuditEvent`
- `Report`
- `BluetoothDevice`
- `USBDevice`
- `HIDDevice`
- `LANHost`
- `ServiceObservation`

This is required before the interface rewrite and protocol expansion.

## Milestone 6: Modern Protocol Support

Support current Wi-Fi and security metadata in both live scan data and imported pcaps.

Protocols and security:

- 802.11a/b/g/n/ac/ax/be.
- Wi-Fi 6, Wi-Fi 6E, and Wi-Fi 7.
- 2.4 GHz, 5 GHz, and 6 GHz channels.
- 320 MHz channels, EHT, MLO, and puncturing where visible in frames.
- WPA, WPA2, WPA3-Personal, WPA3-Enterprise, and transition modes.
- SAE, OWE / Enhanced Open, PMF / 802.11w.
- Enterprise EAP metadata.
- Hidden SSIDs.
- Malformed and vendor-specific tagged parameters.
- Detection-ready model for future Wi-Fi 8 / 802.11bn, without claiming support until APIs and hardware expose it.

Deliverable: protocol fixture corpus under `Tests/Fixtures/` with pcaps for legacy and modern networks.

## Milestone 7: Capture Backend Strategy

Support multiple capture sources, with MacBook hardware first.

Backends:

- CoreWLAN scan backend for MacBook built-in Wi-Fi.
- CoreBluetooth backend for BLE advertisement and GATT inventory.
- IOKit backend for USB/HID/serial inventory.
- Bonjour/DNS-SD backend for passive LAN service discovery.
- pcap backend where macOS permits.
- Imported pcap analysis as always-supported mode.
- Kismet drone/remote capture backend.
- Optional external adapter backend.
- Apple Wireless Diagnostics integration if it provides a stable, automatable capture path.

The app must continue to be useful even when raw monitor mode or injection is unavailable on built-in MacBook Wi-Fi.

## Milestone 8: Modern macOS Interface

Modernize the interface around current macOS Human Interface Guidelines while preserving power-user workflows.

Required UI:

- Sidebar-based main window.
- Toolbar with start/stop scan, import, export, report, and capability status.
- Recon dashboard for APs, clients, channels, security, and activity.
- Detail inspector for selected network/client.
- Tagged-parameter and security explanation views.
- Capability dashboard.
- Campaign workspace.
- Handshake workspace.
- Map/GPS workspace.
- LAN workspace.
- Bluetooth workspace.
- USB/HID workspace.
- Reports workspace.
- Settings window replacing legacy preferences where practical.
- Standard menu bar and keyboard shortcuts.
- Contextual menus for networks, clients, captures, and reports.
- Clear empty, error, permission, and unsupported states.

Use SwiftUI/AppKit incrementally only after core behavior is stable.

## Milestone 9: Privacy, Safety, And Authorized-Lab Guardrails

The app is a cyber tool, so active features must be explicit and scoped.

Requirements:

- Passive recon is separate from active lab features.
- Active features require an authorized campaign.
- Active campaign requires scope: SSIDs, BSSIDs, clients, adapters, channels, and time window.
- Deauth, injection, impersonation, captive portal, and AP simulation are disabled until scope is configured.
- Emergency stop is always visible during active campaigns.
- Audit log records active operations.
- Local-only storage by default.
- MAC redaction option.
- Bluetooth identifier redaction option.
- Hostname and local IP redaction option.
- Server export disabled unless explicitly enabled.
- Project encryption option for sensitive captures.

## Milestone 10: Pineapple-Style Authorized Lab Features

Implement Pineapple-like capabilities only as authorized lab workflows and only where hardware/macOS permit.

Feature groups:

- Recon dashboard with AP/client discovery, sorting, filtering, and search.
- Event log for probes, associations, disassociations, and handshakes.
- Client and SSID allow/deny filters.
- Passive and targeted handshake workspace.
- Lab AP profiles for owned test networks.
- Captive portal simulation for training environments.
- AP simulation / evil-twin-equivalent only with explicit scope and supported hardware.
- Deauth and frame injection only with explicit scope, compatible hardware, rate limits, and audit logging.
- Module system for local analyzers, report exporters, protocol decoders, and Kismet integrations.
- Campaign reports with evidence, timeline, and limitations.

MacBook built-in Wi-Fi must remain the first-class core recon target, but active radio features may require external hardware if modern macOS blocks them.

## Milestone 11: Physical Interface Extensions

Add Flipper-like physical-interface features only when an external module provides the required hardware.

External module families:

- Sub-GHz SDR/transceiver module.
- NFC reader/writer module.
- 125 kHz RFID reader/writer module.
- Infrared receiver/transmitter module.
- iButton / 1-Wire adapter.
- GPIO bridge or microcontroller module.
- USB device-mode HID module for authorized BadUSB-style lab simulations.

Rules:

- Read-only inventory and analysis first.
- Transmit, emulate, write, fuzz, or inject features require authorized lab scope.
- Every module declares capabilities, permissions, firmware version, and safety limits.
- Reports must label external-module evidence separately from MacBook-native evidence.

## Milestone 12: Project Files, Reports, And Exports

Create a modern `.kismac` project bundle containing:

- scan database
- captures
- maps
- reports
- campaign configuration
- hardware probe results
- audit log
- redaction settings

Reports should include:

- discovered networks
- observed clients
- LAN hosts and services
- BLE devices and services
- USB/HID/serial inventory
- protocol/security posture
- handshake status
- captures and evidence files
- map/GPS data
- MacBook hardware capability result
- unsupported or blocked features

## Milestone 13: Plugin System

Design plugins before adding arbitrary module execution.

Requirements:

- Signed local modules.
- Permission manifest.
- No arbitrary shell execution by default.
- Module API for UI panels, capture processors, protocol decoders, and report exporters.
- Clear uninstall/update path.
- Compatibility checks against app version and capability engine.

## Milestone 14: Signing, Notarization, CI, And Release

- Add Developer ID signing.
- Add hardened runtime settings.
- Add notarization script.
- Add release DMG packaging.
- Add CI build for project and submodules.
- Add static analysis.
- Add submodule patch validation.
- Add smoke test script.
- Document install, permissions, troubleshooting, and adapter compatibility.

## Milestone 15: Full Validation Matrix

Validation dimensions:

- Intel MacBook.
- Apple Silicon MacBook.
- Latest macOS.
- Previous supported macOS.
- Built-in Wi-Fi.
- Built-in Bluetooth.
- USB/HID/serial devices.
- External adapters.
- 2.4 GHz, 5 GHz, 6 GHz.
- Wi-Fi 4/5/6/6E/7.
- WPA2, WPA3, OWE, Enterprise, PMF.
- Passive recon.
- Imported pcaps.
- Kismet remote capture.
- LAN discovery.
- BLE inventory.
- USB/HID inventory.
- GPS/map workflows.
- Reports and exports.
- Signed release launch outside Xcode.

## Non-Negotiables

- MacBook built-in Wi-Fi support is mandatory for core recon.
- MacBook-native BLE, LAN, USB/HID, location, mapping, reporting, and project workflows must be implemented where macOS APIs permit them.
- Active Pineapple-style features must be scoped, logged, and hardware-gated.
- Do not claim full support for monitor mode, AP impersonation, or frame injection on MacBook hardware until the hardware probe proves it.
- Do not claim Flipper-style Sub-GHz, RFID, NFC, IR, iButton, GPIO, or BadUSB-device behavior on MacBook hardware alone; those require external modules.
- Do not call the app fully functional until original parity, modern protocols, UI modernization, and hardware validation all have documented results.
