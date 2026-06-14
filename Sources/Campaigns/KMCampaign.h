/*
 File:        KMCampaign.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: An authorized-lab CAMPAIGN (Milestone 9). A campaign bundles a
              human label, an EXPLICIT authorization flag, an authorization
              attribution string (who authorized it / ticket), a scope
              (KMCampaignScope), and an emergency-stop flag.

              A campaign is "ACTIVE" (i.e. permits active/offensive operations)
              ONLY when ALL of:
                1. it is explicitly authorized            (authorized == YES)
                2. it is NOT emergency-stopped            (emergencyStopped==NO)
                3. the current time is within its scope's time window

              This is the fail-closed contract S4.1 provides; the capability
              engine's KMActiveScopeProviding asks exactly -isActive.

              MUTABILITY: the authorization + emergency-stop flags and scope are
              settable so a manager/UI can build and arm a campaign, but the
              -isActive computation is the single source of truth and cannot be
              spoofed independently of those inputs.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMCampaignScope.h"

NS_ASSUME_NONNULL_BEGIN

@interface KMCampaign : NSObject <NSSecureCoding>

/// Stable identifier (UUID string).
@property (nonatomic, copy, readonly) NSString *identifier;
/// Human-readable campaign label.
@property (nonatomic, copy) NSString *label;

/// EXPLICIT authorization. Defaults to NO. Must be set YES deliberately.
@property (nonatomic, assign, getter=isAuthorized) BOOL authorized;
/// Free-form attribution for the authorization (operator, ticket, customer).
/// Recorded in the audit log when the campaign is armed.
@property (nonatomic, copy, nullable) NSString *authorizedBy;

/// The authorized scope (targets + time window).
@property (nonatomic, copy) KMCampaignScope *scope;

/// Emergency-stop latch. When YES the campaign is forced inactive regardless
/// of authorization/window. Set by the global emergency stop; cleared only by
/// an explicit re-arm. Defaults to NO.
@property (nonatomic, assign, getter=isEmergencyStopped) BOOL emergencyStopped;

/// When the campaign was created.
@property (nonatomic, copy, readonly) NSDate *createdAt;

- (instancetype)initWithLabel:(NSString *)label
                        scope:(KMCampaignScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark The fail-closed contract

/// THE single source of truth: YES iff authorized AND not emergency-stopped
/// AND within the scope's time window right now.
- (BOOL)isActive;

/// As -isActive but evaluated at an explicit date (testability).
- (BOOL)isActiveAtDate:(NSDate *)date;

/// Human-readable reason the campaign is NOT active (nil if it IS active).
- (nullable NSString *)inactiveReason;

@end

NS_ASSUME_NONNULL_END
