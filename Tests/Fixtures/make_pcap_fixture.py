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


# ===========================================================================
# S2.1 — Modern protocol metadata corpus.
#
# Each fixture is a SINGLE beacon whose tagged parameters encode a known modern
# security posture and/or PHY generation. The in-app KISMAC_PROTO_SELFTEST
# harness imports each file and asserts the decoded security/PHY display string
# matches the value documented here (and in README.md).
#
# These bytes are hand-rolled (no scapy) so the files are byte-reproducible.
# OFFLINE TEST DATA ONLY — never produced by or fed to a radio.
# ===========================================================================

# --- Information-element builders (all bounds-safe; ids per IEEE 802.11) -----

def ie(eid, body):
    return bytes([eid & 0xFF, len(body) & 0xFF]) + body

def ie_ssid(ssid):
    b = ssid.encode("ascii")
    return ie(0, b)

def ie_rates():
    return ie(1, bytes([0x82, 0x84, 0x8b, 0x96]))

def ie_ds(channel):
    return ie(3, bytes([channel & 0xFF]))

# RSN IE (id 48). akms is a list of 00-0F-AC suite type bytes; pmf in
# {None,'capable','required'}. group/pairwise default to CCMP (type 4).
OUI_IEEE = b"\x00\x0f\xac"

def rsn_ie(akms, pmf=None, pairwise=(4,)):
    body = struct.pack("<H", 1)                       # version
    body += OUI_IEEE + bytes([4])                     # group cipher = CCMP
    body += struct.pack("<H", len(pairwise))          # pairwise count
    for pw in pairwise:
        body += OUI_IEEE + bytes([pw])
    body += struct.pack("<H", len(akms))              # AKM count
    for a in akms:
        body += OUI_IEEE + bytes([a])
    cap = 0x0000
    if pmf == "capable":
        cap |= 0x0080                                 # MFPC
    elif pmf == "required":
        cap |= 0x0080 | 0x0040                        # MFPC + MFPR
    body += struct.pack("<H", cap)                    # RSN capabilities
    return ie(48, body)

# Vendor WPA1 IE (id 221, OUI 00-50-F2, type 1).
def wpa1_ie():
    body = b"\x00\x50\xf2\x01"
    body += struct.pack("<H", 1)                      # version
    body += b"\x00\x50\xf2\x02"                       # group = TKIP
    body += struct.pack("<H", 1) + b"\x00\x50\xf2\x02"  # pairwise TKIP
    body += struct.pack("<H", 1) + b"\x00\x50\xf2\x02"  # akm = WPA-PSK
    return ie(221, body)

# PHY capability elements.
def ht_caps(forty=True):
    htcap = 0x0002 if forty else 0x0000
    body = struct.pack("<H", htcap) + b"\x00" * 24    # 26-byte HT caps
    return ie(45, body)

def vht_caps(width160=True):
    info = (1 << 2) if width160 else 0                # Supported Channel Width Set
    body = struct.pack("<I", info) + b"\x00" * 8      # 12-byte VHT caps
    return ie(191, body)

def ext_ie(ext_id, body=b""):
    return ie(255, bytes([ext_id & 0xFF]) + body)

def he_caps():
    return ext_ie(35, b"\x00" * 21)                   # HE capabilities

def he_6ghz_caps():
    return ext_ie(59, b"\x00\x00")                    # 6 GHz band capabilities

def eht_caps():
    return ext_ie(108, b"\x00" * 9)                   # EHT capabilities


def proto_beacon(bssid, ssid, channel, ies, privacy=False):
    fc = b"\x80\x00"
    duration = b"\x00\x00"
    hdr = fc + duration + BROADCAST + bssid + bssid + b"\x00\x00"
    timestamp = b"\x00" * 8
    beacon_interval = struct.pack("<H", 100)
    cap = 0x0001                                       # ESS
    if privacy:
        cap |= 0x0010                                  # Privacy bit
    fixed = timestamp + beacon_interval + struct.pack("<H", cap)
    body = b"".join(ies)
    return hdr + fixed + body


