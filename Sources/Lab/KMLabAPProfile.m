/*
 File:        KMLabAPProfile.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabAPProfile.h. Data + scope-binding only. NOT an AP.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabAPProfile.h"
#import "KMLabWorkflow.h"   // KMLabScopeChecking protocol
#import "../Safety/KMRedactionSettings.h"

NSString *KMStringFromLabAPSecurity(KMLabAPSecurity security) {
    switch (security) {
        case KMLabAPSecurityOpen:          return @"Open";
        case KMLabAPSecurityWEP:           return @"WEP";
        case KMLabAPSecurityWPA2Personal:  return @"WPA2-Personal";
        case KMLabAPSecurityWPA3Personal:  return @"WPA3-Personal";
        case KMLabAPSecurityEnterprise:    return @"Enterprise";
    }
    return @"Unknown";
}

@implementation KMLabAPProfile

- (instancetype)initWithLabel:(NSString *)label
                         ssid:(NSString *)ssid
                        bssid:(NSString *)bssid
                      channel:(NSInteger)channel
                     security:(KMLabAPSecurity)security {
    self = [super init];
    if (self) {
        _identifier = [[[NSUUID UUID] UUIDString] copy];
        _label = [label copy] ?: @"";
        _ssid = [ssid copy] ?: @"";
        _bssid = [bssid copy] ?: @"";
        _channel = channel;
        _security = security;
    }
    return self;
}

- (BOOL)isUsableWithScopeProvider:(id<KMLabScopeChecking>)scopeProvider {
    // FAIL CLOSED: no provider, no active scope, or either identifier not in
    // scope => not usable. Both BSSID and SSID must be authorized.
    if (![scopeProvider respondsToSelector:@selector(hasActiveScope)]) return NO;
    if (![scopeProvider hasActiveScope]) return NO;
    if (![scopeProvider scopeContainsBSSID:self.bssid]) return NO;
    if (![scopeProvider scopeContainsSSID:self.ssid]) return NO;
    return YES;
}

- (NSString *)redactedDescriptionWithSettings:(id)settings {
    NSString *ssid = self.ssid, *bssid = self.bssid;
    if ([settings isKindOfClass:[KMRedactionSettings class]]) {
        KMRedactionSettings *r = settings;
        ssid = [r redactSSID:self.ssid];
        bssid = [r redactMAC:self.bssid];
    }
    return [NSString stringWithFormat:@"%@: ssid=%@ bssid=%@ ch=%ld sec=%@",
            self.label, ssid, bssid, (long)self.channel,
            KMStringFromLabAPSecurity(self.security)];
}

- (NSString *)description {
    KMRedactionSettings *safe = [KMRedactionSettings defaultSettings];
    safe.enabled = YES;
    return [self redactedDescriptionWithSettings:safe];
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier forKey:@"identifier"];
    [coder encodeObject:self.label forKey:@"label"];
    [coder encodeObject:self.ssid forKey:@"ssid"];
    [coder encodeObject:self.bssid forKey:@"bssid"];
    [coder encodeInteger:self.channel forKey:@"channel"];
    [coder encodeInteger:self.security forKey:@"security"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *label = [coder decodeObjectOfClass:[NSString class] forKey:@"label"] ?: @"";
    NSString *ssid  = [coder decodeObjectOfClass:[NSString class] forKey:@"ssid"] ?: @"";
    NSString *bssid = [coder decodeObjectOfClass:[NSString class] forKey:@"bssid"] ?: @"";
    NSInteger channel = [coder decodeIntegerForKey:@"channel"];
    KMLabAPSecurity security = (KMLabAPSecurity)[coder decodeIntegerForKey:@"security"];
    self = [self initWithLabel:label ssid:ssid bssid:bssid channel:channel security:security];
    if (self) {
        NSString *ident = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        if (ident.length) _identifier = [ident copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KMLabAPProfile *c = [[KMLabAPProfile allocWithZone:zone]
                         initWithLabel:self.label ssid:self.ssid bssid:self.bssid
                         channel:self.channel security:self.security];
    c->_identifier = [self.identifier copy];
    return c;
}

@end
