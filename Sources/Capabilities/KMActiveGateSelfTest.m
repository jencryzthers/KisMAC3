/*
 File:        KMActiveGateSelfTest.m
 Program:     KisMac3
 Slice:       S4.2 - Gate inject/deauth/AP behind capability + scope

 This file is part of KisMAC. GPL v2.
 */

#import "KMActiveGateSelfTest.h"
#import "KMCapabilityEngine.h"
#import "KMCapability.h"
#import "KMHardwareCapability.h"
#import "../Safety/KMCampaignManager.h"
#import "../Safety/KMAuditLog.h"
#import "../Campaigns/KMCampaign.h"
#import "../Campaigns/KMCampaignScope.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

#pragma mark - Mock adapter-presence providers

/// MOCK: reports an injection-capable adapter IS present (no real USB needed).
@interface KMMockAdapterPresent : NSObject <KMAdapterPresenceProviding>
@end
@implementation KMMockAdapterPresent
- (BOOL)hasInjectionCapableAdapter { return YES; }
@end

/// MOCK: reports NO injection-capable adapter (the built-in MacBook reality).
@interface KMMockAdapterAbsent : NSObject <KMAdapterPresenceProviding>
@end
@implementation KMMockAdapterAbsent
- (BOOL)hasInjectionCapableAdapter { return NO; }
@end

@implementation KMActiveGateSelfTest

+ (NSArray<KMHardwareCapability *> *)mockAllGreenHardware {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusSupported reason:@"mock iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusSupported reason:@"mock granted"],
        [KMHardwareCapability capabilityWithKey:KMCapPcapOpen
            status:KMCapabilityStatusSupported reason:@"mock bpf ok"],
    ];
}

