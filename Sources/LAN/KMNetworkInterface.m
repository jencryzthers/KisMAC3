/*
 File:        KMNetworkInterface.m
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMNetworkInterface.h"
#import "../Safety/KMRedactionSettings.h"

NSString *KMStringFromInterfaceType(KMInterfaceType type) {
    switch (type) {
        case KMInterfaceTypeWiFi:              return @"Wi-Fi";
        case KMInterfaceTypeEthernet:          return @"Ethernet";
        case KMInterfaceTypeThunderboltBridge: return @"Thunderbolt-bridge";
        case KMInterfaceTypeVPN:               return @"VPN";
        case KMInterfaceTypeAWDLPeer:          return @"AWDL/peer";
        case KMInterfaceTypeLoopback:          return @"loopback";
        case KMInterfaceTypeOther:             return @"other";
        case KMInterfaceTypeUnknown:
        default:                               return @"unknown";
    }
}

@implementation KMNetworkInterface

- (instancetype)init {
    if ((self = [super init])) {
        _bsdName = @"";
        _type = KMInterfaceTypeUnknown;
        _ipv4Addresses = @[];
        _ipv6Addresses = @[];
        _ipv4Netmasks = @[];
    }
    return self;
}

- (BOOL)hasIPAddress {
    return (self.ipv4Addresses.count > 0) || (self.ipv6Addresses.count > 0);
}

- (NSString *)flagsString {
    NSMutableArray<NSString *> *f = [NSMutableArray array];
    if (self.isUp)            [f addObject:@"UP"];
    if (self.isRunning)       [f addObject:@"RUNNING"];
    if (self.supportsBroadcast) [f addObject:@"BROADCAST"];
    if (self.isPointToPoint)  [f addObject:@"P2P"];
    if (self.isLoopback)      [f addObject:@"LOOPBACK"];
    return f.count ? [f componentsJoinedByString:@","] : @"-";
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"bsdName"] = self.bsdName ?: @"";
    d[@"type"] = KMStringFromInterfaceType(self.type);
    d[@"up"] = @(self.isUp);
    d[@"running"] = @(self.isRunning);
    d[@"broadcast"] = @(self.supportsBroadcast);
    d[@"pointToPoint"] = @(self.isPointToPoint);
    d[@"loopback"] = @(self.isLoopback);
    d[@"flags"] = @(self.flags);
    if (self.macAddress) d[@"macAddress"] = self.macAddress;
    if (self.ipv4Addresses.count) d[@"ipv4Addresses"] = self.ipv4Addresses;
    if (self.ipv6Addresses.count) d[@"ipv6Addresses"] = self.ipv6Addresses;
    if (self.ipv4Netmasks.count) d[@"ipv4Netmasks"] = self.ipv4Netmasks;
    d[@"primary"] = @(self.isPrimary);
    return d;
}

/// An IP address is a sensitive local identifier; mask it like a hostname so it
/// follows the same master/per-type (redactHostnames) switch. Keep enough
/// structure (first octet / IPv6 prefix) to stay debuggable but non-identifying.
/// (Mirrors KMLANService's redaction so the two LAN surfaces match.)
- (NSString *)redactedIP:(NSString *)ip withSettings:(KMRedactionSettings *)settings {
    if (ip.length == 0) return @"";
    if (!settings) return @"<redacted>";
    if (!settings.isEnabled || !settings.redactHostnames) return ip;
    NSArray<NSString *> *dots = [ip componentsSeparatedByString:@"."];
    if (dots.count == 4) {
        return [NSString stringWithFormat:@"%@.*.*.*", dots.firstObject];
    }
    if (ip.length > 4) {
        NSMutableString *out = [[ip substringToIndex:4] mutableCopy];
        for (NSUInteger i = 4; i < ip.length; i++) {
            unichar c = [ip characterAtIndex:i];
            if (c == ':' || c == '.' || c == '%') [out appendFormat:@"%C", c];
            else [out appendString:@"*"];
        }
        return out;
    }
    return @"****";
}

- (NSArray<NSString *> *)redactedIPs:(NSArray<NSString *> *)ips withSettings:(KMRedactionSettings *)settings {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *ip in ips) [out addObject:[self redactedIP:ip withSettings:settings]];
    return out;
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    // MAC masked via the S4.1 MAC transform (keeps the OUI for vendor context).
    NSString *mac;
    if (self.macAddress.length == 0) {
        mac = @"-";
    } else if (settings) {
        mac = [settings redactMAC:self.macAddress];
    } else {
        mac = @"<redacted>";   // no settings -> fully redacted (safe for logs)
    }

    NSArray<NSString *> *v4 = [self redactedIPs:self.ipv4Addresses withSettings:settings];
    NSArray<NSString *> *v6 = [self redactedIPs:self.ipv6Addresses withSettings:settings];
    NSString *v4Str = v4.count ? [v4 componentsJoinedByString:@","] : @"-";
    NSString *v6Str = v6.count ? [v6 componentsJoinedByString:@","] : @"-";

    return [NSString stringWithFormat:
            @"iface %@ [%@] flags=%@ mac=%@ v4=[%@] v6=[%@]%@",
            self.bsdName ?: @"?",
            KMStringFromInterfaceType(self.type),
            [self flagsString],
            mac, v4Str, v6Str,
            self.isPrimary ? @" (primary)" : @""];
}

- (NSString *)description {
    return [self redactedDescriptionWithSettings:nil];
}

@end
