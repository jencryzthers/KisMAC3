#!/usr/bin/env python3
# S2.2 — Golden pcap/pcapng fixture generator for KisMac3 offline import.
#
# Produces a deterministic capture with a KNOWN set of 802.11 beacon frames
# (one per BSSID/SSID) plus a couple of data frames, wrapped in a minimal
# radiotap header (DLT_IEEE802_11_RADIO = 127). No scapy dependency: we emit
# the bytes by hand so the file is byte-for-byte reproducible and committable.
#
# This is OFFLINE test data only. It never touches a radio.
#
# Usage:
#   python3 make_pcap_fixture.py            # writes golden.pcap (+ golden.pcapng)
#
# Network count == number of distinct BSSIDs that appear (beacons).
# Expected counts are documented in README.md and asserted by the in-app
# KISMAC_PCAP_IMPORT_SELFTEST harness (KMPcapImportSelfTest).

import struct
import sys
import os

DLT_IEEE802_11_RADIO = 127

# --- Known fixture content (the "golden" values) ---------------------------
# (bssid bytes, ssid string, channel)
NETWORKS = [
    (b"\x00\x11\x22\x33\x44\x01", "KISMAC-FIX-ALPHA",   1),
    (b"\x00\x11\x22\x33\x44\x02", "KISMAC-FIX-BRAVO",   6),
    (b"\x00\x11\x22\x33\x44\x03", "KISMAC-FIX-CHARLIE", 11),
]
BROADCAST = b"\xff\xff\xff\xff\xff\xff"


def radiotap_header():
    # Minimal radiotap: version=0, pad=0, len=8, present=0 (no fields).
    return struct.pack("<BBHI", 0, 0, 8, 0)


def beacon_frame(bssid, ssid, channel):
    # 802.11 MGMT beacon, frame control bytes 0x80 0x00 (subtype beacon, type mgmt, v0).
    fc = b"\x80\x00"
    duration = b"\x00\x00"
    addr1 = BROADCAST          # DA = broadcast
    addr2 = bssid              # SA = BSSID
    addr3 = bssid              # BSSID
    seq = b"\x00\x00"
    hdr = fc + duration + addr1 + addr2 + addr3 + seq

    # Fixed beacon parameters.
    timestamp = b"\x00" * 8
    beacon_interval = struct.pack("<H", 100)
    capability = struct.pack("<H", 0x0001)  # ESS

    fixed = timestamp + beacon_interval + capability

    # Tagged parameters.
    ssid_b = ssid.encode("ascii")
    ie_ssid = bytes([0, len(ssid_b)]) + ssid_b                 # SSID element
    ie_rates = bytes([1, 4, 0x82, 0x84, 0x8b, 0x96])           # Supported rates
    ie_ds = bytes([3, 1, channel])                             # DS param (channel)

    return hdr + fixed + ie_ssid + ie_rates + ie_ds


def data_frame(bssid, client):
    # 802.11 DATA frame, ToDS=1 (client -> AP). FC bytes: 0x08 0x01.
    fc = b"\x08\x01"
    duration = b"\x00\x00"
    addr1 = bssid              # BSSID (RA, ToDS)
    addr2 = client             # SA (client)
    addr3 = BROADCAST          # DA
    seq = b"\x00\x00"
    hdr = fc + duration + addr1 + addr2 + addr3 + seq
    body = b"\x00" * 8         # minimal LLC-ish padding
    return hdr + body


def frames():
    out = []
    for bssid, ssid, ch in NETWORKS:
        out.append(beacon_frame(bssid, ssid, ch))
    # One client on the first network (a single data frame, ToDS).
    out.append(data_frame(NETWORKS[0][0], b"\xaa\xbb\xcc\xdd\xee\x01"))
    return out


def write_pcap(path):
    with open(path, "wb") as f:
        # pcap global header: magic, vmaj, vmin, thiszone, sigfigs, snaplen, linktype
        f.write(struct.pack("<IHHiIII",
                            0xa1b2c3d4, 2, 4, 0, 0, 65535, DLT_IEEE802_11_RADIO))
        ts = 1700000000
        for i, body in enumerate(frames()):
            pkt = radiotap_header() + body
            # record header: ts_sec, ts_usec, incl_len, orig_len
            f.write(struct.pack("<IIII", ts + i, 0, len(pkt), len(pkt)))
            f.write(pkt)


def write_pcapng(path):
    # Minimal pcapng: SHB + IDB + one EPB per packet.
    def block(btype, body):
        total = 12 + len(body)
        pad = (-len(body)) % 4
        body = body + b"\x00" * pad
        total = 12 + len(body)
        return struct.pack("<II", btype, total) + body + struct.pack("<I", total)

    with open(path, "wb") as f:
        # Section Header Block (0x0A0D0D0A)
        shb_body = struct.pack("<IHHq", 0x1A2B3C4D, 1, 0, -1)
        f.write(block(0x0A0D0D0A, shb_body))
        # Interface Description Block (0x00000001): linktype, reserved, snaplen
        idb_body = struct.pack("<HHI", DLT_IEEE802_11_RADIO, 0, 65535)
        f.write(block(0x00000001, idb_body))
        # Enhanced Packet Blocks (0x00000006)
        for body in frames():
            pkt = radiotap_header() + body
            epb_head = struct.pack("<IIIII",
                                  0,          # interface id
                                  0, 0,       # ts high/low
                                  len(pkt),   # captured len
                                  len(pkt))   # original len
            f.write(block(0x00000006, epb_head + pkt))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    pcap_path = os.path.join(here, "golden.pcap")
    pcapng_path = os.path.join(here, "golden.pcapng")
    write_pcap(pcap_path)
    write_pcapng(pcapng_path)
    print("Wrote %s (%d bytes)" % (pcap_path, os.path.getsize(pcap_path)))
    print("Wrote %s (%d bytes)" % (pcapng_path, os.path.getsize(pcapng_path)))
    print("Networks (distinct BSSIDs): %d" % len(NETWORKS))
    for bssid, ssid, ch in NETWORKS:
        print("  %s  ch%-3d  %s" % (
            ":".join("%02X" % b for b in bssid), ch, ssid))


if __name__ == "__main__":
    main()
