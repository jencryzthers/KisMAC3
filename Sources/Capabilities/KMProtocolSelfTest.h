/*
 File:          KMProtocolSelfTest.h
 Program:       KisMac3
 Slice:         S2.1 - Modern protocol metadata model + fixtures

 Description:   Env-gated, headless self-test for the S2.1 protocol decoder.
                Mirrors the S2.2 KMPcapImportSelfTest pattern: imports each
                bundled proto_*.pcap fixture through the OFFLINE pipeline
                (-[WaveScanner readPCAPDump:] -> pcap_open_offline) and asserts
                the decoded security + PHY display strings match the fixture's
                KNOWN values.

                OFFLINE / PASSIVE ONLY: never starts a scan, opens a BPF device,
                enters monitor mode, switches channels, or transmits.

                Runs only when KISMAC_PROTO_SELFTEST is set in the environment.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMProtocolSelfTest : NSObject

/// Imports each bundled proto_*.pcap, asserts decoded security/PHY strings, and
/// logs one PASS/FAIL line per fixture plus a summary. Returns YES iff all pass.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
