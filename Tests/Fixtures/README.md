# Tests/Fixtures — golden capture fixtures (S2.2)

Deterministic, committed capture files used to verify KisMac3's **offline**
pcap/pcapng import path (`-[WaveScanner readPCAPDump:]` → `pcap_open_offline`).
These are test data only — they are never produced by, and never drive, a radio.

## Files

| File            | Format | Datalink                       | Bytes |
|-----------------|--------|--------------------------------|-------|
| `golden.pcap`   | pcap   | `DLT_IEEE802_11_RADIO` (radiotap) | 343 |
| `golden.pcapng` | pcapng | `DLT_IEEE802_11_RADIO` (radiotap) | 436 |

Both encode the **same logical content** so the pcapng variant exercises the
pcapng read path of the linked `libpcap` (`pcap_open_offline` reads pcapng
transparently — confirmed, see below).

## Content (the "golden" values)

3 beacon frames (one per BSSID/SSID) + 1 data frame (ToDS, one station):

| BSSID                 | SSID                | Channel |
|-----------------------|---------------------|---------|
| `00:11:22:33:44:01`   | `KISMAC-FIX-ALPHA`   | 1       |
| `00:11:22:33:44:02`   | `KISMAC-FIX-BRAVO`   | 6       |
| `00:11:22:33:44:03`   | `KISMAC-FIX-CHARLIE` | 11      |

Plus one data frame: station `AA:BB:CC:DD:EE:01` → BSSID `00:11:22:33:44:01`.

### Expected counts after import (asserted by the self-test)

- **Networks: 3** — one per distinct BSSID (beacons).
- **Clients: 7** — the `WavePacket`→`WaveNet`→`WaveContainer` pipeline registers,
  per network, the BSSID (frame sender) and the broadcast DA (frame receiver)
  as clients; the data frame adds one station to ALPHA:
  - ALPHA   = `{BSSID_01, FF:FF:FF:FF:FF:FF, AA:BB:CC:DD:EE:01}` = 3
  - BRAVO   = `{BSSID_02, FF:FF:FF:FF:FF:FF}` = 2
  - CHARLIE = `{BSSID_03, FF:FF:FF:FF:FF:FF}` = 2
  - **total = 7**

These counts are pinned in `Sources/Capabilities/KMPcapImportSelfTest.m`
(`kExpectedNetworkCount` / `kExpectedClientCount`).

## Regenerating

The fixtures are byte-for-byte reproducible (no scapy dependency):

```sh
python3 Tests/Fixtures/make_pcap_fixture.py
```

This rewrites `golden.pcap` and `golden.pcapng`. If you change the content,
re-run the self-test and update the pinned expected counts.

`golden.pcap` is bundled into the app (Resources) so the self-test can find it
without an external path.

## Running the offline-import self-test (headless, no GUI clicking, no radio)

```sh
# default: imports the bundled golden.pcap
KISMAC_PCAP_IMPORT_SELFTEST=1 .../KisMac2.app/Contents/MacOS/KisMac2

# or point at a specific capture (e.g. the pcapng variant)
KISMAC_PCAP_IMPORT_SELFTEST="$PWD/Tests/Fixtures/golden.pcapng" \
  .../KisMac2.app/Contents/MacOS/KisMac2
```

It imports the fixture into a throwaway `WaveContainer` via the offline pipeline
and logs a single PASS/FAIL line with actual-vs-expected counts. Verified output:

```
[PCAP-IMPORT-SELFTEST] PASS fixture=golden.pcap   networks=3 (expected 3) clients=7 (expected 7) [offline import, no live capture]
[PCAP-IMPORT-SELFTEST] PASS fixture=golden.pcapng networks=3 (expected 3) clients=7 (expected 7) [offline import, no live capture]
```

## pcapng support

**Works.** The linked `libpcap`'s `pcap_open_offline` reads `golden.pcapng`
transparently — no code change was needed and the self-test PASSes on the
pcapng variant with identical counts. (`tcpdump -r golden.pcapng` also reads it,
confirming the file is a valid pcapng independent of KisMac.)

