/*

 File:          KMPcapImportSelfTest.m
 Program:       KisMAC

 Description:   See KMPcapImportSelfTest.h. OFFLINE / PASSIVE ONLY.

 This file is part of KisMAC.

 KisMAC is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License, version 2,
 as published by the Free Software Foundation;
 */

#import "KMPcapImportSelfTest.h"
#import "WaveScanner.h"
#import "WaveContainer.h"
#import "WaveNet.h"

// --- Golden fixture expected counts (see Tests/Fixtures/README.md) ----------
// 3 beacon frames (3 distinct BSSIDs) + 1 ToDS data frame.
static const NSUInteger kExpectedNetworkCount = 3;
// Client count is the observed-and-pinned golden value produced by the real
// WavePacket->WaveNet->WaveContainer pipeline for golden.pcap (see README).
// Each beacon registers its BSSID (sender) and the broadcast DA (receiver) as
// clients of its network; the data frame adds one station to network ALPHA:
//   ALPHA   = {BSSID_01, FF:FF:FF:FF:FF:FF, AA:BB:CC:DD:EE:01} = 3
//   BRAVO   = {BSSID_02, FF:FF:FF:FF:FF:FF}                    = 2
//   CHARLIE = {BSSID_03, FF:FF:FF:FF:FF:FF}                    = 2
//   total                                                      = 7
static const NSUInteger kExpectedClientCount = 7;

@implementation KMPcapImportSelfTest

+ (BOOL)importFixtureAtPath:(NSString *)path
                networkCount:(NSUInteger *)outNetworks
                 clientCount:(NSUInteger *)outClients
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        DBNSLog(@"[PCAP-IMPORT-SELFTEST] fixture not found at %@", path);
        return NO;
    }

    // Throwaway container + scanner; inject the container into the scanner's
    // IBOutlet ivar so the offline import has somewhere to deposit results.
    WaveContainer *container = [[WaveContainer alloc] init];
    [container clearAllEntries];

    WaveScanner *scanner = [[WaveScanner alloc] init];
    [scanner setValue:container forKey:@"_container"];

    // OFFLINE import only — readPCAPDump: routes through pcap_open_offline.
    // It never starts a scan / touches a radio / changes channels.
    [scanner readPCAPDump:path];

    // -count returns the *view*-filtered (_sortedCount) total, which addPacket:
    // does not populate; the GUI refreshes the view after an import. Mirror that
    // here so the count reflects every imported network.
    [container refreshView];

    NSUInteger nets = [container count];
    NSUInteger clients = 0;
    for (NSUInteger i = 0; i < nets; ++i) {
        WaveNet *net = [container netAtIndex:i];
        clients += [[net getClientKeys] count];
    }

    if (outNetworks) *outNetworks = nets;
    if (outClients)  *outClients = clients;
    return YES;
}

+ (NSString *)resolvedFixturePath
{
    NSString *env = [[NSProcessInfo processInfo] environment][@"KISMAC_PCAP_IMPORT_SELFTEST"];

    // An explicit path (anything that isn't the "enable" sentinel) wins.
    if (env.length > 0 && ![env isEqualToString:@"1"]) {
        return [env stringByExpandingTildeInPath];
    }

    // Otherwise default to the committed golden fixture bundled in Resources.
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"golden" ofType:@"pcap"];
    if (bundled) return bundled;

    return nil;
}

+ (BOOL)runSelfTestLogging
{
    NSString *path = [self resolvedFixturePath];
    if (!path) {
        DBNSLog(@"[PCAP-IMPORT-SELFTEST] FAIL: no fixture path resolved "
                @"(set KISMAC_PCAP_IMPORT_SELFTEST=<path> or bundle golden.pcap)");
        return NO;
    }

    NSUInteger nets = 0, clients = 0;
    BOOL imported = [self importFixtureAtPath:path
                                  networkCount:&nets
                                   clientCount:&clients];
    if (!imported) {
        DBNSLog(@"[PCAP-IMPORT-SELFTEST] FAIL: could not import %@", path);
        return NO;
    }

    BOOL pass = (nets == kExpectedNetworkCount) && (clients == kExpectedClientCount);
    DBNSLog(@"[PCAP-IMPORT-SELFTEST] %@ fixture=%@ networks=%lu (expected %lu) "
            @"clients=%lu (expected %lu) [offline import, no live capture]",
            pass ? @"PASS" : @"FAIL",
            [path lastPathComponent],
            (unsigned long)nets, (unsigned long)kExpectedNetworkCount,
            (unsigned long)clients, (unsigned long)kExpectedClientCount);
    return pass;
}

@end
