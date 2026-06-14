/*
 File:        KMCapability.m
 Program:     KisMac3
 Slice:       S1.3 - Capability engine core

 This file is part of KisMAC. GPL v2.
 */

#import "KMCapability.h"

#pragma mark - Capability keys

NSString * const KMFeatureScan                  = @"scan";
NSString * const KMFeaturePassiveCapture        = @"passiveCapture";
NSString * const KMFeaturePcapImport            = @"pcapImport";
NSString * const KMFeaturePcapExport            = @"pcapExport";
NSString * const KMFeatureChannelSwitching      = @"channelSwitching";
NSString * const KMFeatureMonitorMode           = @"monitorMode";
NSString * const KMFeatureAPMode                = @"apMode";
NSString * const KMFeatureFrameInjection        = @"frameInjection";
NSString * const KMFeatureDeauth                = @"deauth";
NSString * const KMFeatureHandshakeCapture      = @"handshakeCapture";
NSString * const KMFeatureKismetRemoteCapture   = @"kismetRemoteCapture";
NSString * const KMFeatureGPS                   = @"gps";
NSString * const KMFeatureMapPlotting           = @"mapPlotting";
NSString * const KMFeatureLANDiscovery          = @"lanDiscovery";
NSString * const KMFeatureBonjourInventory      = @"bonjourInventory";
NSString * const KMFeatureBLEScan               = @"bleScan";
NSString * const KMFeatureBLEGattEnumeration    = @"bleGattEnumeration";
NSString * const KMFeatureUSBInventory          = @"usbInventory";
NSString * const KMFeatureHIDInventory          = @"hidInventory";
NSString * const KMFeatureSerialInventory       = @"serialInventory";
NSString * const KMFeatureWiFi6Decode           = @"wifi6Decode";
NSString * const KMFeatureWPA3Decode            = @"wpa3Decode";
NSString * const KMFeatureOWEDecode             = @"oweDecode";
NSString * const KMFeatureEnterpriseDecode      = @"enterpriseDecode";
NSString * const KMFeatureSubGhzExternalModule  = @"subGhzExternalModule";
NSString * const KMFeatureNFCExternalModule     = @"nfcExternalModule";
NSString * const KMFeatureRFIDExternalModule    = @"rfidExternalModule";
NSString * const KMFeatureIRExternalModule      = @"irExternalModule";
NSString * const KMFeatureIButtonExternalModule = @"ibuttonExternalModule";

NSArray<NSString *> *KMAllFeatureKeys(void) {
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            KMFeatureScan,
            KMFeaturePassiveCapture,
            KMFeaturePcapImport,
            KMFeaturePcapExport,
            KMFeatureChannelSwitching,
            KMFeatureMonitorMode,
            KMFeatureAPMode,
            KMFeatureFrameInjection,
            KMFeatureDeauth,
            KMFeatureHandshakeCapture,
            KMFeatureKismetRemoteCapture,
            KMFeatureGPS,
            KMFeatureMapPlotting,
            KMFeatureLANDiscovery,
            KMFeatureBonjourInventory,
            KMFeatureBLEScan,
            KMFeatureBLEGattEnumeration,
            KMFeatureUSBInventory,
            KMFeatureHIDInventory,
            KMFeatureSerialInventory,
            KMFeatureWiFi6Decode,
            KMFeatureWPA3Decode,
            KMFeatureOWEDecode,
            KMFeatureEnterpriseDecode,
            KMFeatureSubGhzExternalModule,
            KMFeatureNFCExternalModule,
            KMFeatureRFIDExternalModule,
            KMFeatureIRExternalModule,
            KMFeatureIButtonExternalModule,
        ];
    });
    return keys;
}

#pragma mark - Stable tokens

NSString *KMStringFromCapabilityAvailability(KMCapabilityAvailability a) {
    switch (a) {
        case KMCapabilityAvailable:                    return @"available";
        case KMCapabilityUnavailable:                  return @"unavailable";
        case KMCapabilityUnknownRequiresActiveProbe:   return @"unknownRequiresActiveProbe";
    }
    return @"unavailable";
}

NSString *KMStringFromCapabilityReason(KMCapabilityReason r) {
    switch (r) {
        case KMCapabilityReasonNone:                       return @"none";
        case KMCapabilityReasonPermissionMissing:          return @"permissionMissing";
        case KMCapabilityReasonUnsupportedMacBookHardware: return @"unsupportedMacBookHardware";
        case KMCapabilityReasonUnsupportedAdapter:         return @"unsupportedAdapter";
        case KMCapabilityReasonMacOSBlocked:               return @"macOSBlocked";
        case KMCapabilityReasonProtocolParserMissing:      return @"protocolParserMissing";
        case KMCapabilityReasonActiveLabScopeMissing:      return @"activeLabScopeMissing";
        case KMCapabilityReasonUnknownRequiresActiveProbe: return @"unknownRequiresActiveProbe";
    }
    return @"none";
}

#pragma mark - KMCapability

@interface KMCapability ()
@property (nonatomic, copy, readwrite) NSString *key;
@property (nonatomic, assign, readwrite) KMCapabilityAvailability availability;
@property (nonatomic, assign, readwrite) KMCapabilityReason reason;
@property (nonatomic, copy, readwrite) NSString *explanation;
@end

@implementation KMCapability

+ (instancetype)capabilityWithKey:(NSString *)key
                     availability:(KMCapabilityAvailability)availability
                           reason:(KMCapabilityReason)reason
                      explanation:(NSString *)explanation {
    KMCapability *c = [[self alloc] init];
    c.key = key;
    c.availability = availability;
    c.reason = reason;
    c.explanation = explanation ?: @"";
    return c;
}

+ (instancetype)availableCapabilityWithKey:(NSString *)key
                               explanation:(NSString *)explanation {
    return [self capabilityWithKey:key
                      availability:KMCapabilityAvailable
                            reason:KMCapabilityReasonNone
                       explanation:explanation];
}

+ (instancetype)unavailableCapabilityWithKey:(NSString *)key
                                      reason:(KMCapabilityReason)reason
                                 explanation:(NSString *)explanation {
    return [self capabilityWithKey:key
                      availability:KMCapabilityUnavailable
                            reason:reason
                       explanation:explanation];
}

- (BOOL)isAvailable {
    return self.availability == KMCapabilityAvailable;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"key":          self.key ?: @"",
        @"availability": KMStringFromCapabilityAvailability(self.availability),
        @"reason":       KMStringFromCapabilityReason(self.reason),
        @"explanation":  self.explanation ?: @"",
    };
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ = %@ / %@ (%@)>",
            NSStringFromClass([self class]), self.key,
            KMStringFromCapabilityAvailability(self.availability),
            KMStringFromCapabilityReason(self.reason),
            self.explanation];
}

@end
