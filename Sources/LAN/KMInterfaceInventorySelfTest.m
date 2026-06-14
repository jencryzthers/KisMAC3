/*
 File:        KMInterfaceInventorySelfTest.m
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMInterfaceInventorySelfTest.h"
#import "KMInterfaceInventory.h"
#import "KMNetworkInterface.h"
#import "../Safety/KMRedactionSettings.h"

#import <ifaddrs.h>
#import <net/if.h>

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

@implementation KMInterfaceInventorySelfTest

/// Ground-truth set of BSD interface names directly from getifaddrs, to
/// cross-check the collector's coalesced count/names (mirrors `ifconfig -l`).
+ (NSSet<NSString *> *)groundTruthNames {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) == 0 && ifaddr) {
        for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_name) {
                NSString *n = [NSString stringWithUTF8String:ifa->ifa_name];
                if (n.length) [names addObject:n];
            }
        }
        freeifaddrs(ifaddr);
    }
    return names;
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];
    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) { DBNSLog(@"[KMInterfaceInventorySelfTest]   PASS  %@", label); }
        else      { DBNSLog(@"[KMInterfaceInventorySelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };

    DBNSLog(@"[KMInterfaceInventorySelfTest] ===== S3.4 local interface inventory self-test =====");

    // Redaction ON so the logged summary never dumps a raw MAC / IP.
    KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
    r.enabled = YES;

    // ---- 1) REAL enumeration on THIS machine (no permission needed) ----
    NSArray<KMNetworkInterface *> *ifaces = [KMInterfaceInventory currentInterfaces];
    check(@"1a enumeration returned without crashing", ifaces != nil);
    check(@"1b enumeration is non-empty (a Mac always has lo0 + en*)", ifaces.count > 0);

    DBNSLog(@"[KMInterfaceInventorySelfTest]   COUNT  interfaces=%lu", (unsigned long)ifaces.count);

    // Redacted summary of EVERY interface (name/type/up/has-IP), masked MAC/IP.
    for (KMNetworkInterface *i in ifaces) {
        DBNSLog(@"[KMInterfaceInventorySelfTest]   IFACE  %@ type=%@ up=%d hasIP=%d  ::  %@",
                i.bsdName, KMStringFromInterfaceType(i.type), i.isUp, i.hasIPAddress,
                [i redactedDescriptionWithSettings:r]);
    }

    // ---- 2) lo0 present and classified loopback ----
    KMNetworkInterface *lo0 = nil, *anyEN = nil;
    NSUInteger primaryCount = 0;
    for (KMNetworkInterface *i in ifaces) {
        if ([i.bsdName isEqualToString:@"lo0"]) lo0 = i;
        if ([i.bsdName hasPrefix:@"en"] && anyEN == nil) anyEN = i;
        if (i.isPrimary) primaryCount++;
    }
    check(@"2a lo0 is present", lo0 != nil);
    check(@"2b lo0 is classified loopback", lo0 != nil && lo0.type == KMInterfaceTypeLoopback);
    check(@"2c lo0 is up", lo0 != nil && lo0.isUp);

    // ---- 3) at least one en* interface present ----
    check(@"3a at least one en* interface present", anyEN != nil);

    // ---- 4) primary status consistent with the system ----
    NSString *sysPrimary = [KMInterfaceInventory primaryInterfaceName];
    DBNSLog(@"[KMInterfaceInventorySelfTest]   SYSTEM primaryInterface=%@", sysPrimary ?: @"(none)");
    // At most one interface flagged primary, and if the system reports a
    // primary the matching interface must be the one we flagged.
    check(@"4a at most one interface flagged primary", primaryCount <= 1);
    if (sysPrimary.length) {
        KMNetworkInterface *flagged = nil;
        for (KMNetworkInterface *i in ifaces) { if (i.isPrimary) { flagged = i; break; } }
        check(@"4b flagged primary matches system PrimaryInterface",
              flagged != nil && [flagged.bsdName isEqualToString:sysPrimary]);
    } else {
        // No default route (e.g. offline) -> no primary flagged. Consistent.
        check(@"4b no system primary => none flagged", primaryCount == 0);
    }

    // ---- 5) count/names consistent with getifaddrs ground truth ----
    NSSet<NSString *> *truth = [self groundTruthNames];
    NSMutableSet<NSString *> *collected = [NSMutableSet set];
    for (KMNetworkInterface *i in ifaces) [collected addObject:i.bsdName];
    DBNSLog(@"[KMInterfaceInventorySelfTest]   GROUND-TRUTH getifaddrs names=%lu  collected(coalesced)=%lu",
            (unsigned long)truth.count, (unsigned long)collected.count);
    check(@"5a collected names == getifaddrs distinct names (coalesced 1-per-iface)",
          [collected isEqualToSet:truth]);

    // ---- 6) Redaction: no raw MAC/IP leaks into the redacted description ----
    KMNetworkInterface *withMAC = nil;
    for (KMNetworkInterface *i in ifaces) { if (i.macAddress.length) { withMAC = i; break; } }
    if (withMAC) {
        NSString *desc = [withMAC redactedDescriptionWithSettings:r];
        check(@"6a redacted description does NOT contain the raw MAC",
              [desc rangeOfString:withMAC.macAddress].location == NSNotFound);
    } else {
        DBNSLog(@"[KMInterfaceInventorySelfTest]   SKIP  no interface exposed a link-layer MAC to redaction-check");
    }

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMInterfaceInventorySelfTest] PASS - getifaddrs enumeration ran headlessly (interfaces=%lu), "
                @"lo0 present+loopback, en* present, primary=%@ consistent, names match getifaddrs ground truth, "
                @"MAC/IP redactable. READ-ONLY: no interface configured, no traffic.",
                (unsigned long)ifaces.count, sysPrimary ?: @"(none)");
    } else {
        DBNSLog(@"[KMInterfaceInventorySelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMInterfaceInventorySelfTest]   - %@", l);
    }
    return pass;
}

@end