## S2.1 — Modern protocol metadata corpus

In addition to the `golden.*` import fixtures above, the generator emits a
single-beacon fixture per modern protocol posture. Each beacon's tagged
parameters (RSN IE id 48, vendor WPA IE id 221, HT id 45, VHT id 191, HE/EHT
element-extensions, 6 GHz band caps) encode a **known** security and PHY value.
The `KMProtocolMetadata` decoder is a fully bounds-checked TLV walker; these
fixtures pin its output.

| File                          | Decoded security                        | Decoded PHY                       |
|-------------------------------|-----------------------------------------|-----------------------------------|
| `proto_wep.pcap`              | `WEP`                                    | `802.11a/b/g`                     |
| `proto_wpa2.pcap`             | `WPA2-Personal`                          | `802.11a/b/g`                     |
| `proto_wpa3_sae.pcap`         | `WPA3-SAE (PMF required)`                | `802.11a/b/g`                     |
| `proto_wpa3_transition.pcap`  | `WPA2/WPA3-Transition (PMF capable)`     | `802.11a/b/g`                     |
| `proto_owe.pcap`              | `OWE (Enhanced Open) (PMF required)`     | `802.11a/b/g`                     |
| `proto_enterprise.pcap`       | `WPA2-Enterprise`                        | `802.11a/b/g`                     |
| `proto_pmf_required.pcap`     | `WPA2-Personal (PMF required)`           | `802.11a/b/g`                     |
| `proto_hidden.pcap`           | `WPA2-Personal` (hidden SSID flagged)    | `802.11a/b/g`                     |
| `proto_wifi6.pcap`            | `WPA3-SAE (PMF required)`                | `Wi-Fi 6 (802.11ax), 80 MHz`      |
| `proto_wifi6e.pcap`           | `WPA3-SAE (PMF required)`                | `Wi-Fi 6E (802.11ax, 6 GHz)`      |
| `proto_wifi7.pcap`            | `WPA3-SAE (PMF required)`                | `Wi-Fi 7 (802.11be), 320 MHz`     |
| `proto_malformed.pcap`        | *(no-crash; best-effort `WEP`)*          | `802.11a/b/g`                     |

`proto_malformed.pcap` carries an RSN IE whose declared length overruns the
buffer plus a truncated element-extension (id 255 with no sub-id). The decoder
must **not** crash; it falls back to the Privacy bit.

These values are asserted by the in-app **`KISMAC_PROTO_SELFTEST`** harness
(`Sources/Capabilities/KMProtocolSelfTest.m`) and were independently verified by
compiling `KMProtocolMetadata.m` standalone against these bytes.

### Known limitations (no fixture / not faithfully synthesizable)

- **HE/EHT channel width:** width for Wi-Fi 6/6E is carried in the HE PHY
  Capabilities bitmap / HE Operation IE, which the decoder does **not** parse.
  Width is asserted only from HT (40), VHT (80/160) and EHT (320). So
  `proto_wifi6e` deliberately shows no width, and `proto_wifi6` derives 80 MHz
  from a co-present VHT element. Documented decode limitation, not a faked claim.
- **MLO / puncturing (Wi-Fi 7):** detected only to the extent of EHT presence
  (→ Wi-Fi 7, 320 MHz). Per-link MLO and puncturing bitmaps are not decoded.
- **Live capture of these frames is NOT claimed.** This is offline/imported-pcap
  decode only; built-in monitor capture remains `unknownRequiresActiveProbe`.

### Running the protocol self-test (headless, no GUI, no radio)

```sh
# imports every bundled proto_*.pcap and asserts security + PHY strings
KISMAC_PROTO_SELFTEST=1 .../KisMac2.app/Contents/MacOS/KisMac2
```

It logs one PASS/FAIL line per fixture (actual vs expected) plus a summary, and
explicitly proves the malformed fixture does not crash.

## Safety

This whole path is **offline / passive**. Importing a file routes only through
`pcap_open_offline`; it never starts a live capture, opens a BPF device, enters
monitor mode, switches channels, or injects/transmits.
