/*
 File:        KMBluetoothDevice.m
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMBluetoothDevice.h"
#import "../Safety/KMRedactionSettings.h"

@interface KMBluetoothDevice ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSDate *firstSeen;
@end

@implementation KMBluetoothDevice

- (instancetype)initWithIdentifier:(NSString *)identifier {
    if ((self = [super init])) {
        _identifier = [identifier copy] ?: @"";
        _serviceUUIDs = @[];
        _rssi = 127;            // CoreBluetooth "RSSI not available" sentinel
        _connectable = NO;
        _observationCount = 0;
        _firstSeen = [NSDate date];
        _lastSeen = _firstSeen;
    }
    return self;
}

- (NSInteger)manufacturerCompanyIdentifier {
    if (self.manufacturerData.length < 2) return -1;
    const uint8_t *b = (const uint8_t *)self.manufacturerData.bytes;
    return (NSInteger)(b[0] | (b[1] << 8));   // little-endian company ID
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"identifier"]       = self.identifier ?: @"";
    if (self.localName)        d[@"localName"] = self.localName;
    d[@"serviceUUIDs"]     = self.serviceUUIDs ?: @[];
    d[@"rssi"]             = @(self.rssi);
    d[@"connectable"]      = @(self.connectable);
    d[@"observationCount"] = @(self.observationCount);
    NSInteger company = [self manufacturerCompanyIdentifier];
    if (company >= 0)          d[@"manufacturerCompanyId"] = @(company);
    if (self.manufacturerData) d[@"manufacturerDataLength"] = @(self.manufacturerData.length);
    if (self.firstSeen)        d[@"firstSeen"] = @([self.firstSeen timeIntervalSince1970]);
    if (self.lastSeen)         d[@"lastSeen"]  = @([self.lastSeen timeIntervalSince1970]);
    return [d copy];
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    NSString *ident = self.identifier ?: @"";
    NSString *name  = self.localName  ?: @"(no name)";
    if (settings) {
        ident = [settings redactBluetoothIdentifier:ident];
        // Reuse the SSID masker shape for the local name (also an identifier).
        if (settings.isEnabled && settings.redactBluetoothIdentifiers && self.localName) {
            name = [settings redactSSID:self.localName];
        }
    } else {
        // No settings -> fully mask the identifier for log safety.
        ident = ident.length > 8 ? [[ident substringToIndex:8] stringByAppendingString:@"-****"]
                                 : @"****";
        name  = @"(redacted)";
    }
    return [NSString stringWithFormat:@"BLE %@ name=%@ svc=%lu rssi=%ld conn=%@ seen=%lu",
            ident, name, (unsigned long)self.serviceUUIDs.count,
            (long)self.rssi, self.connectable ? @"Y" : @"N",
            (unsigned long)self.observationCount];
}

- (NSString *)description {
    // Default description is REDACTED for safety (don't leak raw identifiers to
    // generic logging / debugger po unless the caller explicitly asks).
    return [self redactedDescriptionWithSettings:nil];
}

@end
