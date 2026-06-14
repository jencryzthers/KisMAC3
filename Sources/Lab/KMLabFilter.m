/*
 File:        KMLabFilter.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabFilter.h. Pure data + matching; display filter only.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabFilter.h"
#import "../Campaigns/KMCampaignScope.h"  // +normalizedMAC:

@implementation KMLabFilter

+ (instancetype)emptyFilter {
    KMLabFilter *f = [[self alloc] init];
    f.allowClientMACs = [NSSet set];
    f.denyClientMACs = [NSSet set];
    f.allowSSIDs = [NSSet set];
    f.denySSIDs = [NSSet set];
    return f;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _allowClientMACs = [NSSet set];
        _denyClientMACs = [NSSet set];
        _allowSSIDs = [NSSet set];
        _denySSIDs = [NSSet set];
    }
    return self;
}

// Build a normalized-MAC set so membership is separator/case-insensitive.
static NSSet<NSString *> *normalizedMACSet(NSSet<NSString *> *raw) {
    NSMutableSet<NSString *> *out = [NSMutableSet setWithCapacity:raw.count];
    for (NSString *m in raw) {
        NSString *n = [KMCampaignScope normalizedMAC:m];
        if (n) [out addObject:n];
    }
    return out;
}

- (BOOL)allowsClientMAC:(NSString *)mac {
    NSString *n = [KMCampaignScope normalizedMAC:mac];
    // A nil/unparseable MAC: deny only if there's an allow-list that it can't be
    // in (fail-open is for display; an allow-list means "show only these").
    NSSet<NSString *> *deny = normalizedMACSet(self.denyClientMACs);
    NSSet<NSString *> *allow = normalizedMACSet(self.allowClientMACs);
    if (n && [deny containsObject:n]) return NO;   // deny overrides
    if (allow.count == 0) return YES;              // no allow restriction
    return (n != nil) && [allow containsObject:n];
}

- (BOOL)allowsSSID:(NSString *)ssid {
    NSString *s = ssid ?: @"";
    if ([self.denySSIDs containsObject:s]) return NO;  // deny overrides
    if (self.allowSSIDs.count == 0) return YES;        // no allow restriction
    return [self.allowSSIDs containsObject:s];
}

- (BOOL)allowsClientMAC:(NSString *)mac ssid:(NSString *)ssid {
    BOOL clientOK = (mac == nil) ? YES : [self allowsClientMAC:mac];
    BOOL ssidOK   = (ssid == nil) ? YES : [self allowsSSID:ssid];
    return clientOK && ssidOK;
}

- (id)copyWithZone:(NSZone *)zone {
    KMLabFilter *c = [[KMLabFilter allocWithZone:zone] init];
    c.allowClientMACs = [self.allowClientMACs copy];
    c.denyClientMACs = [self.denyClientMACs copy];
    c.allowSSIDs = [self.allowSSIDs copy];
    c.denySSIDs = [self.denySSIDs copy];
    return c;
}

@end
