/*
 File:        KMReportSelfTest.h
 Program:     KisMac3
 Slice:       S6.1 - Secure .kismac load + unified report generator

 Description: Headless acceptance self-test for S6.1, gated by the env var
              KISMAC_REPORT_SELFTEST=1 (mirrors the prior slices' self-tests).

   Part A (secure .kismac load):
     - round-trip: save a small container to a temp `.kismac` and reload it via
       the secure path, asserting fidelity; AND
     - feed a deliberately MALFORMED / HOSTILE blob to the secure unarchiver and
       assert it fails gracefully (clear error / no crash / no arbitrary-class
       decode).
   Part B (unified report):
     - import Tests/Fixtures/golden.pcap into a container, generate a report,
       assert it contains the expected sections + the 3 known networks, the
       capability / blocked-features section is present, and that with redaction
       ON no raw BSSID/SSID appears (and with it OFF they do).

   Logs PASS/FAIL actual-vs-expected via DBNSLog. OFFLINE / PASSIVE ONLY.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMReportSelfTest : NSObject
/// Runs all S6.1 assertions and logs PASS/FAIL. Returns YES iff ALL pass.
+ (BOOL)runSelfTestLogging;
@end

NS_ASSUME_NONNULL_END