/// Scope covering BSSID 00:11:22:33:44:55 + client AA:BB:CC:DD:EE:FF, open window.
+ (KMCampaignScope *)inWindowScope {
    NSDate *now = [NSDate date];
    return [[KMCampaignScope alloc]
        initWithSSIDs:[NSSet setWithObject:@"LabNet"]
               bssids:[NSSet setWithObject:@"00:11:22:33:44:55"]
           clientMACs:[NSSet setWithObject:@"AA:BB:CC:DD:EE:FF"]
             adapters:[NSSet setWithObject:@"en0"]
             channels:[NSSet setWithObject:@6]
          windowStart:[now dateByAddingTimeInterval:-3600]
            windowEnd:[now dateByAddingTimeInterval:3600]];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];

    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) { DBNSLog(@"[KMActiveGateSelfTest]   PASS  %@", label); }
        else      { DBNSLog(@"[KMActiveGateSelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };

    // Assert a feature's (availability, reason) on a given engine.
    BOOL (^feat)(NSString *, KMCapabilityEngine *, NSString *,
                 KMCapabilityAvailability, KMCapabilityReason) =
    ^BOOL(NSString *label, KMCapabilityEngine *eng, NSString *key,
          KMCapabilityAvailability wantAvail, KMCapabilityReason wantReason) {
        KMCapability *c = [eng availabilityForCapability:key];
        BOOL ok = (c.availability == wantAvail) && (c.reason == wantReason);
        if (ok) {
            DBNSLog(@"[KMActiveGateSelfTest]   PASS  %@ (got %@/%@)", label,
                    KMStringFromCapabilityAvailability(c.availability),
                    KMStringFromCapabilityReason(c.reason));
        } else {
            DBNSLog(@"[KMActiveGateSelfTest]   FAIL  %@ -- got (%@/%@) want (%@/%@) -- %@",
                    label,
                    KMStringFromCapabilityAvailability(c.availability),
                    KMStringFromCapabilityReason(c.reason),
                    KMStringFromCapabilityAvailability(wantAvail),
                    KMStringFromCapabilityReason(wantReason), c.explanation);
            [fail addObject:label];
        }
        return ok;
    };

    DBNSLog(@"[KMActiveGateSelfTest] ===== S4.2 active/offensive gate matrix (mock adapter + real scope) =====");

    id<KMAdapterPresenceProviding> adapterYes = [[KMMockAdapterPresent alloc] init];
    id<KMAdapterPresenceProviding> adapterNo  = [[KMMockAdapterAbsent alloc] init];

    // Isolated audit log in a temp dir (never touch the real log).
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"kismac-activegate-selftest-%@",
                                     [[NSUUID UUID] UUIDString]] isDirectory:YES];
    KMAuditLog *audit = [[KMAuditLog alloc] initWithDirectory:tmp];
    KMCampaignManager *mgr = [[KMCampaignManager alloc] initWithAuditLog:audit];

    NSArray *trio = @[ KMFeatureFrameInjection, KMFeatureDeauth, KMFeatureAPMode ];

    // ---- 1) NO adapter, NO scope => unsupportedAdapter, NOT available ----
    KMCapabilityEngine *noAdapterNoScope = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider
                     parserRegistry:nil
                    adapterProvider:adapterNo];
    for (NSString *k in trio) {
        feat([@"1 no-adapter/no-scope " stringByAppendingString:k],
             noAdapterNoScope, k, KMCapabilityUnavailable, KMCapabilityReasonUnsupportedAdapter);
        check([@"1 no-adapter NOT available " stringByAppendingString:k],
              ![noAdapterNoScope isAvailable:k]);
    }

    // ---- 2) adapter present, NO scope => activeLabScopeMissing ----
    KMCapabilityEngine *adapterNoScope = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider
                     parserRegistry:nil
                    adapterProvider:adapterYes];
    for (NSString *k in trio) {
        feat([@"2 adapter/no-scope " stringByAppendingString:k],
             adapterNoScope, k, KMCapabilityUnavailable, KMCapabilityReasonActiveLabScopeMissing);
    }

    // ---- 3) adapter present, authorized in-window scope => available ----
    KMCampaign *camp = [[KMCampaign alloc] initWithLabel:@"S4.2 Lab"
                                                   scope:[self inWindowScope]];
    camp.authorizedBy = @"selftest";
    [mgr armCampaign:camp];
    check(@"3a armed in-window => hasActiveScope YES", mgr.scopeProvider.hasActiveScope == YES);
    KMCapabilityEngine *adapterScoped = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider
                     parserRegistry:nil
                    adapterProvider:adapterYes];
    for (NSString *k in trio) {
        feat([@"3 adapter/scope " stringByAppendingString:k],
             adapterScoped, k, KMCapabilityAvailable, KMCapabilityReasonNone);
    }

    // ---- 4) adapter + scope BUT target out of scope => op-guard refuses + audits
    // This mirrors the WaveScanner op-site guard's per-target membership check:
    //   in-scope BSSID/client  -> permitted
    //   out-of-scope BSSID/client -> REFUSED (scopeContains* returns NO)
    KMActiveCampaignScopeProvider *scope = mgr.scopeProvider;
    NSString *inBSSID   = @"00:11:22:33:44:55";
    NSString *outBSSID  = @"99:99:99:99:99:99";
    NSString *inClient  = @"AA:BB:CC:DD:EE:FF";
    NSString *outClient = @"11:22:33:44:55:66";

    check(@"4a in-scope BSSID is in scope",  [scope scopeContainsBSSID:inBSSID]);
    check(@"4b out-of-scope BSSID is NOT in scope (deauth/inject would refuse)",
          ![scope scopeContainsBSSID:outBSSID]);
    check(@"4c in-scope client is in scope",  [scope scopeContainsClientMAC:inClient]);
    check(@"4d out-of-scope client is NOT in scope (injection-test would refuse)",
          ![scope scopeContainsClientMAC:outClient]);

    // The op guard records an audit entry for the refusal. Use the manager's
    // recordActiveOperation: (same audit log) to prove the refusal is audited.
    BOOL permittedOut = [mgr recordActiveOperation:@"deauth-network" target:outBSSID];
    check(@"4e out-of-scope op refused (recordActiveOperation NO)", permittedOut == NO);
    BOOL permittedIn = [mgr recordActiveOperation:@"deauth-network" target:inBSSID];
    check(@"4f in-scope op permitted (recordActiveOperation YES)", permittedIn == YES);
    {
        NSArray<NSDictionary *> *entries = [audit readCurrentEntries];
        BOOL foundRefusal = NO, foundPermit = NO;
        for (NSDictionary *e in entries) {
            if (![e[@"action"] isEqual:KMAuditActionActiveOperation]) continue;
            id ctx = e[@"context"];
            NSString *detail = e[@"detail"];
            BOOL refused = ([detail rangeOfString:@"REFUSED"].location != NSNotFound) ||
                           ([ctx isKindOfClass:[NSDictionary class]] && [ctx[@"inScope"] isEqual:@NO]);
            BOOL permit  = ([detail rangeOfString:@"permitted"].location != NSNotFound) ||
                           ([ctx isKindOfClass:[NSDictionary class]] && [ctx[@"inScope"] isEqual:@YES]);
            if (refused) foundRefusal = YES;
            if (permit)  foundPermit = YES;
        }
        check(@"4g out-of-scope refusal is AUDITED", foundRefusal);
        check(@"4h in-scope permit is AUDITED", foundPermit);
    }

    // ---- 5) emergency stop => back to refused (no scope) ----
    [mgr engageEmergencyStop:@"selftest e-stop"];
    check(@"5a e-stop => hasActiveScope NO", mgr.scopeProvider.hasActiveScope == NO);
    // Rebuild the engine view (provider is the same object; scope now NO).
    for (NSString *k in trio) {
        feat([@"5 e-stop => " stringByAppendingString:k],
             adapterScoped, k, KMCapabilityUnavailable, KMCapabilityReasonActiveLabScopeMissing);
    }
    check(@"5b e-stop => in-scope BSSID no longer in scope (fails closed)",
          ![scope scopeContainsBSSID:inBSSID]);
    {
        NSArray<NSDictionary *> *entries = [audit readCurrentEntries];
        BOOL foundStop = NO;
        for (NSDictionary *e in entries) {
            if ([e[@"action"] isEqual:KMAuditActionEmergencyStop]) { foundStop = YES; break; }
        }
        check(@"5c emergency_stop audit entry recorded", foundStop);
    }

    // cleanup
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:NULL];

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMActiveGateSelfTest] PASS - S4.2 gate matrix held: adapter+scope 3-way, target-scope refusal+audit, e-stop fail-closed.");
    } else {
        DBNSLog(@"[KMActiveGateSelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMActiveGateSelfTest]   - %@", l);
    }
    return pass;
}

@end
