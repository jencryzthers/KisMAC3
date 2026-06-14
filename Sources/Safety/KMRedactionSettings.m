/*
 File:        KMRedactionSettings.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMRedactionSettings.h"

@implementation KMRedactionSettings

- (instancetype)init {
    if ((self = [super init])) {
        _enabled = NO;                    // parity: off by default
        _redactMACAddresses = YES;
        _redactSSIDs = YES;
        _redactHostnames = YES;
        _redactBluetoothIdentifiers = YES;
    }
    return self;
}

+ (instancetype)defaultSettings {
    return [[self alloc] init];
}

#pragma mark Typed single-value redaction

- (NSString *)redactMAC:(NSString *)mac {
    if (![mac isKindOfClass:[NSString class]] || mac.length == 0) return mac ?: @"";
    if (!self.enabled || !self.redactMACAddresses) return mac;
    // Keep the OUI (first 3 octets), mask the device portion. Works for
    // colon/dash separated forms; for unseparated, mask all but first 6 hex.
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@":-"];
    if ([mac rangeOfCharacterFromSet:sep].location != NSNotFound) {
        NSMutableArray *parts = [[mac componentsSeparatedByCharactersInSet:sep] mutableCopy];
        for (NSUInteger i = 3; i < parts.count; i++) parts[i] = @"**";
        // Preserve the original separator (use ':' canonical).
        return [parts componentsJoinedByString:@":"];
    }
    if (mac.length > 6) {
        NSMutableString *out = [[mac substringToIndex:6] mutableCopy];
        for (NSUInteger i = 6; i < mac.length; i++) [out appendString:@"*"];
        return out;
    }
    return @"******";
}

- (NSString *)maskKeepingEnds:(NSString *)s {
    if (s.length <= 2) {
        NSMutableString *m = [NSMutableString string];
        for (NSUInteger i = 0; i < s.length; i++) [m appendString:@"*"];
        return m.length ? m : @"*";
    }
    NSMutableString *out = [[s substringToIndex:1] mutableCopy];
    for (NSUInteger i = 1; i < s.length - 1; i++) [out appendString:@"*"];
    [out appendString:[s substringFromIndex:s.length - 1]];
    return out;
}

- (NSString *)redactSSID:(NSString *)ssid {
    if (![ssid isKindOfClass:[NSString class]] || ssid.length == 0) return ssid ?: @"";
    if (!self.enabled || !self.redactSSIDs) return ssid;
    return [self maskKeepingEnds:ssid];
}

- (NSString *)redactHostname:(NSString *)hostname {
    if (![hostname isKindOfClass:[NSString class]] || hostname.length == 0) return hostname ?: @"";
    if (!self.enabled || !self.redactHostnames) return hostname;
    NSRange dot = [hostname rangeOfString:@"."];
    if (dot.location == NSNotFound) {
        return [self maskKeepingEnds:hostname];
    }
    NSString *label = [hostname substringToIndex:dot.location];
    NSString *rest  = [hostname substringFromIndex:dot.location]; // includes leading '.'
    return [[self maskKeepingEnds:label] stringByAppendingString:rest];
}

- (NSString *)redactBluetoothIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return identifier ?: @"";
    if (!self.enabled || !self.redactBluetoothIdentifiers) return identifier;
    // BLE addresses look like MACs; UUIDs are longer. Mask everything but a
    // short non-identifying prefix.
    if (identifier.length <= 4) {
        return @"****";
    }
    NSMutableString *out = [[identifier substringToIndex:4] mutableCopy];
    for (NSUInteger i = 4; i < identifier.length; i++) {
        unichar c = [identifier characterAtIndex:i];
        // keep structural separators so shape is recognizable
        if (c == ':' || c == '-' || c == '.') [out appendFormat:@"%C", c];
        else [out appendString:@"*"];
    }
    return out;
}

#pragma mark Free-text redaction

- (NSString *)redactString:(NSString *)text {
    return [self redactString:text knownSSIDs:nil knownHostnames:nil];
}

- (NSString *)redactString:(NSString *)text
              knownSSIDs:(NSArray<NSString *> *)ssids
           knownHostnames:(NSArray<NSString *> *)hostnames {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return text ?: @"";
    if (!self.enabled) return text;

    NSMutableString *result = [text mutableCopy];

    // 1) MACs are reliably pattern-detectable -> mask in place.
    if (self.redactMACAddresses) {
        static NSRegularExpression *macRE = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // 6 hex octets separated by ':' or '-'
            macRE = [NSRegularExpression regularExpressionWithPattern:
                     @"\\b([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\\b"
                                                              options:0 error:NULL];
        });
        // Replace each match with its OUI-preserving redaction (back-to-front
        // so ranges stay valid).
        NSArray<NSTextCheckingResult *> *matches =
            [macRE matchesInString:result options:0 range:NSMakeRange(0, result.length)];
        for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
            NSRange r = matches[i].range;
            NSString *orig = [result substringWithRange:r];
            [result replaceCharactersInRange:r withString:[self redactMAC:orig]];
        }
    }

    // 2) Known SSIDs / hostnames: literal substitution (longest first to avoid
    //    partial-overlap surprises).
    if (self.redactSSIDs && ssids.count) {
        NSArray *sorted = [ssids sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [@(b.length) compare:@(a.length)];
        }];
        for (NSString *s in sorted) {
            if (s.length == 0) continue;
            [result replaceOccurrencesOfString:s withString:[self redactSSID:s]
                                       options:NSLiteralSearch range:NSMakeRange(0, result.length)];
        }
    }
    if (self.redactHostnames && hostnames.count) {
        NSArray *sorted = [hostnames sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [@(b.length) compare:@(a.length)];
        }];
        for (NSString *h in sorted) {
            if (h.length == 0) continue;
            [result replaceOccurrencesOfString:h withString:[self redactHostname:h]
                                       options:NSLiteralSearch range:NSMakeRange(0, result.length)];
        }
    }

    return [result copy];
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.enabled forKey:@"enabled"];
    [coder encodeBool:self.redactMACAddresses forKey:@"redactMACAddresses"];
    [coder encodeBool:self.redactSSIDs forKey:@"redactSSIDs"];
    [coder encodeBool:self.redactHostnames forKey:@"redactHostnames"];
    [coder encodeBool:self.redactBluetoothIdentifiers forKey:@"redactBluetoothIdentifiers"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [self init])) {
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _redactMACAddresses = [coder decodeBoolForKey:@"redactMACAddresses"];
        _redactSSIDs = [coder decodeBoolForKey:@"redactSSIDs"];
        _redactHostnames = [coder decodeBoolForKey:@"redactHostnames"];
        _redactBluetoothIdentifiers = [coder decodeBoolForKey:@"redactBluetoothIdentifiers"];
    }
    return self;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    KMRedactionSettings *c = [[KMRedactionSettings allocWithZone:zone] init];
    c->_enabled = _enabled;
    c->_redactMACAddresses = _redactMACAddresses;
    c->_redactSSIDs = _redactSSIDs;
    c->_redactHostnames = _redactHostnames;
    c->_redactBluetoothIdentifiers = _redactBluetoothIdentifiers;
    return c;
}

@end
