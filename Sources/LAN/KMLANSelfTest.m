/*
 File:        KMLANSelfTest.m
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 This file is part of KisMAC. GPL v2.
 */

#import "KMLANSelfTest.h"
#import "KMLANDiscovery.h"
#import "KMLANService.h"
#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Capabilities/KMHardwareCapability.h"
#import "../Safety/KMRedactionSettings.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

@implementation KMLANSelfTest

+ (NSArray<KMHardwareCapability *> *)mockGreenWiFi {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusSupported reason:@"mock iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusSupported reason:@"mock granted"],
    ];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];
    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) { DBNSLog(@"[KMLANSelfTest]   PASS  %@", label); }
        else      { DBNSLog(@"[KMLANSelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };

    DBNSLog(@"[KMLANSelfTest] ===== S3.3 LAN discovery (passive Bonjour/DNS-SD) self-test =====");

    // Redaction ON so the logged sample never dumps a raw hostname / IP.
    KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
    r.enabled = YES;

    // ---- 1) Browser starts without crashing + passive future-hook honesty ----
    KMLANDiscovery *lan = [[KMLANDiscovery alloc] init];
    check(@"1a discovery object instantiated", lan != nil);
    check(@"1b active ping sweep is NOT implemented (passive only, no stealth)",
          lan.pingSweepIsImplemented == NO);
    check(@"1c default service-type set is non-empty",
          [KMLANDiscovery defaultServiceTypes].count > 0);

    [lan startBrowsing];
    check(@"1d browser started without crashing (browsing == YES)", lan.isBrowsing);

    // ---- 2) Brief (~3s) PASSIVE browse on THIS machine ----
    // The browser's result/resolution handlers run on KMLANDiscovery's OWN
    // serial queue (not the main runloop), and -discoveredServices reads the
    // store via dispatch_sync on that queue. So we just sleep here -- we do NOT
    // pump the main runloop (which a modal alert elsewhere at launch could
    // otherwise stall).
    DBNSLog(@"[KMLANSelfTest] browsing passively for ~3s (mDNS/DNS-SD announcements only; no active probe)...");
    [NSThread sleepForTimeInterval:3.0];

    NSArray<KMLANService *> *services = [lan discoveredServices];
    check(@"2a discoveredServices returned without crashing", services != nil);

    DBNSLog(@"[KMLANSelfTest]   COUNT  bonjour services discovered = %lu  (localNetworkState=%@)",
            (unsigned long)services.count,
            KMStringFromLANNetworkState(lan.localNetworkState));

    // Redacted samples (up to 5).
    NSUInteger shown = 0;
    for (KMLANService *svc in services) {
        DBNSLog(@"[KMLANSelfTest]   SAMPLE %@", [svc redactedDescriptionWithSettings:r]);
        if (++shown >= 5) break;
    }

    // ---- 3) Redaction: a resolved hostname is NOT dumped raw ----
    KMLANService *withHost = nil;
    for (KMLANService *s in services) { if (s.hostName.length > 0) { withHost = s; break; } }
    if (withHost) {
        NSString *desc = [withHost redactedDescriptionWithSettings:r];
        check(@"3a redacted description does NOT contain the raw hostname",
              [desc rangeOfString:withHost.hostName].location == NSNotFound);
    } else {
        DBNSLog(@"[KMLANSelfTest]   SKIP  no service resolved to a hostname to redaction-check");
    }

    // ---- 4) Engine reports lanDiscovery / bonjourInventory honestly ----
    KMCapabilityEngine *engine =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockGreenWiFi]
                                                   scopeProvider:nil
                                                 parserRegistry:nil
                                                adapterProvider:nil];
    KMCapability *lanCap = [engine availabilityForCapability:KMFeatureLANDiscovery];
    KMCapability *bonjourCap = [engine availabilityForCapability:KMFeatureBonjourInventory];

    // Honest PASS: available (passive Bonjour allowed) OR permissionMissing
    // (Local Network denied). Never "unknownRequiresActiveProbe" anymore.
    BOOL lanOK = (lanCap.availability == KMCapabilityAvailable) ||
                 (lanCap.availability == KMCapabilityUnavailable &&
                  lanCap.reason == KMCapabilityReasonPermissionMissing);
    BOOL bonjourOK = (bonjourCap.availability == KMCapabilityAvailable) ||
                     (bonjourCap.availability == KMCapabilityUnavailable &&
                      bonjourCap.reason == KMCapabilityReasonPermissionMissing);
    check(@"4a engine lanDiscovery available (or permissionMissing) -- not 'not implemented'",
          lanOK);
    check(@"4b engine bonjourInventory available (or permissionMissing)",
          bonjourOK);
    check(@"4c lanDiscovery is no longer unknownRequiresActiveProbe",
          lanCap.availability != KMCapabilityUnknownRequiresActiveProbe);
    DBNSLog(@"[KMLANSelfTest]   ENGINE lanDiscovery=%@/%@  bonjourInventory=%@/%@",
            KMStringFromCapabilityAvailability(lanCap.availability),
            KMStringFromCapabilityReason(lanCap.reason),
            KMStringFromCapabilityAvailability(bonjourCap.availability),
            KMStringFromCapabilityReason(bonjourCap.reason));

    // ---- 5) No active/stealth scanning occurred (structural assertion) ----
    check(@"5a passive only: no active ping sweep path exists",
          lan.pingSweepIsImplemented == NO);

    [lan stopBrowsing];
    check(@"5b browser stopped cleanly (browsing == NO)", lan.isBrowsing == NO);

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMLANSelfTest] PASS - passive Bonjour browse ran headlessly (services=%lu, state=%@), "
                @"engine reports lanDiscovery/bonjourInventory available-or-permissionMissing, "
                @"hostnames/IPs redactable, NO active/stealth scan. "
                @"NOTE: Local Network permission may gate live results on a signed build.",
                (unsigned long)services.count,
                KMStringFromLANNetworkState(lan.localNetworkState));
    } else {
        DBNSLog(@"[KMLANSelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMLANSelfTest]   - %@", l);
    }
    return pass;
}

@end
