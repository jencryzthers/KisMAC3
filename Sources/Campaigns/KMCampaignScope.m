/*
 File:        KMCampaignScope.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMCampaignScope.h"

@implementation KMCampaignScope

- (instancetype)initWithSSIDs:(NSSet<NSString *> *)ssids
                       bssids:(NSSet<NSString *> *)bssids
                   clientMACs:(NSSet<NSString *> *)clientMACs
                     adapters:(NSSet<NSString *> *)adapters
                     channels:(NSSet<NSNumber *> *)channels
                  windowStart:(NSDate *)windowStart
                    windowEnd:(NSDate *)windowEnd {
    if ((self = [super init])) {
        // SSIDs: keep verbatim (case-insensitive matched at query time).
        _ssids   = [ssids copy] ?: [NSSet set];
        _adapters = [adapters copy] ?: [NSSet set];
        _channels = [channels copy] ?: [NSSet set];
        // MAC sets are stored NORMALIZED so membership is O(1) + robust to
        // separator/case differences.
        _bssids     = [[self class] normalizedMACSet:bssids];
        _clientMACs = [[self class] normalizedMACSet:clientMACs];
        // Defensive: a nil/garbage window must not silently become "always".
        _windowStart = [windowStart copy] ?: [NSDate distantFuture];
        _windowEnd   = [windowEnd copy] ?: [NSDate distantPast];
    }
    return self;
}

- (instancetype)init {
    return [self initWithSSIDs:nil bssids:nil clientMACs:nil adapters:nil
                      channels:nil
                   windowStart:[NSDate distantFuture]
                     windowEnd:[NSDate distantPast]];
}

#pragma mark Normalization

+ (NSString *)normalizedMAC:(NSString *)mac {
    if (![mac isKindOfClass:[NSString class]] || mac.length == 0) return nil;
    NSMutableString *out = [NSMutableString stringWithCapacity:mac.length];
    for (NSUInteger i = 0; i < mac.length; i++) {
        unichar c = [mac characterAtIndex:i];
        if (c == ':' || c == '-' || c == '.' || c == ' ') continue;
        // lowercase ascii hex
        if (c >= 'A' && c <= 'F') c = (unichar)(c - 'A' + 'a');
        [out appendFormat:@"%C", c];
    }
    return out.length ? [out copy] : nil;
}

+ (NSSet<NSString *> *)normalizedMACSet:(NSSet<NSString *> *)macs {
    NSMutableSet *out = [NSMutableSet setWithCapacity:macs.count];
    for (NSString *m in macs) {
        NSString *n = [self normalizedMAC:m];
        if (n) [out addObject:n];
    }
    return [out copy];
}

#pragma mark Time window

- (BOOL)isWithinWindowAtDate:(NSDate *)date {
    if (![date isKindOfClass:[NSDate class]]) return NO;
    // [start, end]; if start >= end the window is degenerate -> closed.
    if ([self.windowStart compare:self.windowEnd] != NSOrderedAscending) return NO;
    return ([date compare:self.windowStart] != NSOrderedAscending) &&
           ([date compare:self.windowEnd]   != NSOrderedDescending);
}

- (BOOL)isWithinWindowNow {
    return [self isWithinWindowAtDate:[NSDate date]];
}

#pragma mark Membership (fail-closed)

- (BOOL)containsSSID:(NSString *)ssid {
    if (![ssid isKindOfClass:[NSString class]] || ssid.length == 0) return NO;
    for (NSString *s in self.ssids) {
        if ([s caseInsensitiveCompare:ssid] == NSOrderedSame) return YES;
    }
    return NO;
}

- (BOOL)containsBSSID:(NSString *)bssid {
    NSString *n = [[self class] normalizedMAC:bssid];
    return n != nil && [self.bssids containsObject:n];
}

- (BOOL)containsClientMAC:(NSString *)mac {
    NSString *n = [[self class] normalizedMAC:mac];
    return n != nil && [self.clientMACs containsObject:n];
}

- (BOOL)containsAdapter:(NSString *)adapter {
    if (![adapter isKindOfClass:[NSString class]] || adapter.length == 0) return NO;
    for (NSString *a in self.adapters) {
        if ([a caseInsensitiveCompare:adapter] == NSOrderedSame) return YES;
    }
    return NO;
}

- (BOOL)containsChannel:(NSInteger)channel {
    return [self.channels containsObject:@(channel)];
}

#pragma mark Helpers

- (NSString *)contextSummary {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    return [NSString stringWithFormat:
        @"scope{ssids:%lu bssids:%lu clients:%lu adapters:%lu channels:%lu window:%@..%@}",
        (unsigned long)self.ssids.count, (unsigned long)self.bssids.count,
        (unsigned long)self.clientMACs.count, (unsigned long)self.adapters.count,
        (unsigned long)self.channels.count,
        [fmt stringFromDate:self.windowStart], [fmt stringFromDate:self.windowEnd]];
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.ssids      forKey:@"ssids"];
    [coder encodeObject:self.bssids     forKey:@"bssids"];
    [coder encodeObject:self.clientMACs forKey:@"clientMACs"];
    [coder encodeObject:self.adapters   forKey:@"adapters"];
    [coder encodeObject:self.channels   forKey:@"channels"];
    [coder encodeObject:self.windowStart forKey:@"windowStart"];
    [coder encodeObject:self.windowEnd   forKey:@"windowEnd"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSSet *strClasses = [NSSet setWithObjects:[NSSet class], [NSString class], nil];
    NSSet *numClasses = [NSSet setWithObjects:[NSSet class], [NSNumber class], nil];
    NSSet *ssids   = [coder decodeObjectOfClasses:strClasses forKey:@"ssids"];
    NSSet *bssids  = [coder decodeObjectOfClasses:strClasses forKey:@"bssids"];
    NSSet *clients = [coder decodeObjectOfClasses:strClasses forKey:@"clientMACs"];
    NSSet *adapters = [coder decodeObjectOfClasses:strClasses forKey:@"adapters"];
    NSSet *channels = [coder decodeObjectOfClasses:numClasses forKey:@"channels"];
    NSDate *start = [coder decodeObjectOfClass:[NSDate class] forKey:@"windowStart"];
    NSDate *end   = [coder decodeObjectOfClass:[NSDate class] forKey:@"windowEnd"];
    return [self initWithSSIDs:ssids bssids:bssids clientMACs:clients
                      adapters:adapters channels:channels
                   windowStart:start windowEnd:end];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    // Immutable value object.
    return self;
}

@end
