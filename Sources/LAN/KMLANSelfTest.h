/*
 File:        KMLANSelfTest.h
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 Description: Headless self-test for the passive Bonjour/DNS-SD discovery
              surface. Runs under KISMAC_LAN_SELFTEST=1.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMLANSelfTest : NSObject

/// Runs the S3.3 self-test, logging PASS/FAIL via DBNSLog. Returns YES on PASS.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