# (filename, ssid, channel, privacy, [ies after fixed],
#  expected_security, expected_phy)  -- expected_* documented in README.
PROTO_FIXTURES = [
    ("proto_wep", "PROTO-WEP", 1, True,
     [ie_ssid("PROTO-WEP"), ie_rates(), ie_ds(1)],
     "WEP", "802.11a/b/g"),

    ("proto_wpa2", "PROTO-WPA2", 6, True,
     [ie_ssid("PROTO-WPA2"), ie_rates(), ie_ds(6), rsn_ie([2])],
     "WPA2-Personal", "802.11a/b/g"),

    ("proto_wpa3_sae", "PROTO-WPA3", 36, True,
     [ie_ssid("PROTO-WPA3"), ie_rates(), ie_ds(36), rsn_ie([8], pmf="required")],
     "WPA3-SAE (PMF required)", "802.11a/b/g"),

    ("proto_wpa3_transition", "PROTO-WPA3T", 11, True,
     [ie_ssid("PROTO-WPA3T"), ie_rates(), ie_ds(11),
      rsn_ie([2, 8], pmf="capable")],
     "WPA2/WPA3-Transition (PMF capable)", "802.11a/b/g"),

    ("proto_owe", "PROTO-OWE", 1, True,
     [ie_ssid("PROTO-OWE"), ie_rates(), ie_ds(1),
      rsn_ie([18], pmf="required")],
     "OWE (Enhanced Open) (PMF required)", "802.11a/b/g"),

    ("proto_enterprise", "PROTO-ENT", 6, True,
     [ie_ssid("PROTO-ENT"), ie_rates(), ie_ds(6), rsn_ie([1])],
     "WPA2-Enterprise", "802.11a/b/g"),

    ("proto_pmf_required", "PROTO-PMF", 36, True,
     [ie_ssid("PROTO-PMF"), ie_rates(), ie_ds(36),
      rsn_ie([2], pmf="required")],
     "WPA2-Personal (PMF required)", "802.11a/b/g"),

    ("proto_hidden", "", 1, True,
     [ie_ssid(""), ie_rates(), ie_ds(1), rsn_ie([2])],
     "WPA2-Personal", "802.11a/b/g"),

    # Wi-Fi 6: HE caps, WPA3, 80 MHz (from a co-present VHT 80).
    ("proto_wifi6", "PROTO-WIFI6", 36, True,
     [ie_ssid("PROTO-WIFI6"), ie_rates(), ie_ds(36),
      ht_caps(True), vht_caps(False), he_caps(),
      rsn_ie([8], pmf="required")],
     "WPA3-SAE (PMF required)", "Wi-Fi 6 (802.11ax), 80 MHz"),

    # Wi-Fi 6E: HE caps + 6 GHz band caps.
    ("proto_wifi6e", "PROTO-WIFI6E", 37, True,
     [ie_ssid("PROTO-WIFI6E"), ie_rates(),
      he_caps(), he_6ghz_caps(),
      rsn_ie([8], pmf="required")],
     "WPA3-SAE (PMF required)", "Wi-Fi 6E (802.11ax, 6 GHz)"),

    # Wi-Fi 7: EHT caps (320 MHz), WPA3.
    ("proto_wifi7", "PROTO-WIFI7", 37, True,
     [ie_ssid("PROTO-WIFI7"), ie_rates(),
      he_caps(), he_6ghz_caps(), eht_caps(),
      rsn_ie([8], pmf="required")],
     "WPA3-SAE (PMF required)", "Wi-Fi 7 (802.11be), 320 MHz"),

    # Malformed: an RSN IE whose declared length runs past the buffer, plus a
    # truncated extension element. Must NOT crash; decoded values are best-effort.
    ("proto_malformed", "PROTO-BAD", 1, True,
     [ie_ssid("PROTO-BAD"), ie_rates(),
      bytes([48, 40]) + b"\x01\x00\x00\x0f\xac\x04",   # len=40 but only 6 bytes
      bytes([255])],                                    # truncated ext (no sub-id)
     "*no-crash*", "*no-crash*"),
]


def write_single_beacon_pcap(path, fix, index):
    _name, ssid, ch, privacy, ies, _sec, _phy = fix
    # Deterministic per-fixture BSSID (index-derived, NOT hash() which varies
    # across runs via PYTHONHASHSEED -> keeps the files byte-reproducible).
    bssid = bytes([0x02, 0x00, 0x00, 0x00, 0x00, (index + 1) & 0xFF])
    beacon = proto_beacon(bssid, ssid, ch, ies, privacy)
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII",
                            0xa1b2c3d4, 2, 4, 0, 0, 65535, DLT_IEEE802_11_RADIO))
        pkt = radiotap_header() + beacon
        f.write(struct.pack("<IIII", 1700000000, 0, len(pkt), len(pkt)))
        f.write(pkt)
    return bssid


# ===========================================================================
# S7.1 — Authorized-lab MANAGEMENT-FRAME fixture (lab_mgmt.pcap).
#
# A small, deterministic capture exercising the KMLabEventLog: a probe-request,
# an association-request, a deauthentication, and ONE EAPOL handshake message.
# The in-app KISMAC_LAB_SELFTEST harness imports it and asserts the expected
# event types + counts. OFFLINE TEST DATA ONLY — never produced by a radio.
#
# Lab fixture identities (also pinned in README.md / KMLabSelfTest):
LAB_AP_BSSID   = b"\x00\x11\x22\x33\x44\x55"   # 00:11:22:33:44:55
LAB_CLIENT_MAC = b"\xAA\xBB\xCC\xDD\xEE\xFF"   # AA:BB:CC:DD:EE:FF
LAB_SSID       = "KISMAC-LAB-NET"


