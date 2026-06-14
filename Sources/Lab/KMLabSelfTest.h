/*
 File:        KMLabSelfTest.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: Headless self-test for S7.1, run under KISMAC_LAB_SELFTEST=1.
              Asserts the lab event log (from an imported management-frame
              fixture), the allow/deny filters, AP-profile scope-binding, the
              KMLabWorkflow gate matrix (fail-closed incl. out-of-scope + e-stop
              + no-adapter refusals, AP-sim/captive-portal unimplemented), and
              the campaign report lab section + limitations + redaction.

              PASSIVE / OFFLINE / LOCAL-ONLY: imports a bundled pcap, uses a
              throwaway audit dir + a MOCK adapter; never opens a radio.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMLabSelfTest : NSObject
/// Runs all S7.1 assertions, logs PASS/FAIL actual-vs-expected. YES iff ALL pass.
+ (BOOL)runSelfTestLogging;
@end

NS_ASSUME_NONNULL_END
