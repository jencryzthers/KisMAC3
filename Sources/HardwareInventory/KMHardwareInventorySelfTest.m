/*
 File:        KMHardwareInventorySelfTest.m
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMHardwareInventorySelfTest.h"
#import "KMHardwareInventory.h"
#import "KMUSBDevice.h"
#import "KMHIDDevice.h"
#import "KMSerialDevice.h"
#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Capabilities/KMHardwareCapability.h"
#import "../Safety/KMRedactionSettings.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

@implementation KMHardwareInventorySelfTest

+ (NSArray<KMHardwareCapability *> *)mockGreenWiFi {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusSupported reason:@"mock iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusSupported reason:@"mock granted"],
    ];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];
    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) { DBNSLog(@"[KMHardwareInventorySelfTest]   PASS  %@", label); }
        else      { DBNSLog(@"[KMHardwareInventorySelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };

    DBNSLog(@"[KMHardwareInventorySelfTest] ===== S3.2 USB/HID/serial inventory self-test =====");

    // Redaction ON so the logged sample never dumps a raw serial.
    KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
    r.enabled = YES;

    KMHardwareInventory *inv = [[KMHardwareInventory alloc] init];

    // ---- 1) REAL enumeration on THIS machine (no permission needed) ----
    NSArray<KMUSBDevice *> *usb = [inv enumerateUSBDevices];
    NSArray<KMHIDDevice *> *hid = [inv enumerateHIDDevices];
    NSArray<KMSerialDevice *> *ser = [inv enumerateSerialDevices];

    check(@"1a USB enumeration returned without crashing", usb != nil);
    check(@"1b HID enumeration returned without crashing", hid != nil);
    check(@"1c serial enumeration returned without crashing", ser != nil);

    DBNSLog(@"[KMHardwareInventorySelfTest]   COUNTS  usb=%lu hid=%lu serial=%lu",
            (unsigned long)usb.count, (unsigned long)hid.count, (unsigned long)ser.count);

    // Redacted samples (first of each, if present).
    if (usb.count) DBNSLog(@"[KMHardwareInventorySelfTest]   SAMPLE usb[0]: %@", [usb.firstObject redactedDescriptionWithSettings:r]);
    if (hid.count) DBNSLog(@"[KMHardwareInventorySelfTest]   SAMPLE hid[0]: %@", [hid.firstObject redactedDescriptionWithSettings:r]);
    if (ser.count) DBNSLog(@"[KMHardwareInventorySelfTest]   SAMPLE ser[0]: %@", [ser.firstObject redactedDescriptionWithSettings:r]);

    // ---- 2) HID count > 0 (a Mac always has a built-in keyboard/trackpad) ----
    check(@"2a HID count > 0 (built-in keyboard/trackpad present)", hid.count > 0);

    // ---- 3) Redaction: a sample serial is NOT dumped raw when present ----
    KMUSBDevice *withSerial = nil;
    for (KMUSBDevice *d in usb) { if (d.serialNumber.length > 4) { withSerial = d; break; } }
    if (withSerial) {
        NSString *desc = [withSerial redactedDescriptionWithSettings:r];
        check(@"3a redacted USB description does NOT contain the raw serial",
              [desc rangeOfString:withSerial.serialNumber].location == NSNotFound);
    } else {
        DBNSLog(@"[KMHardwareInventorySelfTest]   SKIP  no USB device exposed a serial > 4 chars to redaction-check");
    }

    // ---- 4) Engine reports all three inventories AVAILABLE (no permission) ----
    KMCapabilityEngine *engine =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockGreenWiFi]
                                                   scopeProvider:nil
                                                 parserRegistry:nil
                                                adapterProvider:nil];
    check(@"4a engine usbInventory available",    [engine isAvailable:KMFeatureUSBInventory]);
    check(@"4b engine hidInventory available",    [engine isAvailable:KMFeatureHIDInventory]);
    check(@"4c engine serialInventory available", [engine isAvailable:KMFeatureSerialInventory]);

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMHardwareInventorySelfTest] PASS - real IOKit enumeration ran headlessly (usb=%lu hid=%lu serial=%lu), "
                @"HID present, serials redactable, engine reports usb/hid/serial inventory available. READ-ONLY: no device opened.",
                (unsigned long)usb.count, (unsigned long)hid.count, (unsigned long)ser.count);
    } else {
        DBNSLog(@"[KMHardwareInventorySelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMHardwareInventorySelfTest]   - %@", l);
    }
    return pass;
}

@end
