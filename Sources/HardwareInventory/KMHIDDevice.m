/*
 File:        KMHIDDevice.m
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMHIDDevice.h"
#import "../Safety/KMRedactionSettings.h"

// HID usage-page / usage constants we classify against (from IOHIDUsageTables.h).
// Declared locally so the header stays self-contained (Foundation only).
enum {
    KMHIDPageGenericDesktop = 0x01,
    KMHIDPageConsumer       = 0x0C,
};
enum {
    KMHIDUsageGD_Pointer   = 0x01,
    KMHIDUsageGD_Mouse     = 0x02,
    KMHIDUsageGD_Joystick  = 0x04,
    KMHIDUsageGD_GamePad   = 0x05,
    KMHIDUsageGD_Keyboard  = 0x06,
    KMHIDUsageGD_Keypad    = 0x07,
    KMHIDUsageGD_MultiAxis = 0x08,
};

@implementation KMHIDDevice

- (instancetype)init {
    if ((self = [super init])) {
        _usagePage = -1;
        _usage = -1;
        _vendorID = -1;
        _productID = -1;
    }
    return self;
}

- (NSString *)category {
    if (self.usagePage == KMHIDPageGenericDesktop) {
        switch (self.usage) {
            case KMHIDUsageGD_Keyboard:
            case KMHIDUsageGD_Keypad:    return @"Keyboard";
            case KMHIDUsageGD_Mouse:
            case KMHIDUsageGD_Pointer:   return @"Pointing device";
            case KMHIDUsageGD_Joystick:
            case KMHIDUsageGD_GamePad:
            case KMHIDUsageGD_MultiAxis: return @"Game controller";
            default: break;
        }
    }
    if (self.usagePage == KMHIDPageConsumer) {
        return @"Consumer/remote";
    }
    return @"Other HID";
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"usagePage"] = @(self.usagePage);
    d[@"usage"] = @(self.usage);
    d[@"category"] = self.category;
    d[@"vendorID"] = @(self.vendorID);
    d[@"productID"] = @(self.productID);
    if (self.productName) d[@"productName"] = self.productName;
    if (self.manufacturer) d[@"manufacturer"] = self.manufacturer;
    if (self.transport) d[@"transport"] = self.transport;
    if (self.serialNumber) d[@"serialNumber"] = self.serialNumber;
    return d;
}

- (NSString *)redactedSerialWithSettings:(KMRedactionSettings *)settings {
    if (self.serialNumber.length == 0) return @"-";
    if (settings) return [settings redactBluetoothIdentifier:self.serialNumber];
    return @"<redacted>";
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    NSString *vid = (self.vendorID >= 0) ? [NSString stringWithFormat:@"0x%04lX", (long)self.vendorID] : @"?";
    NSString *pid = (self.productID >= 0) ? [NSString stringWithFormat:@"0x%04lX", (long)self.productID] : @"?";
    return [NSString stringWithFormat:@"HID [%@] usage=%ld/%ld %@:%@ \"%@\" transport=%@ serial=%@",
            self.category, (long)self.usagePage, (long)self.usage, vid, pid,
            self.productName ?: @"?", self.transport ?: @"?",
            [self redactedSerialWithSettings:settings]];
}

- (NSString *)description {
    return [self redactedDescriptionWithSettings:nil];
}

@end
