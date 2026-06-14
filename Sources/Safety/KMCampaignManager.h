/*
 File:        KMCampaignManager.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: The shared owner of the current authorized campaign (Milestone 9)
              and the home of the always-available EMERGENCY STOP.

              It also vends the REAL active-scope provider
              (KMActiveCampaignScopeProvider) that the capability engine's
              <KMActiveScopeProviding> contract consumes: -hasActiveScope is
              YES iff there is a current campaign and it -isActive (authorized
              AND in-window AND NOT emergency-stopped).

              EMERGENCY STOP (always available, even with no campaign): latches
              the current campaign to emergencyStopped=YES, which immediately
              makes -hasActiveScope return NO so EVERY active/offensive feature
              fails closed at once. The stop records an audit entry and posts
              KMEmergencyStopEngagedNotification so any bound UI (S5.x) and any
              running active op can halt. Re-arming is an explicit, separate act.

              FAIL CLOSED: no campaign => no scope. The provider never reports
              scope it cannot back with an active, authorized, in-window
              campaign.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "../Campaigns/KMCampaign.h"
#import "../Capabilities/KMCapabilityEngine.h"   // <KMActiveScopeProviding>

@class KMAuditLog;
@class KMCampaignManager;

NS_ASSUME_NONNULL_BEGIN

/// Posted when the active campaign / scope state changes (armed, disarmed,
/// window edge, emergency stop). Observers should re-query -hasActiveScope and
/// rebuild any capability gate. object = the KMCampaignManager.
extern NSString * const KMActiveScopeChangedNotification;
/// Posted specifically when the emergency stop is engaged. object = manager.
extern NSString * const KMEmergencyStopEngagedNotification;

#pragma mark - Real scope provider

/// The REAL <KMActiveScopeProviding> backed by the campaign manager. Inject
/// this into KMCapabilityEngine instead of KMNoActiveScopeProvider so active
/// features become available ONLY with an authorized, in-window campaign. Adds
/// scope-membership queries for callers that need to check a specific target.
@interface KMActiveCampaignScopeProvider : NSObject <KMActiveScopeProviding>
- (instancetype)initWithManager:(KMCampaignManager *)manager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// YES iff an authorized, in-window, non-stopped campaign is in effect.
- (BOOL)hasActiveScope;

/// Scope-membership queries -- all FAIL CLOSED when there is no active scope.
- (BOOL)scopeContainsBSSID:(nullable NSString *)bssid;
- (BOOL)scopeContainsClientMAC:(nullable NSString *)mac;
- (BOOL)scopeContainsSSID:(nullable NSString *)ssid;
- (BOOL)scopeContainsChannel:(NSInteger)channel;
- (BOOL)scopeContainsAdapter:(nullable NSString *)adapter;
@end

#pragma mark - Campaign manager

@interface KMCampaignManager : NSObject

/// Shared manager (uses KMAuditLog.sharedLog).
+ (instancetype)sharedManager;

/// Designated init for tests: inject an audit log.
- (instancetype)initWithAuditLog:(KMAuditLog *)auditLog NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// The audit log this manager records to.
@property (nonatomic, strong, readonly) KMAuditLog *auditLog;

/// The current campaign (nil => fail closed, no scope). Setting it records a
/// scope-changed audit entry and posts KMActiveScopeChangedNotification.
@property (nonatomic, strong, nullable) KMCampaign *currentCampaign;

/// Whether the emergency stop is currently engaged (latched). Cleared by
/// -armCampaign: or -clearEmergencyStop.
@property (nonatomic, assign, readonly, getter=isEmergencyStopped) BOOL emergencyStopped;

/// The real scope provider to inject into the capability engine.
@property (nonatomic, strong, readonly) KMActiveCampaignScopeProvider *scopeProvider;

#pragma mark Campaign lifecycle

/// Sets `campaign` as current, marks it authorized, clears any latched
/// emergency stop, and records a campaign-armed audit entry. The campaign only
/// becomes truly active if it is also within its time window.
- (void)armCampaign:(KMCampaign *)campaign;

/// Disarms (sets authorized=NO) and clears the current campaign; records an
/// audit entry. Scope becomes inactive.
- (void)disarmCurrentCampaign;

#pragma mark Emergency stop (ALWAYS available)

/// THE global emergency stop. Always callable, even with no campaign. Latches
/// emergencyStopped, forces the current campaign inactive, records an audit
/// entry, and posts both KMEmergencyStopEngagedNotification and
/// KMActiveScopeChangedNotification. After this, -hasActiveScope is NO until an
/// explicit re-arm.
- (void)engageEmergencyStop:(nullable NSString *)reason;

/// Clears the latched stop WITHOUT re-authorizing any campaign (the campaign
/// stays disarmed until -armCampaign:). Records an audit entry.
- (void)clearEmergencyStop;

#pragma mark Active-operation auditing

/// Convenience for active/offensive code paths to record that an active
/// operation was attempted/performed, with the target + current scope context.
/// Returns YES if the op is in scope AND there is active scope (callers should
/// refuse the op when this returns NO).
- (BOOL)recordActiveOperation:(NSString *)operation
                       target:(nullable NSString *)target;

@end

NS_ASSUME_NONNULL_END
