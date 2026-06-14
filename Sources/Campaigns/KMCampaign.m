/*
 File:        KMCampaign.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMCampaign.h"

@interface KMCampaign ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSDate *createdAt;
@end

@implementation KMCampaign

- (instancetype)initWithLabel:(NSString *)label scope:(KMCampaignScope *)scope {
    if ((self = [super init])) {
        _identifier = [[NSUUID UUID] UUIDString];
        _label = [label copy] ?: @"Untitled campaign";
        // Default scope is a closed (distantFuture..distantPast) window -> never
        // active until a real scope is set. Fail closed.
        _scope = [scope copy] ?: [[KMCampaignScope alloc]
            initWithSSIDs:nil bssids:nil clientMACs:nil adapters:nil channels:nil
              windowStart:[NSDate distantFuture] windowEnd:[NSDate distantPast]];
        _authorized = NO;          // explicit opt-in required
        _emergencyStopped = NO;
        _createdAt = [NSDate date];
    }
    return self;
}

#pragma mark Fail-closed contract

- (BOOL)isActiveAtDate:(NSDate *)date {
    if (!self.authorized) return NO;
    if (self.emergencyStopped) return NO;
    if (![self.scope isWithinWindowAtDate:date]) return NO;
    return YES;
}

- (BOOL)isActive {
    return [self isActiveAtDate:[NSDate date]];
}

- (NSString *)inactiveReason {
    if (self.emergencyStopped) return @"Emergency stop engaged.";
    if (!self.authorized)      return @"Campaign is not explicitly authorized.";
    if (![self.scope isWithinWindowNow]) return @"Outside the authorized time window.";
    return nil;
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier   forKey:@"identifier"];
    [coder encodeObject:self.label        forKey:@"label"];
    [coder encodeBool:self.authorized     forKey:@"authorized"];
    [coder encodeObject:self.authorizedBy forKey:@"authorizedBy"];
    [coder encodeObject:self.scope        forKey:@"scope"];
    [coder encodeBool:self.emergencyStopped forKey:@"emergencyStopped"];
    [coder encodeObject:self.createdAt    forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *label = [coder decodeObjectOfClass:[NSString class] forKey:@"label"];
    KMCampaignScope *scope = [coder decodeObjectOfClass:[KMCampaignScope class] forKey:@"scope"];
    if ((self = [self initWithLabel:label scope:scope])) {
        NSString *ident = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        if (ident) _identifier = [ident copy];
        _authorized      = [coder decodeBoolForKey:@"authorized"];
        _authorizedBy    = [[coder decodeObjectOfClass:[NSString class] forKey:@"authorizedBy"] copy];
        _emergencyStopped = [coder decodeBoolForKey:@"emergencyStopped"];
        NSDate *created  = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        if (created) _createdAt = [created copy];
    }
    return self;
}

@end
