#!/usr/bin/env python3
"""
Mock legacy Kismet server for KisMac3 S2.4 (Kismet remote/drone backend
modernization) self-test.

Speaks the ~2006-era Kismet *NETWORK: text line protocol that
Sources/WaveDrivers/WaveDriverKismet.m expects. It is NOT a real Kismet and does
NOT implement the modern Kismet 3.x REST/websocket/JSON protocol -- it exists
purely to prove the modernized Network.framework transport connects, reads, and
parses, against a known fixture, with no real hardware.

Wire format the client parses (see WaveDriverKismet.m -networksInRange):
  - lines are split on '\n'
  - each line is split on '\x01' -> [header, ssid, ...]
  - the header is split on ' ' -> tokens
        tokens[0] == "*NETWORK:"
        tokens[1] == BSSID  (aa:bb:cc:dd:ee:ff)
        tokens[2] == type   (0=managed,1=adhoc,2=probe)
        tokens[3] == wep    (0=open,2=WEP,>2=WPA)
        tokens[4] == signal
        tokens[5] == maxrate
        tokens[6] == channel
  - the SSID is the token AFTER the first '\x01'
So a full line is:
  "*NETWORK: <bssid> <type> <wep> <signal> <maxrate> <channel>\x01<ssid>\x01\n"

The client first sends an "!0 ENABLE NETWORK ...\n" subscribe command; we wait
for any bytes (or a short delay) and then stream the fixture networks.

Usage: python3 mock_kismet_server.py [host] [port]   (default 127.0.0.1 27410)
"""

import socket
import sys
import time

# Fixture networks. BSSIDs/channels are asserted by KMKismetSelfTest.m.
NETWORKS = [
    # bssid,             type, wep, signal, maxrate, channel, ssid
    ("00:11:22:33:44:55", 0,   0,   -42,    54,      6,       "TestNetOne"),
    ("AA:BB:CC:DD:EE:FF", 0,   2,   -55,    54,      11,      "SecureNet"),
]


def build_line(bssid, ntype, wep, signal, maxrate, channel, ssid):
    header = "*NETWORK: %s %d %d %d %d %d" % (bssid, ntype, wep, signal, maxrate, channel)
    return ("%s\x01%s\x01\n" % (header, ssid)).encode("utf-8")


def serve(host, port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(1)
    srv.settimeout(20.0)
    sys.stderr.write("mock_kismet_server listening on %s:%d\n" % (host, port))
    sys.stderr.flush()

    try:
        conn, addr = srv.accept()
    except socket.timeout:
        sys.stderr.write("mock_kismet_server: no client connected, exiting\n")
        return 1

    conn.settimeout(5.0)
    # Wait for the client's subscribe command (best-effort; don't fail if none).
    try:
        conn.recv(256)
    except socket.timeout:
        pass

    payload = b"".join(build_line(*n) for n in NETWORKS)
    # Send a few times so the polling client is sure to see them.
    for _ in range(10):
        try:
            conn.sendall(payload)
        except (BrokenPipeError, OSError):
            break
        time.sleep(0.2)

    try:
        conn.close()
    except OSError:
        pass
    srv.close()
    return 0


if __name__ == "__main__":
    h = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    p = int(sys.argv[2]) if len(sys.argv) > 2 else 27410
    sys.exit(serve(h, p))
