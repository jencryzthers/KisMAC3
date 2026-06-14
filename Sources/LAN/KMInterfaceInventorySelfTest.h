/*
 File:        KMInterfaceInventorySelfTest.h
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 Description: Headless self-test for the local interface inventory. Enumerates
              the interfaces on THIS machine (getifaddrs needs no permission),
              logs a REDACTED summary, and asserts the acceptance criteria
              (enumeration doesn't crash, lo0 present + loopback-classified, at
              least one en* present, primary status consistent). Gated by
              KISMAC_IFACE_SELFTEST=1.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMInterfaceInventorySelfTest : NSObject

/// Runs the S3.4 self-test, DBNSLog'ing PASS/FAIL. Returns YES on PASS.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
