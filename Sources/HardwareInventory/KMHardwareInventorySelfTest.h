/*
 File:        KMHardwareInventorySelfTest.h
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 Description: Headless self-test for the USB/HID/serial IOKit inventory. Unlike
              BLE, IOKit registry enumeration needs no permission, so this REALLY
              enumerates THIS machine: it runs all three enumerations, logs the
              device counts + a redacted sample, and asserts that (a) enumeration
              returns without crashing, (b) HID count > 0 (a Mac always has a
              built-in keyboard/trackpad HID), and (c) the capability engine now
              reports usbInventory/hidInventory/serialInventory = available.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMHardwareInventorySelfTest : NSObject
/// Runs the self-test, logging PASS/FAIL with details. Returns YES on pass.
+ (BOOL)runSelfTestLogging;
@end

NS_ASSUME_NONNULL_END
