/*
 File:        KMSafetySelfTest.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMSafetySelfTest.h"
#import "KMCampaignManager.h"
#import "KMAuditLog.h"
#import "KMRedactionSettings.h"
#import "../Campaigns/KMCampaign.h"
#import "../Campaigns/KMCampaignScope.h"
#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Capabilities/KMHardwareCapability.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

/// MOCK adapter-presence provider that reports an injection-capable adapter, so
/// this S4.1 test can exercise the SCOPE gate flip (with no adapter the S4.2
/// engine would report unsupportedAdapter and mask the scope transition).
@interface KMSafetyTestAdapterProvider : NSObject <KMAdapterPresenceProviding>
@end
@implementation KMSafetyTestAdapterProvider
- (BOOL)hasInjectionCapableAdapter { return YES; }
@end

@implementation KMSafetySelfTest

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

/// A scope covering one BSSID, an open window [now-1h, now+1h].
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

/// A scope whose window already closed (ended an hour ago).
+ (KMCampaignScope *)expiredScope {
    NSDate *now = [NSDate date];
    return [[KMCampaignScope alloc]
        initWithSSIDs:nil bssids:[NSSet setWithObject:@"00:11:22:33:44:55"]
           clientMACs:nil adapters:nil channels:nil
          windowStart:[now dateByAddingTimeInterval:-7200]
            windowEnd:[now dateByAddingTimeInterval:-3600]];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];

    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) {
            DBNSLog(@"[KMSafetySelfTest]   PASS  %@", label);
        } else {
            DBNSLog(@"[KMSafetySelfTest]   FAIL  %@", label);
            [fail addObject:label];
        }
        return cond;
    };

    // Helper to assert an active feature's reason on a given engine.
    BOOL (^featReason)(NSString *, KMCapabilityEngine *, NSString *,
                       KMCapabilityReason) =
    ^BOOL(NSString *label, KMCapabilityEngine *eng, NSString *featureKey,
          KMCapabilityReason wantReason) {
        KMCapability *c = [eng availabilityForCapability:featureKey];
        BOOL ok = (c.reason == wantReason);
        if (!ok) {
            DBNSLog(@"[KMSafetySelfTest]   FAIL  %@ -- got reason %@, want %@ (%@)",
                    label, KMStringFromCapabilityReason(c.reason),
                    KMStringFromCapabilityReason(wantReason), c.explanation);
            [fail addObject:label];
        } else {
            DBNSLog(@"[KMSafetySelfTest]   PASS  %@ (reason %@)",
                    label, KMStringFromCapabilityReason(c.reason));
        }
        return ok;
    };

    // ---- isolated audit log in a temp dir (never touch the real log) ----
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"kismac-safety-selftest-%@",
                                     [[NSUUID UUID] UUIDString]] isDirectory:YES];
    KMAuditLog *audit = [[KMAuditLog alloc] initWithDirectory:tmp];
    KMCampaignManager *mgr = [[KMCampaignManager alloc] initWithAuditLog:audit];

    // Build a REAL engine over MOCKED all-green hardware + the REAL provider.
    // S4.2: the engine designated init now also takes an adapter-presence
    // provider. To exercise the SCOPE gate flip (this test's purpose) we inject
    // a MOCK provider that reports an injection-capable adapter present, so the
    // offensive trio's reason depends solely on scope (activeLabScopeMissing
    // when no scope, available when an authorized in-window campaign is armed).
    KMCapabilityEngine *engine = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider
                     parserRegistry:nil
                    adapterProvider:[[KMSafetyTestAdapterProvider alloc] init]];

    DBNSLog(@"[KMSafetySelfTest] ===== S4.1 safety self-test (real provider + real engine) =====");

    // ---- 1) No campaign => fail closed ----
    check(@"1a no campaign => hasActiveScope NO", mgr.scopeProvider.hasActiveScope == NO);
    featReason(@"1b no campaign => frameInjection activeLabScopeMissing",
               engine, KMFeatureFrameInjection, KMCapabilityReasonActiveLabScopeMissing);
    featReason(@"1c no campaign => deauth activeLabScopeMissing",
               engine, KMFeatureDeauth, KMCapabilityReasonActiveLabScopeMissing);
    featReason(@"1d no campaign => apMode activeLabScopeMissing",
               engine, KMFeatureAPMode, KMCapabilityReasonActiveLabScopeMissing);
    check(@"1e no campaign => frameInjection NOT available",
          ![engine isAvailable:KMFeatureFrameInjection]);

    // ---- 2) Authorized in-window campaign => scope ON, gate flips off ----
    KMCampaign *camp = [[KMCampaign alloc] initWithLabel:@"SelfTest Lab"
                                                   scope:[self inWindowScope]];
    camp.authorizedBy = @"selftest";
    [mgr armCampaign:camp];
    check(@"2a in-window armed => hasActiveScope YES", mgr.scopeProvider.hasActiveScope == YES);
    // S4.2: with a (mock) injection-capable adapter present AND an authorized
    // in-window scope, the offensive trio is AVAILABLE (reason None). The op
    // site still enforces per-target scope + audit (see KMActiveGateSelfTest).
    featReason(@"2b armed + adapter => frameInjection available",
               engine, KMFeatureFrameInjection, KMCapabilityReasonNone);
    featReason(@"2c armed + adapter => deauth available",
               engine, KMFeatureDeauth, KMCapabilityReasonNone);
    featReason(@"2d armed + adapter => apMode available",
               engine, KMFeatureAPMode, KMCapabilityReasonNone);
    // Scope-membership queries.
    check(@"2e scope contains BSSID 00:11:22:33:44:55",
          [mgr.scopeProvider scopeContainsBSSID:@"00-11-22-33-44-55"]);   // normalized
    check(@"2f scope does NOT contain unlisted BSSID",
          ![mgr.scopeProvider scopeContainsBSSID:@"99:99:99:99:99:99"]);
    check(@"2g scope contains channel 6", [mgr.scopeProvider scopeContainsChannel:6]);
    check(@"2h scope does NOT contain channel 11", ![mgr.scopeProvider scopeContainsChannel:11]);

    // ---- 3) Emergency stop => fail closed again + audit entry ----
    [mgr engageEmergencyStop:@"selftest e-stop"];
    check(@"3a e-stop => hasActiveScope NO", mgr.scopeProvider.hasActiveScope == NO);
    featReason(@"3b e-stop => frameInjection activeLabScopeMissing again",
               engine, KMFeatureFrameInjection, KMCapabilityReasonActiveLabScopeMissing);
    {
        NSArray<NSDictionary *> *entries = [audit readCurrentEntries];
        BOOL foundStop = NO;
        for (NSDictionary *e in entries) {
            if ([e[@"action"] isEqual:KMAuditActionEmergencyStop]) { foundStop = YES; break; }
        }
        check(@"3c emergency_stop audit entry recorded", foundStop);
    }

    // ---- 4) Expired window => not active ----
    KMCampaign *expired = [[KMCampaign alloc] initWithLabel:@"Expired"
                                                      scope:[self expiredScope]];
    [mgr armCampaign:expired];   // arming authorizes + clears e-stop...
    check(@"4a expired-window armed => campaign NOT active", ![expired isActive]);
    check(@"4b expired-window => hasActiveScope NO", mgr.scopeProvider.hasActiveScope == NO);
    featReason(@"4c expired-window => frameInjection activeLabScopeMissing",
               engine, KMFeatureFrameInjection, KMCapabilityReasonActiveLabScopeMissing);

    // ---- 5) Audit log appended + readable ----
    {
        NSArray<NSDictionary *> *entries = [audit readCurrentEntries];
        check(@"5a audit entries exist and are readable", entries.count > 0);
        BOOL wellFormed = YES;
        for (NSDictionary *e in entries) {
            if (![e[@"ts"] isKindOfClass:[NSString class]] ||
                ![e[@"action"] isKindOfClass:[NSString class]]) { wellFormed = NO; break; }
        }
        check(@"5b every audit entry has ts + action", wellFormed);
        DBNSLog(@"[KMSafetySelfTest]   (audit file: %@, %lu entries)",
                audit.currentLogFileURL.path, (unsigned long)entries.count);
    }

    // ---- 6) Redaction on/off ----
    {
        KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
        NSString *mac = @"00:11:22:33:44:55";
        NSString *ssid = @"HomeNetwork";
        NSString *host = @"printer.local";
        NSString *bt = @"12345678-90ab-cdef-1234-567890abcdef";

        // OFF (default): untouched.
        check(@"6a redaction OFF => MAC untouched",  [[r redactMAC:mac] isEqualToString:mac]);
        check(@"6b redaction OFF => SSID untouched", [[r redactSSID:ssid] isEqualToString:ssid]);
        check(@"6c redaction OFF => hostname untouched", [[r redactHostname:host] isEqualToString:host]);

        // ON: transformed (and the device portion / labels masked).
        r.enabled = YES;
        NSString *rMac = [r redactMAC:mac];
        check(@"6d redaction ON => MAC changed", ![rMac isEqualToString:mac]);
        check(@"6e redaction ON => MAC keeps OUI", [rMac hasPrefix:@"00:11:22"]);
        check(@"6f redaction ON => MAC masks device part", [rMac containsString:@"**"]);
        NSString *rSsid = [r redactSSID:ssid];
        check(@"6g redaction ON => SSID changed", ![rSsid isEqualToString:ssid]);
        check(@"6h redaction ON => SSID keeps ends", [rSsid hasPrefix:@"H"] && [rSsid hasSuffix:@"k"]);
        NSString *rHost = [r redactHostname:host];
        check(@"6i redaction ON => hostname changed", ![rHost isEqualToString:host]);
        check(@"6j redaction ON => hostname keeps TLD", [rHost hasSuffix:@".local"]);
        check(@"6k redaction ON => bluetooth id changed", ![[r redactBluetoothIdentifier:bt] isEqualToString:bt]);
        // free-text MAC masking
        NSString *line = @"client 00:11:22:33:44:55 deauthed";
        NSString *rLine = [r redactString:line];
        check(@"6l redaction ON => free-text MAC masked", ![rLine isEqualToString:line] && [rLine containsString:@"00:11:22"]);

        // per-type independence: turning MAC off leaves it verbatim while ON.
        r.redactMACAddresses = NO;
        check(@"6m per-type MAC off => MAC untouched even with master ON",
              [[r redactMAC:mac] isEqualToString:mac]);
    }

    // ---- cleanup temp dir ----
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:NULL];

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMSafetySelfTest] PASS - all S4.1 safety assertions held (fail-closed, e-stop, audit, redaction).");
    } else {
        DBNSLog(@"[KMSafetySelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMSafetySelfTest]   - %@", l);
    }
    return pass;
}

@end
