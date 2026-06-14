/*
 File:          KMCryptoSelfTest.h
 Program:       KisMac3
 Slice:         S2.3 - Crypto/cracking modernization

 Description:   Env-gated, headless self-test for the S2.3 CommonCrypto
                migration of the crack path. Mirrors the S2.1/S2.2 self-test
                pattern (KMProtocolSelfTest / KMPcapImportSelfTest): runs known
                test vectors and logs one PASS/FAIL line per check (actual vs
                expected) plus a summary.

                Validates, against standard vectors:
                  - CC_MD4  / CC_MD5 / CC_SHA1 raw digests
                  - the WPA PMK (PBKDF2-HMAC-SHA1, 4096, SSID salt) via both
                    WPA.m's wpaTestPasswordHash() vectors and the migrated
                    CommonCrypto fastWP_passwordHash() path (IEEE/password ->
                    known PMK), asserting the two paths agree bit-for-bit
                  - a LEAP NtPasswordHash + DES round-trip (gethashlast2 +
                    testChallenge) exercising the migrated MD4 + the kept DES.

                CPU-only / PASSIVE: no radio, no monitor mode, no I/O beyond
                logging. Runs only when KISMAC_CRYPTO_SELFTEST=1 is set in the
                environment.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMCryptoSelfTest : NSObject

/// Runs all crypto vectors, logging PASS/FAIL (actual vs expected) per check
/// plus a summary. Returns YES iff every check passes.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
