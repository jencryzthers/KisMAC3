/*
 File:        KMSafetySelfTest.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: Env-gated, headless self-test for the S4.1 safety machinery.
              Mirrors the prior slices' self-tests (KMCapabilityEngine /
              KMProtocolSelfTest / KMCryptoSelfTest): logs one PASS/FAIL line
              per check (actual vs expected) plus a summary. Runs only when
              KISMAC_SAFETY_SELFTEST=1 is set in the environment.

              Asserts, against the REAL KMActiveCampaignScopeProvider wired into
              a real KMCapabilityEngine (built from MOCKED all-green hardware so
              the test is hardware-independent):
                1. No campaign      => hasActiveScope NO  => frameInjection /
                                       deauth / apMode unavailable w/
                                       activeLabScopeMissing (FAIL CLOSED).
                2. Authorized in-window campaign => hasActiveScope YES => those
                                       features flip OFF activeLabScopeMissing
                                       (to unsupportedMacBookHardware on
                                       built-in, per S1.3 -- expected).
                3. Emergency stop   => scope immediately inactive => fail closed
                                       again; an emergency_stop audit entry was
                                       recorded.
                4. Expired window   => campaign NOT active.
                5. Audit log        => entries appended + readable.
                6. Redaction        => MAC/SSID/hostname transformed when ON,
                                       untouched when OFF.

              Uses a temporary audit directory so it never pollutes the real
              log. PASSIVE: touches no radio / monitor / channel.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMSafetySelfTest : NSObject

/// Runs all S4.1 safety checks, logging PASS/FAIL (actual vs expected) plus a
/// summary. Returns YES iff every check passes.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
