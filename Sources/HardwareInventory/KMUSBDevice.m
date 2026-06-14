/*
 File:        KMUSBDevice.m
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMUSBDevice.h"
#import "../Safety/KMRedactionSettings.h"

@implementation KMUSBDevice

- (instancetype)init {
    if ((self = [super init])) {
        _vendorID = -1;
        _productID = -1;
        _deviceClass = -1;
        _deviceSubClass = -1;
    }
    return self;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"vendorID"] = @(self.vendorID);
    d[@"productID"] = @(self.productID);
    if (self.vendorName) d[@"vendorName"] = self.vendorName;
    if (self.productName) d[@"productName"] = self.productName;
    d[@"deviceClass"] = @(self.deviceClass);
    d[@"deviceSubClass"] = @(self.deviceSubClass);
    if (self.serialNumber) d[@"serialNumber"] = self.serialNumber;
    if (self.locationID) d[@"locationID"] = self.locationID;
    if (self.servicePath) d[@"servicePath"] = self.servicePath;
    if (self.speed) d[@"speed"] = self.speed;
    return d;
}

/// A serial number is a stable hardware identifier; treat it like a MAC for
/// redaction so it follows the same master/per-type switches.
- (NSString *)redactedSerialWithSettings:(KMRedactionSettings *)settings {
    if (self.serialNumber.length == 0) return @"-";
    if (settings) {
        // Reuse the Bluetooth-identifier transform: it masks all but a short
        // non-identifying prefix, which is the right shape for a serial.
        return [settings redactBluetoothIdentifier:self.serialNumber];
    }
    // No settings -> fully redacted (safe default for logs).
    return @"<redacted>";
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    NSString *vid = (self.vendorID >= 0) ? [NSString stringWithFormat:@"0x%04lX", (long)self.vendorID] : @"?";
    NSString *pid = (self.productID >= 0) ? [NSString stringWithFormat:@"0x%04lX", (long)self.productID] : @"?";
    return [NSString stringWithFormat:@"USB %@:%@ class=%ld/%ld \"%@\" / \"%@\" serial=%@ loc=%@ speed=%@",
            vid, pid, (long)self.deviceClass, (long)self.deviceSubClass,
            self.vendorName ?: @"?", self.productName ?: @"?",
            [self redactedSerialWithSettings:settings],
            self.locationID ?: @"?", self.speed ?: @"?"];
}

- (NSString *)description {
    return [self redactedDescriptionWithSettings:nil];
}

@end
