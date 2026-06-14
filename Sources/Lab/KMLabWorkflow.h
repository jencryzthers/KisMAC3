/*
 File:        KMLabWorkflow.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: The lab WORKFLOW ORCHESTRATION layer -- a THIN POLICY layer that
              exposes the active lab operations (deauth, injection,
              AP-simulation, captive-portal) as GATED REQUESTS. It builds no new
              transmit/radio/AP/portal code: it is the policy + evidence +
              orchestration LAYER on top of the existing S4.2 op-site gate.

 For EACH requested active operation it verifies, FAIL CLOSED, that:
   (a) the capability engine reports the feature AVAILABLE
       (=> an injection-capable adapter is present),
   (b) an authorized, in-window campaign scope is active,
   (c) the target is IN scope,
   (d) the emergency stop is NOT engaged,
 and AUDITS every attempt (allowed or refused) via KMAuditLog. Where a real
 implementation exists (deauth / injection from S4.2's WaveScanner paths) it
 reports the request PERMITTED so the caller may proceed through the existing
 gated WaveScanner entry point. For AP-SIMULATION and CAPTIVE-PORTAL there is NO
 implementation and this layer does NOT create one: they are represented as
 unavailable / unknownRequiresActiveProbe (hardware + future work), gated and
 fail-closed, with a clear reason.

 A simple per-operation RATE-LIMIT hook is included (token-bucket-ish minimum
 interval) so that even a permitted op cannot be hammered; exceeding it is a
 refusal and is audited.

 SAFETY (both reviewers): EVERYTHING fails closed. No turnkey offensive
 capability is introduced. Built-in MacBook hardware still cannot transmit
 (the adapter-presence provider reports NO for it). AP-sim / captive-portal are
 POLICY STUBS that REFUSE, never implementations. This file delegates execution
 to the EXISTING gated WaveScanner paths; it adds no transmit code.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMCapabilityEngine;
@class KMCampaignManager;
@class KMLabWorkflowDecision;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Scope-checking protocol

/// What the workflow + the AP profile need from a scope provider. The S4.1
/// KMActiveCampaignScopeProvider already implements ALL of these, so it is
/// passed in directly; tests can supply a mock.
@protocol KMLabScopeChecking <NSObject>
- (BOOL)hasActiveScope;
- (BOOL)scopeContainsBSSID:(nullable NSString *)bssid;
- (BOOL)scopeContainsClientMAC:(nullable NSString *)mac;
- (BOOL)scopeContainsSSID:(nullable NSString *)ssid;
@end

#pragma mark - The lab active operations

/// The active lab operations exposed as gated requests.
typedef NS_ENUM(NSInteger, KMLabOperation) {
    KMLabOperationDeauth = 0,        ///< targeted deauthentication (S4.2-backed)
    KMLabOperationInjection,         ///< frame (re)injection (S4.2-backed)
    KMLabOperationAPSimulation,      ///< AP-sim / evil-twin -- NO IMPL (policy stub)
    KMLabOperationCaptivePortal,     ///< captive-portal hosting -- NO IMPL (policy stub)
};

extern NSString *KMStringFromLabOperation(KMLabOperation op);

#pragma mark - Decision result

/// Why a lab op was refused (or that it was permitted). Stable strings so the
/// report + audit can render them.
typedef NS_ENUM(NSInteger, KMLabDecisionReason) {
    KMLabDecisionPermitted = 0,            ///< gate passed; caller may proceed via the gated WaveScanner path
    KMLabDecisionRefusedCapabilityUnavailable, ///< engine says feature unavailable (no adapter / no scope etc.)
    KMLabDecisionRefusedNoActiveScope,     ///< no authorized in-window campaign
    KMLabDecisionRefusedTargetOutOfScope,  ///< target not in campaign scope
    KMLabDecisionRefusedEmergencyStop,     ///< emergency stop engaged
    KMLabDecisionRefusedNoTarget,          ///< broadcast/no-target op cannot be scoped
    KMLabDecisionRefusedRateLimited,       ///< too soon since the last permitted op
    KMLabDecisionRefusedUnimplemented,     ///< AP-sim / captive-portal: no implementation (hardware + future work)
};

extern NSString *KMStringFromLabDecisionReason(KMLabDecisionReason reason);

@interface KMLabWorkflowDecision : NSObject
@property (nonatomic, assign, readonly) BOOL permitted;
@property (nonatomic, assign, readonly) KMLabOperation operation;
@property (nonatomic, assign, readonly) KMLabDecisionReason reason;
/// Human-readable explanation (safe to show; identifiers up to caller to redact).
@property (nonatomic, copy, readonly) NSString *explanation;
@end

#pragma mark - KMLabWorkflow

@interface KMLabWorkflow : NSObject

/// Designated init: inject the capability engine + the campaign manager (which
/// vends the scope provider + audit log). Tests inject mocks; production passes
/// the ScanController's engine and [KMCampaignManager sharedManager].
- (instancetype)initWithCapabilityEngine:(KMCapabilityEngine *)engine
                         campaignManager:(KMCampaignManager *)manager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Minimum seconds between two PERMITTED ops of the same type (rate-limit hook).
/// Default 0.25s. Set to 0 to disable in a test.
@property (nonatomic, assign) NSTimeInterval minimumIntervalBetweenOps;

#pragma mark Gated requests (each AUDITS; each fails closed)

/// Request a targeted deauthentication of an AP BSSID. Backed by the S4.2
/// WaveScanner path when permitted (this layer does NOT transmit). Fails closed
/// + audits if not (a)-(d). target=nil => RefusedNoTarget (broadcast can't be scoped).
- (KMLabWorkflowDecision *)requestDeauthForBSSID:(nullable NSString *)bssid;

/// Request a frame (re)injection toward an AP BSSID (S4.2-backed when permitted).
- (KMLabWorkflowDecision *)requestInjectionForBSSID:(nullable NSString *)bssid;

/// Request AP-simulation for an in-scope target. ALWAYS refused: no
/// implementation exists (hardware + future consented active-probe). Gated +
/// audited (so an authorized attempt is still recorded), fail-closed.
- (KMLabWorkflowDecision *)requestAPSimulationForBSSID:(nullable NSString *)bssid;

/// Request captive-portal hosting for an in-scope target. ALWAYS refused: no
/// implementation exists. Gated + audited, fail-closed.
- (KMLabWorkflowDecision *)requestCaptivePortalForSSID:(nullable NSString *)ssid;

/// Generic entry the above wrap. operation selects the op; target is a BSSID
/// (or, for captive-portal, an SSID); targetIsClient is unused at S7.1 (the
/// exposed ops target an AP) but kept for symmetry with the S4.2 gate.
- (KMLabWorkflowDecision *)requestOperation:(KMLabOperation)operation
                                     target:(nullable NSString *)target;

#pragma mark Self-test (S7.1 acceptance)

/// Runs the S7.1 lab self-test (event log from a management-frame fixture,
/// filters, AP-profile scope-binding, the workflow gate matrix incl.
/// out-of-scope + e-stop + no-adapter refusals, and the report lab section)
/// and logs PASS/FAIL actual-vs-expected via DBNSLog. Returns YES iff ALL pass.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
