/*
 File:        KMLabSelfTest.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabSelfTest.h. PASSIVE / OFFLINE / LOCAL-ONLY.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabSelfTest.h"

#import "KMLabEvent.h"
#import "KMLabEventLog.h"
#import "KMLabFilter.h"
#import "KMLabAPProfile.h"
#import "KMLabAPProfileStore.h"
#import "KMLabWorkflow.h"

#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Capabilities/KMHardwareCapability.h"
#import "../Safety/KMCampaignManager.h"
#import "../Safety/KMAuditLog.h"
#import "../Safety/KMRedactionSettings.h"
#import "../Campaigns/KMCampaign.h"
#import "../Campaigns/KMCampaignScope.h"
#import "../Reporting/KMReport.h"

#import "WaveScanner.h"
#import "WaveContainer.h"

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

#pragma mark - Mock adapter-presence providers (mirror KMActiveGateSelfTest)

@interface KMLabMockAdapterPresent : NSObject <KMAdapterPresenceProviding>
@end
@implementation KMLabMockAdapterPresent
- (BOOL)hasInjectionCapableAdapter { return YES; }
@end

@interface KMLabMockAdapterAbsent : NSObject <KMAdapterPresenceProviding>
@end
@implementation KMLabMockAdapterAbsent
- (BOOL)hasInjectionCapableAdapter { return NO; }
@end

@implementation KMLabSelfTest

// Fixture identities (match make_pcap_fixture.py / lab_mgmt.pcap).
static NSString * const kLabBSSID  = @"00:11:22:33:44:55";
static NSString * const kLabClient = @"AA:BB:CC:DD:EE:FF";
static NSString * const kLabSSID   = @"KISMAC-LAB-NET";

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

+ (KMCampaignScope *)inWindowScope {
    NSDate *now = [NSDate date];
    return [[KMCampaignScope alloc]
        initWithSSIDs:[NSSet setWithObject:kLabSSID]
               bssids:[NSSet setWithObject:kLabBSSID]
           clientMACs:[NSSet setWithObject:kLabClient]
             adapters:[NSSet setWithObject:@"en0"]
             channels:[NSSet setWithObject:@6]
          windowStart:[now dateByAddingTimeInterval:-3600]
            windowEnd:[now dateByAddingTimeInterval:3600]];
}

+ (NSString *)labFixturePath {
    NSString *env = [[NSProcessInfo processInfo] environment][@"KISMAC_LAB_SELFTEST"];
    if (env.length > 0 && ![env isEqualToString:@"1"]) return [env stringByExpandingTildeInPath];
    return [[NSBundle mainBundle] pathForResource:@"lab_mgmt" ofType:@"pcap"];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];
    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) DBNSLog(@"[KMLabSelfTest]   PASS  %@", label);
        else { DBNSLog(@"[KMLabSelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };

    DBNSLog(@"[KMLabSelfTest] ===== S7.1 authorized-lab workflow core =====");

    // ===================================================================
    // 1) EVENT LOG from the imported management-frame fixture.
    // ===================================================================
    NSString *path = [self labFixturePath];
    if (!check(@"1 lab_mgmt.pcap fixture resolved", path && [[NSFileManager defaultManager] fileExistsAtPath:path])) {
        DBNSLog(@"[KMLabSelfTest] FAIL early: no fixture; aborting.");
        return NO;
    }

    KMLabEventLog *log = [KMLabEventLog sharedLog];
    [log reset];

    WaveContainer *container = [[WaveContainer alloc] init];
    [container clearAllEntries];
    WaveScanner *scanner = [[WaveScanner alloc] init];
    [scanner setValue:container forKey:@"_container"];
    [scanner readPCAPDump:path];   // OFFLINE; the import hook feeds the event log

    check(@"1a probe-request recorded (count 1)",   [log countOfType:KMLabEventTypeProbeRequest] == 1);
    check(@"1b association-request recorded (count 1)", [log countOfType:KMLabEventTypeAssociationRequest] == 1);
    check(@"1c deauthentication recorded (count 1)", [log countOfType:KMLabEventTypeDeauthentication] == 1);
    check(@"1d EAPOL handshake recorded (count 1)", [log countOfType:KMLabEventTypeEAPOLHandshake] == 1);
    check(@"1e handshakeCount == 1", [log handshakeCount] == 1);
    check(@"1f total events == 4", [log count] == 4);

    // Redaction hides identifiers when ON; shows them when OFF.
    KMRedactionSettings *redOn = [KMRedactionSettings defaultSettings]; redOn.enabled = YES;
    KMRedactionSettings *redOff = [KMRedactionSettings defaultSettings]; redOff.enabled = NO;
    NSString *summaryOn  = [log redactedSummaryWithSettings:redOn];
    NSString *summaryOff = [log redactedSummaryWithSettings:redOff];
    check(@"1g redaction OFF shows raw BSSID",
          [summaryOff rangeOfString:kLabBSSID].location != NSNotFound);
    check(@"1h redaction ON hides raw BSSID",
          [summaryOn rangeOfString:kLabBSSID].location == NSNotFound);
    check(@"1i redaction ON hides raw client MAC",
          [summaryOn rangeOfString:kLabClient].location == NSNotFound);

    // ===================================================================
    // 2) ALLOW/DENY FILTERS (client + SSID).
    // ===================================================================
    KMLabFilter *empty = [KMLabFilter emptyFilter];
    check(@"2a empty filter allows any client", [empty allowsClientMAC:kLabClient]);
    check(@"2b empty filter allows any SSID",   [empty allowsSSID:kLabSSID]);

    KMLabFilter *allowClient = [KMLabFilter emptyFilter];
    allowClient.allowClientMACs = [NSSet setWithObject:kLabClient];
    check(@"2c allow-list passes listed client", [allowClient allowsClientMAC:kLabClient]);
    check(@"2d allow-list rejects unlisted client (separator-insensitive)",
          ![allowClient allowsClientMAC:@"11-22-33-44-55-66"]);
    check(@"2e allow-list matches normalized form", [allowClient allowsClientMAC:@"aabbccddeeff"]);

    KMLabFilter *denyClient = [KMLabFilter emptyFilter];
    denyClient.denyClientMACs = [NSSet setWithObject:kLabClient];
    check(@"2f deny-list blocks listed client",  ![denyClient allowsClientMAC:kLabClient]);
    check(@"2g deny-list allows other client",   [denyClient allowsClientMAC:@"11:22:33:44:55:66"]);

    KMLabFilter *ssidF = [KMLabFilter emptyFilter];
    ssidF.allowSSIDs = [NSSet setWithObject:kLabSSID];
    ssidF.denySSIDs  = [NSSet setWithObject:@"OTHER-NET"];
    check(@"2h allow SSID passes",  [ssidF allowsSSID:kLabSSID]);
    check(@"2i unlisted SSID blocked (allow-list active)", ![ssidF allowsSSID:@"SOME-NET"]);
    check(@"2j deny overrides", ![ssidF allowsSSID:@"OTHER-NET"]);

    // ===================================================================
    // Build the campaign machinery (throwaway audit dir + manager).
    // ===================================================================
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"kismac-lab-selftest-%@",
                                     [[NSUUID UUID] UUIDString]] isDirectory:YES];
    KMAuditLog *audit = [[KMAuditLog alloc] initWithDirectory:tmp];
    KMCampaignManager *mgr = [[KMCampaignManager alloc] initWithAuditLog:audit];

    id<KMAdapterPresenceProviding> adapterYes = [[KMLabMockAdapterPresent alloc] init];
    id<KMAdapterPresenceProviding> adapterNo  = [[KMLabMockAdapterAbsent alloc] init];

    // ===================================================================
    // 3) AP PROFILE: usable only when in scope.
    // ===================================================================
    KMLabAPProfile *profileInScope = [[KMLabAPProfile alloc]
        initWithLabel:@"Owned lab AP" ssid:kLabSSID bssid:kLabBSSID
              channel:6 security:KMLabAPSecurityWPA2Personal];
    KMLabAPProfile *profileOutScope = [[KMLabAPProfile alloc]
        initWithLabel:@"Foreign AP" ssid:@"NOT-MINE" bssid:@"99:99:99:99:99:99"
              channel:1 security:KMLabAPSecurityOpen];

    id<KMLabScopeChecking> scope = (id<KMLabScopeChecking>)mgr.scopeProvider;
    check(@"3a no campaign => in-scope profile NOT usable (fail closed)",
          ![profileInScope isUsableWithScopeProvider:scope]);

    // Persisted store round-trip (throwaway file).
    NSURL *storeURL = [tmp URLByAppendingPathComponent:@"lab-ap-profiles.plist"];
    KMLabAPProfileStore *store = [[KMLabAPProfileStore alloc] initWithFileURL:storeURL];
    [store removeAllProfiles];
    [store addProfile:profileInScope];
    KMLabAPProfileStore *reloaded = [[KMLabAPProfileStore alloc] initWithFileURL:storeURL];
    check(@"3b AP profile persists + reloads", reloaded.profiles.count == 1 &&
          [reloaded.profiles.firstObject.bssid isEqualToString:kLabBSSID]);

    // ===================================================================
    // 4) WORKFLOW GATE — NO adapter / NO scope => EVERY op refused + audited.
    // ===================================================================
    KMCapabilityEngine *engNoAdapterNoScope = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider parserRegistry:nil
                     adapterProvider:adapterNo];
    KMLabWorkflow *wfNone = [[KMLabWorkflow alloc]
        initWithCapabilityEngine:engNoAdapterNoScope campaignManager:mgr];
    wfNone.minimumIntervalBetweenOps = 0;

    check(@"4a no-adapter deauth refused",  ![wfNone requestDeauthForBSSID:kLabBSSID].permitted);
    check(@"4b no-adapter inject refused",  ![wfNone requestInjectionForBSSID:kLabBSSID].permitted);
    check(@"4c no-adapter ap-sim refused",  ![wfNone requestAPSimulationForBSSID:kLabBSSID].permitted);
    check(@"4d no-adapter captive-portal refused", ![wfNone requestCaptivePortalForSSID:kLabSSID].permitted);

    // ===================================================================
    // 5) WORKFLOW GATE — MOCK adapter + authorized in-window scope.
    // ===================================================================
    KMCampaign *camp = [[KMCampaign alloc] initWithLabel:@"S7.1 Lab" scope:[self inWindowScope]];
    camp.authorizedBy = @"selftest";
    [mgr armCampaign:camp];
    check(@"5a armed in-window => hasActiveScope", mgr.scopeProvider.hasActiveScope);
    check(@"5b in-scope AP profile now usable", [profileInScope isUsableWithScopeProvider:scope]);
    check(@"5c out-of-scope AP profile NOT usable", ![profileOutScope isUsableWithScopeProvider:scope]);

    KMCapabilityEngine *engAdapterScoped = [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockAllGreenHardware]
                       scopeProvider:mgr.scopeProvider parserRegistry:nil
                     adapterProvider:adapterYes];
    KMLabWorkflow *wf = [[KMLabWorkflow alloc]
        initWithCapabilityEngine:engAdapterScoped campaignManager:mgr];
    wf.minimumIntervalBetweenOps = 0;

    // deauth/inject for an IN-SCOPE target => permitted + audited.
    KMLabWorkflowDecision *dDeauth = [wf requestDeauthForBSSID:kLabBSSID];
    check(@"5d in-scope deauth PERMITTED", dDeauth.permitted &&
          dDeauth.reason == KMLabDecisionPermitted);
    KMLabWorkflowDecision *dInject = [wf requestInjectionForBSSID:kLabBSSID];
    check(@"5e in-scope inject PERMITTED", dInject.permitted);

    // OUT-OF-SCOPE target => refused.
    KMLabWorkflowDecision *dOut = [wf requestDeauthForBSSID:@"99:99:99:99:99:99"];
    check(@"5f out-of-scope deauth REFUSED (target-out-of-scope)",
          !dOut.permitted && dOut.reason == KMLabDecisionRefusedTargetOutOfScope);

    // AP-sim + captive-portal: in scope + authorized but UNIMPLEMENTED => refused.
    KMLabWorkflowDecision *dAP = [wf requestAPSimulationForBSSID:kLabBSSID];
    check(@"5g in-scope ap-sim REFUSED (unimplemented)",
          !dAP.permitted && dAP.reason == KMLabDecisionRefusedUnimplemented);
    KMLabWorkflowDecision *dCP = [wf requestCaptivePortalForSSID:kLabSSID];
    check(@"5h in-scope captive-portal REFUSED (unimplemented)",
          !dCP.permitted && dCP.reason == KMLabDecisionRefusedUnimplemented);

    // ===================================================================
    // 6) EMERGENCY STOP => everything refused again.
    // ===================================================================
    [mgr engageEmergencyStop:@"selftest e-stop"];
    check(@"6a e-stop => hasActiveScope NO", !mgr.scopeProvider.hasActiveScope);
    KMLabWorkflowDecision *eDeauth = [wf requestDeauthForBSSID:kLabBSSID];
    check(@"6b e-stop => deauth refused (emergency-stop)",
          !eDeauth.permitted && eDeauth.reason == KMLabDecisionRefusedEmergencyStop);
    check(@"6c e-stop => inject refused", ![wf requestInjectionForBSSID:kLabBSSID].permitted);
    check(@"6d e-stop => ap-sim refused", ![wf requestAPSimulationForBSSID:kLabBSSID].permitted);
    check(@"6e e-stop => in-scope profile no longer usable", ![profileInScope isUsableWithScopeProvider:scope]);

    // The attempts above were audited (permits + refusals present in the log).
    {
        NSArray<NSDictionary *> *entries = [audit readCurrentEntries];
        BOOL foundPermit = NO, foundRefuse = NO, foundEStop = NO;
        for (NSDictionary *e in entries) {
            if ([e[@"action"] isEqual:KMAuditActionEmergencyStop]) foundEStop = YES;
            if (![e[@"action"] isEqual:KMAuditActionActiveOperation]) continue;
            id ctx = e[@"context"];
            if (![ctx isKindOfClass:[NSDictionary class]]) continue;
            if ([ctx[@"allowed"] boolValue]) foundPermit = YES; else foundRefuse = YES;
        }
        check(@"6f a PERMITTED lab op was audited", foundPermit);
        check(@"6g a REFUSED lab op was audited",  foundRefuse);
        check(@"6h emergency_stop was audited",     foundEStop);
    }

    // ===================================================================
    // 7) CAMPAIGN REPORT — lab section + limitations + redaction.
    // ===================================================================
    // Re-arm so the report shows an active scope summary (clears the e-stop).
    [mgr armCampaign:[[KMCampaign alloc] initWithLabel:@"S7.1 Lab" scope:[self inWindowScope]]];

    KMReport *report = [[KMReport alloc] init];
    report.container = container;
    report.labEventLog = log;
    report.labAPProfiles = @[ profileInScope, profileOutScope ];
    report.labScopeProvider = scope;
    report.campaignManager = mgr;

    report.redaction = redOff;
    NSString *mdOff = [report generateMarkdown];
    check(@"7a report has lab section",   [mdOff rangeOfString:@"## Authorized lab"].location != NSNotFound);
    check(@"7b report has event log",     [mdOff rangeOfString:@"### Event log"].location != NSNotFound);
    check(@"7c report has handshakes",    [mdOff rangeOfString:@"handshakes observed"].location != NSNotFound);
    check(@"7d report has limitations",   [mdOff rangeOfString:@"### Limitations"].location != NSNotFound);
    check(@"7e report flags ap-sim unimplemented",
          [mdOff rangeOfString:@"AP-simulation"].location != NSNotFound);
    check(@"7f report has active-op attempts", [mdOff rangeOfString:@"Active-operation attempts"].location != NSNotFound);
    check(@"7g report redaction OFF emits raw BSSID",
          [mdOff rangeOfString:kLabBSSID].location != NSNotFound);

    report.redaction = redOn;
    NSString *mdOn = [report generateMarkdown];
    check(@"7h report redaction ON emits NO raw BSSID",
          [mdOn rangeOfString:kLabBSSID].location == NSNotFound);
    check(@"7i report redaction ON emits NO raw SSID",
          [mdOn rangeOfString:kLabSSID].location == NSNotFound);

    // cleanup
    [log reset];
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:NULL];

    BOOL pass = (fail.count == 0);
    if (pass) DBNSLog(@"[KMLabSelfTest] PASS - S7.1 lab core held: passive event log, filters, scope-bound profiles, fail-closed workflow gate (no-adapter/out-of-scope/e-stop refusals + ap-sim/captive-portal unimplemented), report lab section + limitations + redaction.");
    else {
        DBNSLog(@"[KMLabSelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMLabSelfTest]   - %@", l);
    }
    return pass;
}

@end
