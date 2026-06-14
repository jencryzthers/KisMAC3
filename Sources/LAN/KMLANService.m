/*
 File:        KMLANService.m
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 This file is part of KisMAC. GPL v2.
 */

#import "KMLANService.h"
#import "../Safety/KMRedactionSettings.h"

@implementation KMLANService

- (instancetype)init {
    if ((self = [super init])) {
        _domain = @"local.";
        _type = @"";
        _ipAddresses = @[];
    }
    return self;
}

- (BOOL)isResolved {
    return (self.hostName.length > 0) || (self.ipAddresses.count > 0);
}

- (NSString *)identityKey {
    return [NSString stringWithFormat:@"%@|%@|%@",
            self.type ?: @"", self.name ?: @"", self.domain ?: @""];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.name) d[@"name"] = self.name;
    if (self.type) d[@"type"] = self.type;
    if (self.domain) d[@"domain"] = self.domain;
    if (self.hostName) d[@"hostName"] = self.hostName;
    if (self.port) d[@"port"] = @(self.port);
    if (self.ipAddresses.count) d[@"ipAddresses"] = self.ipAddresses;
    d[@"resolved"] = @(self.isResolved);
    return d;
}

/// An IP address is a sensitive local identifier; mask it like a hostname so it
/// follows the same master/per-type (redactHostnames) switch. Keep enough
/// structure (first octet / IPv6 prefix) to stay debuggable but non-identifying.
- (NSString *)redactedIP:(NSString *)ip withSettings:(KMRedactionSettings *)settings {
    if (ip.length == 0) return @"";
    if (!settings) return @"<redacted>";
    if (!settings.isEnabled || !settings.redactHostnames) return ip;
    // IPv4: keep first octet, mask the rest.
    NSArray<NSString *> *dots = [ip componentsSeparatedByString:@"."];
    if (dots.count == 4) {
        return [NSString stringWithFormat:@"%@.*.*.*", dots.firstObject];
    }
    // IPv6 (or anything else): keep a short prefix, mask the remainder.
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

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    // Instance name + resolved hostname are masked via the hostname transform
    // (the instance name often embeds a personal device/owner name).
    NSString *name = self.name ?: @"?";
    NSString *host = self.hostName ?: @"-";
    if (settings) {
        name = [settings redactHostname:name];
        host = (self.hostName.length ? [settings redactHostname:self.hostName] : @"-");
    } else {
        // No settings -> fully redacted (safe default for logs).
        name = @"<redacted>";
        host = (self.hostName.length ? @"<redacted>" : @"-");
    }

    NSMutableArray<NSString *> *ips = [NSMutableArray array];
    for (NSString *ip in self.ipAddresses) {
        [ips addObject:[self redactedIP:ip withSettings:settings]];
    }
    NSString *ipStr = ips.count ? [ips componentsJoinedByString:@","] : @"-";

    return [NSString stringWithFormat:@"Bonjour %@ \"%@\" host=%@ port=%lu ip=[%@] %@",
            self.type ?: @"?", name, host, (unsigned long)self.port, ipStr,
            self.isResolved ? @"(resolved)" : @"(announced)"];
}

- (NSString *)description {
    return [self redactedDescriptionWithSettings:nil];
}

@end
