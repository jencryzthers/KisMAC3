/*
 File:        KMLabWorkflow.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabWorkflow.h. THIN POLICY/ORCHESTRATION LAYER. Fail closed.
              NO new transmit/radio/AP/portal code. Delegates execution to the
              existing S4.2-gated WaveScanner paths (deauth/inject) where they
              exist; AP-sim / captive-portal are policy stubs that REFUSE.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabWorkflow.h"
#import "KMLabSelfTest.h"

#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Safety/KMCampaignManager.h"
#import "../Safety/KMAuditLog.h"

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

NSString *KMStringFromLabOperation(KMLabOperation op) {
    switch (op) {
        case KMLabOperationDeauth:        return @"lab-deauth";
        case KMLabOperationInjection:     return @"lab-injection";
        case KMLabOperationAPSimulation:  return @"lab-ap-simulation";
        case KMLabOperationCaptivePortal: return @"lab-captive-portal";
    }
    return @"lab-unknown";
}

NSString *KMStringFromLabDecisionReason(KMLabDecisionReason reason) {
    switch (reason) {
        case KMLabDecisionPermitted:                   return @"permitted";
        case KMLabDecisionRefusedCapabilityUnavailable:return @"capability-unavailable";
        case KMLabDecisionRefusedNoActiveScope:        return @"no-active-scope";
        case KMLabDecisionRefusedTargetOutOfScope:     return @"target-out-of-scope";
        case KMLabDecisionRefusedEmergencyStop:        return @"emergency-stop";
        case KMLabDecisionRefusedNoTarget:             return @"no-target";
        case KMLabDecisionRefusedRateLimited:          return @"rate-limited";
        case KMLabDecisionRefusedUnimplemented:        return @"unimplemented-hardware-required";
    }
    return @"unknown";
}

@implementation KMLabWorkflowDecision {
@public
    BOOL _permitted;
    KMLabOperation _operation;
    KMLabDecisionReason _reason;
    NSString *_explanation;
}
- (BOOL)permitted { return _permitted; }
- (KMLabOperation)operation { return _operation; }
- (KMLabDecisionReason)reason { return _reason; }
- (NSString *)explanation { return _explanation ?: @""; }
@end

@interface KMLabWorkflow ()
@property (nonatomic, strong) KMCapabilityEngine *engine;
@property (nonatomic, strong) KMCampaignManager *manager;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDate *> *lastPermittedByOp;
@end

@implementation KMLabWorkflow

- (instancetype)initWithCapabilityEngine:(KMCapabilityEngine *)engine
                         campaignManager:(KMCampaignManager *)manager {
    self = [super init];
    if (self) {
        _engine = engine;
        _manager = manager;
        _minimumIntervalBetweenOps = 0.25;
        _lastPermittedByOp = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark Decision construction + audit

static KMLabWorkflowDecision *makeDecision(KMLabOperation op, BOOL permitted,
                                           KMLabDecisionReason reason, NSString *explanation) {
    KMLabWorkflowDecision *d = [[KMLabWorkflowDecision alloc] init];
    d->_operation = op;
    d->_permitted = permitted;
    d->_reason = reason;
    d->_explanation = [explanation copy];
    return d;
}

- (void)auditDecision:(KMLabWorkflowDecision *)decision target:(NSString *)target {
    NSDictionary *ctx = @{
        @"operation": KMStringFromLabOperation(decision.operation),
        @"target": target ?: @"",
        @"allowed": @(decision.permitted),
        @"reason": KMStringFromLabDecisionReason(decision.reason),
        @"layer": @"KMLabWorkflow",
    };
    NSString *detail = [NSString stringWithFormat:@"%@ lab op '%@' target=%@ -- %@",
                        decision.permitted ? @"PERMITTED" : @"REFUSED",
                        KMStringFromLabOperation(decision.operation),
                        target ?: @"<none>",
                        KMStringFromLabDecisionReason(decision.reason)];
    [self.manager.auditLog appendAction:KMAuditActionActiveOperation detail:detail context:ctx];
    DBNSLog(@"[S7.1 KMLabWorkflow] %@", detail);
}

#pragma mark The gate

/// Maps a lab operation to the capability-engine feature key it requires.
static NSString *featureKeyForOperation(KMLabOperation op) {
    switch (op) {
        case KMLabOperationDeauth:        return KMFeatureDeauth;
        case KMLabOperationInjection:     return KMFeatureFrameInjection;
        case KMLabOperationAPSimulation:  return KMFeatureAPMode;
        case KMLabOperationCaptivePortal: return KMFeatureAPMode;  // closest gate (no own capability)
    }
    return KMFeatureFrameInjection;
}

static BOOL operationIsImplemented(KMLabOperation op) {
    // Only deauth + injection have an existing S4.2-gated WaveScanner execution
    // path. AP-sim + captive-portal have NO implementation and must NOT get one
    // here (hardware + future consented active-probe).
    return (op == KMLabOperationDeauth) || (op == KMLabOperationInjection);
}

- (KMLabWorkflowDecision *)requestOperation:(KMLabOperation)operation target:(NSString *)target {
    id<KMLabScopeChecking> scope = (id<KMLabScopeChecking>)self.manager.scopeProvider;
    NSString *opName = KMStringFromLabOperation(operation);

    // (d) EMERGENCY STOP first -- absolute, even before capability. Fail closed.
    if (self.manager.isEmergencyStopped) {
        KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedEmergencyStop,
            [NSString stringWithFormat:@"%@ refused: emergency stop is engaged.", opName]);
        [self auditDecision:d target:target];
        return d;
    }

    // (a) Capability engine must report the feature AVAILABLE (=> injection-
    //     capable adapter present AND authorized in-window scope). Fail closed.
    KMCapability *cap = [self.engine availabilityForCapability:featureKeyForOperation(operation)];
    if (!cap.isAvailable) {
        // Distinguish "no scope" from "no adapter / other" for a precise reason.
        KMLabDecisionReason reason = KMLabDecisionRefusedCapabilityUnavailable;
        if (cap.reason == KMCapabilityReasonActiveLabScopeMissing)
            reason = KMLabDecisionRefusedNoActiveScope;
        KMLabWorkflowDecision *d = makeDecision(operation, NO, reason,
            [NSString stringWithFormat:@"%@ refused: %@ (%@).", opName,
             cap.explanation ?: @"capability unavailable",
             KMStringFromCapabilityReason(cap.reason)]);
        [self auditDecision:d target:target];
        return d;
    }

    // (b) An authorized in-window scope must be active. (Redundant with the
    //     engine's availability above, but checked explicitly so the policy
    //     layer never relies on a single source.) Fail closed.
    if (![scope hasActiveScope]) {
        KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedNoActiveScope,
            [NSString stringWithFormat:@"%@ refused: no authorized in-window campaign scope.", opName]);
        [self auditDecision:d target:target];
        return d;
    }

    // (c) The target must be IN scope. A no-target (broadcast) request cannot be
    //     constrained to one scoped target => fail closed.
    if (target.length == 0) {
        KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedNoTarget,
            [NSString stringWithFormat:@"%@ refused: no in-scope target (broadcast cannot be scoped).", opName]);
        [self auditDecision:d target:target];
        return d;
    }
    BOOL targetInScope;
    if (operation == KMLabOperationCaptivePortal) {
        targetInScope = [scope scopeContainsSSID:target];   // portal keys on SSID
    } else {
        targetInScope = [scope scopeContainsBSSID:target];  // AP-targeted ops key on BSSID
    }
    if (!targetInScope) {
        KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedTargetOutOfScope,
            [NSString stringWithFormat:@"%@ refused: target %@ is outside the authorized campaign scope.",
             opName, target]);
        [self auditDecision:d target:target];
        return d;
    }

    // At this point (a)-(d) all hold and the target is in scope.

    // AP-SIMULATION + CAPTIVE-PORTAL: there is NO implementation. Even fully
    // authorized + in scope, the operation is REFUSED here because no transmit/
    // AP/portal code exists (and S7.1 must NOT add one). The attempt IS audited.
    if (!operationIsImplemented(operation)) {
        KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedUnimplemented,
            [NSString stringWithFormat:@"%@ is authorized + in scope but UNIMPLEMENTED: "
             @"no AP/portal transmit capability exists on this build (requires external "
             @"hardware + a future consented active-probe). Refused, fail-closed.", opName]);
        [self auditDecision:d target:target];
        return d;
    }

    // (rate-limit) Even a permitted, implemented op is throttled.
    if (self.minimumIntervalBetweenOps > 0) {
        NSDate *last = self.lastPermittedByOp[@(operation)];
        if (last && [[NSDate date] timeIntervalSinceDate:last] < self.minimumIntervalBetweenOps) {
            KMLabWorkflowDecision *d = makeDecision(operation, NO, KMLabDecisionRefusedRateLimited,
                [NSString stringWithFormat:@"%@ refused: rate-limited (min %.2fs between ops).",
                 opName, self.minimumIntervalBetweenOps]);
            [self auditDecision:d target:target];
            return d;
        }
    }

    // PERMITTED. NOTE: this layer does NOT transmit. The caller proceeds through
    // the EXISTING S4.2-gated WaveScanner path (-deauthenticateNetwork: /
    // -tryToInject:), which re-checks the same gate at the op site (defense in
    // depth). Record the permit + the rate-limit timestamp.
    self.lastPermittedByOp[@(operation)] = [NSDate date];
    KMLabWorkflowDecision *d = makeDecision(operation, YES, KMLabDecisionPermitted,
        [NSString stringWithFormat:@"%@ permitted (adapter + in-scope target + authorized window). "
         @"Execution delegates to the gated WaveScanner path.", opName]);
    [self auditDecision:d target:target];
    return d;
}

#pragma mark Convenience wrappers

- (KMLabWorkflowDecision *)requestDeauthForBSSID:(NSString *)bssid {
    return [self requestOperation:KMLabOperationDeauth target:bssid];
}
- (KMLabWorkflowDecision *)requestInjectionForBSSID:(NSString *)bssid {
    return [self requestOperation:KMLabOperationInjection target:bssid];
}
- (KMLabWorkflowDecision *)requestAPSimulationForBSSID:(NSString *)bssid {
    return [self requestOperation:KMLabOperationAPSimulation target:bssid];
}
- (KMLabWorkflowDecision *)requestCaptivePortalForSSID:(NSString *)ssid {
    return [self requestOperation:KMLabOperationCaptivePortal target:ssid];
}

#pragma mark Self-test

+ (BOOL)runSelfTestLogging {
    return [KMLabSelfTest runSelfTestLogging];
}

@end