def mgmt_frame(fc0, addr1, addr2, addr3, body=b""):
    # 802.11 mgmt header (3-addr). fc0 = first frame-control byte (subtype|type).
    fc = bytes([fc0, 0x00])
    duration = b"\x00\x00"
    seq = b"\x00\x00"
    return fc + duration + addr1 + addr2 + addr3 + seq + body


def probe_request(client, ssid):
    # subtype 0x4 (probe req), type mgmt -> fc0 = 0x40. DA/BSSID = broadcast.
    body = ie_ssid(ssid) + ie_rates()
    return mgmt_frame(0x40, BROADCAST, client, BROADCAST, body)


def assoc_request(client, bssid, ssid):
    # subtype 0x0 (assoc req), type mgmt -> fc0 = 0x00. To the AP.
    cap = struct.pack("<H", 0x0011)        # ESS + Privacy
    listen = struct.pack("<H", 10)
    body = cap + listen + ie_ssid(ssid) + ie_rates()
    return mgmt_frame(0x00, bssid, client, bssid, body)


def deauth_frame(client, bssid):
    # subtype 0xC (deauth), type mgmt -> fc0 = 0xC0. AP -> client.
    reason = struct.pack("<H", 7)          # class-3 frame from nonassociated STA
    return mgmt_frame(0xC0, client, bssid, bssid, reason)


def eapol_handshake(client, bssid):
    # A DATA frame (ToDS=1, client->AP) carrying an EAPOL-Key message, so the
    # parser flags it isWPAKeyPacket. Body = LLC/SNAP(8) + 802.1X key frame.
    # Layout matches WavePacket: payload[0..7]=LLC, [8]=ver,[9]=type=3(key),
    # [12]=descriptor type 254(WPA), [13..14]=key info (pairwise, not groupwise).
    fc = b"\x08\x01"                       # data, ToDS
    duration = b"\x00\x00"
    hdr = fc + duration + bssid + client + bssid + b"\x00\x00"   # addr1=BSSID,addr2=SA,addr3=DA
    llc = b"\xAA\xAA\x03\x00\x00\x00\x88\x8E"                    # SNAP + EAPOL ethertype
    # 802.1X header: version=2, type=3 (EAPOL-Key), length.
    x_ver = b"\x02"
    x_type = b"\x03"
    # Key descriptor: type(1)=254(WPA), key info(2), then nonces/IV/etc padded so
    # the whole 802.11 payload is >= 99 bytes (parser requirement).
    desc_type = b"\xFE"                     # 254 = WPA key descriptor
    key_info = b"\x00\x08"                  # keytype=pairwise bit set (not groupwise)
    key_len = b"\x00\x10"
    replay = b"\x00" * 8
    nonce = b"\x00" * 32
    key_iv = b"\x00" * 16
    rsc = b"\x00" * 8
    key_id = b"\x00" * 8
    mic = b"\x11" * 16
    key_data_len = b"\x00\x00"
    keyframe = desc_type + key_info + key_len + replay + nonce + key_iv + rsc + key_id + mic + key_data_len
    x_len = struct.pack(">H", len(keyframe))
    body = llc + x_ver + x_type + x_len + keyframe
    return hdr + body


def lab_frames():
    return [
        probe_request(LAB_CLIENT_MAC, LAB_SSID),
        assoc_request(LAB_CLIENT_MAC, LAB_AP_BSSID, LAB_SSID),
        deauth_frame(LAB_CLIENT_MAC, LAB_AP_BSSID),
        eapol_handshake(LAB_CLIENT_MAC, LAB_AP_BSSID),
    ]


def write_lab_mgmt_pcap(path):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII",
                            0xa1b2c3d4, 2, 4, 0, 0, 65535, DLT_IEEE802_11_RADIO))
        ts = 1700001000
        for i, body in enumerate(lab_frames()):
            pkt = radiotap_header() + body
            f.write(struct.pack("<IIII", ts + i, 0, len(pkt), len(pkt)))
            f.write(pkt)


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

    print("\nS2.1 protocol corpus:")
    for idx, fix in enumerate(PROTO_FIXTURES):
        name = fix[0]
        out = os.path.join(here, name + ".pcap")
        write_single_beacon_pcap(out, fix, idx)
        print("  %-26s sec=%-38s phy=%s" % (name + ".pcap", fix[5], fix[6]))

    lab_path = os.path.join(here, "lab_mgmt.pcap")
    write_lab_mgmt_pcap(lab_path)
    print("\nS7.1 lab management-frame fixture:")
    print("  %s (%d bytes)" % (lab_path, os.path.getsize(lab_path)))
    print("  probe-request, association-request, deauthentication, 1 EAPOL handshake")
    print("  AP=%s  client=%s  ssid=%s" % (
        ":".join("%02X" % b for b in LAB_AP_BSSID),
        ":".join("%02X" % b for b in LAB_CLIENT_MAC), LAB_SSID))


if __name__ == "__main__":
    main()
