/*
 File:        KMHardwareCapability.m
 Program:     KisMac3
 Slice:       S1.1 - MacBook hardware capability probe

 This file is part of KisMAC. GPL v2.
 */

#import "KMHardwareCapability.h"

NSString * const KMCapWiFiInterfacePresent  = @"wifi.interface.present";
NSString * const KMCapLocationAuthorization = @"location.authorization";
NSString * const KMCapCoreWLANScan          = @"corewlan.scan";
NSString * const KMCapBand24GHz             = @"band.2_4ghz";
NSString * const KMCapBand5GHz              = @"band.5ghz";
NSString * const KMCapBand6GHz              = @"band.6ghz";
NSString * const KMCapPHYMetadata           = @"phy.metadata";
NSString * const KMCapPcapOpen              = @"pcap.open";
NSString * const KMCapDatalinkEnumeration   = @"pcap.datalinks";
NSString * const KMCapMonitorCapture        = @"capture.monitor";
NSString * const KMCapChannelSwitching      = @"channel.switching";
NSString * const KMCapAPMode                = @"ap.softap";
NSString * const KMCapFrameInjection        = @"frame.injection";

NSString *KMStringFromCapabilityStatus(KMCapabilityStatus status) {
    switch (status) {
        case KMCapabilityStatusSupported:                     return @"supported";
        case KMCapabilityStatusUnsupported:                   return @"unsupported";
        case KMCapabilityStatusPermissionMissing:             return @"permissionMissing";
        case KMCapabilityStatusMacOSBlocked:                  return @"macOSBlocked";
        case KMCapabilityStatusUnknownRequiresActiveProbe:    return @"unknownRequiresActiveProbe";
    }
    return @"unknownRequiresActiveProbe";
}

@interface KMHardwareCapability ()
@property (nonatomic, copy, readwrite) NSString *key;
@property (nonatomic, assign, readwrite) KMCapabilityStatus status;
@property (nonatomic, copy, readwrite) NSString *reason;
@property (nonatomic, copy, readwrite, nullable) NSString *remediation;
@end

@implementation KMHardwareCapability

+ (instancetype)capabilityWithKey:(NSString *)key
                           status:(KMCapabilityStatus)status
                           reason:(NSString *)reason {
    return [self capabilityWithKey:key status:status reason:reason remediation:nil];
}

+ (instancetype)capabilityWithKey:(NSString *)key
                           status:(KMCapabilityStatus)status
                           reason:(NSString *)reason
                      remediation:(nullable NSString *)remediation {
    KMHardwareCapability *cap = [[self alloc] init];
    cap.key = key;
    cap.status = status;
    cap.reason = reason ?: @"";
    cap.remediation = remediation;
    return cap;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"key"]    = self.key ?: @"";
    d[@"status"] = KMStringFromCapabilityStatus(self.status);
    d[@"reason"] = self.reason ?: @"";
    if (self.remediation.length) {
        d[@"remediation"] = self.remediation;
    }
    return d;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ = %@ (%@)>",
            NSStringFromClass([self class]), self.key,
            KMStringFromCapabilityStatus(self.status), self.reason];
}

@end
