/*
 File:        KMGATTProfile.m
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMGATTProfile.h"
#import <CoreBluetooth/CoreBluetooth.h>

@implementation KMGATTCharacteristic

- (instancetype)initWithUUID:(NSString *)uuid properties:(NSUInteger)properties {
    if ((self = [super init])) {
        _uuid = [uuid copy] ?: @"";
        _properties = properties;
    }
    return self;
}

- (NSString *)propertiesDescription {
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger p = self.properties;
    if (p & CBCharacteristicPropertyBroadcast)                   [parts addObject:@"broadcast"];
    if (p & CBCharacteristicPropertyRead)                        [parts addObject:@"read"];
    if (p & CBCharacteristicPropertyWriteWithoutResponse)        [parts addObject:@"writeNoResp"];
    if (p & CBCharacteristicPropertyWrite)                       [parts addObject:@"write"];
    if (p & CBCharacteristicPropertyNotify)                      [parts addObject:@"notify"];
    if (p & CBCharacteristicPropertyIndicate)                    [parts addObject:@"indicate"];
    if (p & CBCharacteristicPropertyAuthenticatedSignedWrites)   [parts addObject:@"signedWrite"];
    if (p & CBCharacteristicPropertyExtendedProperties)          [parts addObject:@"extended"];
    return parts.count ? [parts componentsJoinedByString:@", "] : @"none";
}

@end

@implementation KMGATTService

- (instancetype)initWithUUID:(NSString *)uuid primary:(BOOL)primary {
    if ((self = [super init])) {
        _uuid = [uuid copy] ?: @"";
        _primary = primary;
        _characteristics = @[];
    }
    return self;
}

@end

@implementation KMGATTProfile

- (instancetype)initWithDeviceIdentifier:(NSString *)identifier {
    if ((self = [super init])) {
        _deviceIdentifier = [identifier copy] ?: @"";
        _services = @[];
    }
    return self;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableArray *svcs = [NSMutableArray array];
    for (KMGATTService *s in self.services) {
        NSMutableArray *chars = [NSMutableArray array];
        for (KMGATTCharacteristic *c in s.characteristics) {
            [chars addObject:@{ @"uuid": c.uuid ?: @"",
                                @"properties": @(c.properties),
                                @"propertiesDescription": c.propertiesDescription }];
        }
        [svcs addObject:@{ @"uuid": s.uuid ?: @"",
                           @"primary": @(s.primary),
                           @"characteristics": chars }];
    }
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"deviceIdentifier"] = self.deviceIdentifier ?: @"";
    d[@"services"] = svcs;
    if (self.errorReason) d[@"errorReason"] = self.errorReason;
    return [d copy];
}

@end
