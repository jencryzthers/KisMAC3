/*
 File:        KMActiveGateSelfTest.h
 Program:     KisMac3
 Slice:       S4.2 - Gate inject/deauth/AP behind capability + scope

 Description: Headless self-test for the S4.2 active/offensive gate. Builds a
              MOCK adapter-presence provider + the REAL S4.1 scope provider into
              a real KMCapabilityEngine over MOCKED all-green hardware and
              asserts the full gate matrix:
                - no adapter, no scope   => inject/deauth/AP unsupportedAdapter
                - adapter, no scope       => activeLabScopeMissing
                - adapter, in-window scope => available
                - adapter + scope but target BSSID/client NOT in scope => the
                  op-level guard refuses (scopeContainsBSSID:/ClientMAC: NO) and
                  audits the refusal
                - emergency stop          => back to refused
              Runs ONLY when KISMAC_ACTIVEGATE_SELFTEST=1. PASSIVE: no radio,
              monitor mode, or channel switching; uses a throwaway audit dir.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMActiveGateSelfTest : NSObject
/// Runs the matrix and logs PASS/FAIL (actual vs expected). Returns YES on pass.
+ (BOOL)runSelfTestLogging;
@end

NS_ASSUME_NONNULL_END
