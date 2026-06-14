/*
 File:        KMCampaignManager.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMCampaignManager.h"
#import "KMAuditLog.h"

NSString * const KMActiveScopeChangedNotification   = @"KMActiveScopeChangedNotification";
NSString * const KMEmergencyStopEngagedNotification = @"KMEmergencyStopEngagedNotification";

#pragma mark - Real scope provider

@interface KMActiveCampaignScopeProvider ()
@property (nonatomic, weak) KMCampaignManager *manager;
@end

@implementation KMActiveCampaignScopeProvider

- (instancetype)initWithManager:(KMCampaignManager *)manager {
    if ((self = [super init])) {
        _manager = manager;
    }
    return self;
}

/// The active campaign IFF it is currently active; nil otherwise (fail closed).
- (KMCampaign *)activeCampaign {
    KMCampaignManager *m = self.manager;
    if (!m) return nil;                       // no manager -> no scope
    if (m.isEmergencyStopped) return nil;     // latched stop -> no scope
    KMCampaign *c = m.currentCampaign;
    if (c && [c isActive]) return c;          // authorized + in-window + !stopped
    return nil;
}

- (BOOL)hasActiveScope {
    return [self activeCampaign] != nil;
}

- (BOOL)scopeContainsBSSID:(NSString *)bssid {
    KMCampaign *c = [self activeCampaign];
    return c != nil && [c.scope containsBSSID:bssid];
}
- (BOOL)scopeContainsClientMAC:(NSString *)mac {
    KMCampaign *c = [self activeCampaign];
    return c != nil && [c.scope containsClientMAC:mac];
}
- (BOOL)scopeContainsSSID:(NSString *)ssid {
    KMCampaign *c = [self activeCampaign];
    return c != nil && [c.scope containsSSID:ssid];
}
- (BOOL)scopeContainsChannel:(NSInteger)channel {
    KMCampaign *c = [self activeCampaign];
    return c != nil && [c.scope containsChannel:channel];
}
- (BOOL)scopeContainsAdapter:(NSString *)adapter {
    KMCampaign *c = [self activeCampaign];
    return c != nil && [c.scope containsAdapter:adapter];
}

@end

#pragma mark - Campaign manager

@interface KMCampaignManager ()
@property (nonatomic, strong) KMAuditLog *auditLog;
@property (nonatomic, assign, getter=isEmergencyStopped) BOOL emergencyStopped;
@property (nonatomic, strong) KMActiveCampaignScopeProvider *scopeProvider;
@end

@implementation KMCampaignManager

+ (instancetype)sharedManager {
    static KMCampaignManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[self alloc] initWithAuditLog:[KMAuditLog sharedLog]];
    });
    return shared;
}

- (instancetype)initWithAuditLog:(KMAuditLog *)auditLog {
    if ((self = [super init])) {
        _auditLog = auditLog;
        _emergencyStopped = NO;
        _scopeProvider = [[KMActiveCampaignScopeProvider alloc] initWithManager:self];
    }
    return self;
}

- (void)postScopeChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:KMActiveScopeChangedNotification
                                                        object:self];
}

#pragma mark currentCampaign

- (void)setCurrentCampaign:(KMCampaign *)currentCampaign {
    _currentCampaign = currentCampaign;
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    if (currentCampaign) {
        ctx[@"campaign"] = currentCampaign.label ?: @"";
        ctx[@"campaignId"] = currentCampaign.identifier ?: @"";
        ctx[@"scope"] = [currentCampaign.scope contextSummary] ?: @"";
        ctx[@"active"] = @([currentCampaign isActive]);
    }
    [self.auditLog appendAction:KMAuditActionScopeChanged
                         detail:currentCampaign ? @"Current campaign set."
                                                : @"Current campaign cleared."
                        context:ctx];
    [self postScopeChanged];
}

#pragma mark Lifecycle

- (void)armCampaign:(KMCampaign *)campaign {
    if (!campaign) return;
    // Arming clears any latched stop and authorizes the campaign.
    self.emergencyStopped = NO;
    campaign.emergencyStopped = NO;
    campaign.authorized = YES;

    _currentCampaign = campaign;   // set directly to control the audit message

    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    ctx[@"campaign"] = campaign.label ?: @"";
    ctx[@"campaignId"] = campaign.identifier ?: @"";
    if (campaign.authorizedBy) ctx[@"authorizedBy"] = campaign.authorizedBy;
    ctx[@"scope"] = [campaign.scope contextSummary] ?: @"";
    ctx[@"active"] = @([campaign isActive]);
    if (![campaign isActive]) ctx[@"inactiveReason"] = [campaign inactiveReason] ?: @"";

    [self.auditLog appendAction:KMAuditActionCampaignArmed
                         detail:[NSString stringWithFormat:@"Campaign armed: %@", campaign.label]
                        context:ctx];
    [self postScopeChanged];
}

- (void)disarmCurrentCampaign {
    KMCampaign *c = self.currentCampaign;
    if (c) c.authorized = NO;
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    if (c) { ctx[@"campaign"] = c.label ?: @""; ctx[@"campaignId"] = c.identifier ?: @""; }
    _currentCampaign = nil;
    [self.auditLog appendAction:KMAuditActionCampaignDisarmed
                         detail:@"Campaign disarmed; scope inactive."
                        context:ctx];
    [self postScopeChanged];
}

#pragma mark Emergency stop

- (void)engageEmergencyStop:(NSString *)reason {
    self.emergencyStopped = YES;
    KMCampaign *c = self.currentCampaign;
    if (c) c.emergencyStopped = YES;   // belt-and-suspenders: latch on the campaign too

    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    ctx[@"reason"] = reason ?: @"(none given)";
    if (c) {
        ctx[@"campaign"] = c.label ?: @"";
        ctx[@"campaignId"] = c.identifier ?: @"";
        ctx[@"scope"] = [c.scope contextSummary] ?: @"";
    } else {
        ctx[@"campaign"] = @"(none)";
    }
    [self.auditLog appendAction:KMAuditActionEmergencyStop
                         detail:@"EMERGENCY STOP engaged; all active/offensive features fail closed."
                        context:ctx];

    [[NSNotificationCenter defaultCenter] postNotificationName:KMEmergencyStopEngagedNotification
                                                        object:self];
    [self postScopeChanged];
}

- (void)clearEmergencyStop {
    self.emergencyStopped = NO;
    // NOTE: deliberately does NOT re-authorize the campaign. The latch on the
    // campaign is cleared so a subsequent -armCampaign: can reactivate it.
    if (self.currentCampaign) self.currentCampaign.emergencyStopped = NO;
    [self.auditLog appendAction:KMAuditActionEmergencyStop
                         detail:@"Emergency stop cleared; campaign remains disarmed until re-armed."
                        context:nil];
    [self postScopeChanged];
}

#pragma mark Active-operation auditing

- (BOOL)recordActiveOperation:(NSString *)operation target:(NSString *)target {
    BOOL inScope = [self.scopeProvider hasActiveScope];
    // If a specific target is named, require it to be in scope too (fail closed).
    if (inScope && target.length) {
        inScope = [self.scopeProvider scopeContainsBSSID:target] ||
                  [self.scopeProvider scopeContainsClientMAC:target] ||
                  [self.scopeProvider scopeContainsSSID:target];
    }
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    ctx[@"operation"] = operation ?: @"";
    if (target) ctx[@"target"] = target;
    ctx[@"inScope"] = @(inScope);
    KMCampaign *c = self.currentCampaign;
    if (c) { ctx[@"campaignId"] = c.identifier ?: @""; ctx[@"scope"] = [c.scope contextSummary] ?: @""; }
    [self.auditLog appendAction:KMAuditActionActiveOperation
                         detail:[NSString stringWithFormat:@"Active operation '%@' %@",
                                 operation ?: @"?", inScope ? @"permitted (in scope)" : @"REFUSED (out of scope / no scope)"]
                        context:ctx];
    return inScope;
}

@end
