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

## Safety

This whole path is **offline / passive**. Importing a file routes only through
`pcap_open_offline`; it never starts a live capture, opens a BPF device, enters
monitor mode, switches channels, or injects/transmits.
