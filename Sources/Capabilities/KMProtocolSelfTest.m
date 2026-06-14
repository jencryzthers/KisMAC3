/*
 File:          KMProtocolSelfTest.m
 Program:       KisMac3
 Slice:         S2.1 - Modern protocol metadata model + fixtures

 Description:   See KMProtocolSelfTest.h. OFFLINE / PASSIVE ONLY.

 This file is part of KisMAC. GPL v2.
 */

#import "KMProtocolSelfTest.h"
#import "WaveScanner.h"
#import "WaveContainer.h"
#import "WaveNet.h"

// Each fixture is a single beacon -> exactly one network. The expected
// security/PHY strings are pinned here and in Tests/Fixtures/README.md, and were
// independently verified by compiling KMProtocolMetadata.m standalone.
//
// The malformed fixture asserts only "did not crash"; its decoded values are
// best-effort (privacy-bit fallback), so we accept whatever comes back as long
// as the import completes.
typedef struct {
    const char *resource;   // bundle resource name (without .pcap)
    const char *security;   // expected -[WaveNet securityString], or NULL == any
    const char *phy;        // expected -[WaveNet phyString], or NULL == any
} KMProtoExpect;

static const KMProtoExpect kExpect[] = {
    {"proto_wep",             "WEP",                                    "802.11a/b/g"},
    {"proto_wpa2",            "WPA2-Personal",                          "802.11a/b/g"},
    {"proto_wpa3_sae",        "WPA3-SAE (PMF required)",                "802.11a/b/g"},
    {"proto_wpa3_transition", "WPA2/WPA3-Transition (PMF capable)",     "802.11a/b/g"},
    {"proto_owe",             "OWE (Enhanced Open) (PMF required)",     "802.11a/b/g"},
    {"proto_enterprise",      "WPA2-Enterprise",                        "802.11a/b/g"},
    {"proto_pmf_required",    "WPA2-Personal (PMF required)",           "802.11a/b/g"},
    {"proto_hidden",          "WPA2-Personal",                          "802.11a/b/g"},
    {"proto_wifi6",           "WPA3-SAE (PMF required)",                "Wi-Fi 6 (802.11ax), 80 MHz"},
    {"proto_wifi6e",          "WPA3-SAE (PMF required)",                "Wi-Fi 6E (802.11ax, 6 GHz)"},
    {"proto_wifi7",           "WPA3-SAE (PMF required)",                "Wi-Fi 7 (802.11be), 320 MHz"},
    {"proto_malformed",       NULL,                                     NULL}, // no-crash only
};

@implementation KMProtocolSelfTest

+ (BOOL)importFirstNetAtPath:(NSString *)path
                    security:(NSString **)outSec
                         phy:(NSString **)outPhy
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;

    WaveContainer *container = [[WaveContainer alloc] init];
    [container clearAllEntries];

    WaveScanner *scanner = [[WaveScanner alloc] init];
    [scanner setValue:container forKey:@"_container"];

    // OFFLINE import only -- routes through pcap_open_offline. No radio.
    [scanner readPCAPDump:path];
    [container refreshView];

    if ([container count] == 0) return NO;
    WaveNet *net = [container netAtIndex:0];
    if (outSec) *outSec = [net securityString];
    if (outPhy) *outPhy = [net phyString];
    return YES;
}

+ (BOOL)runSelfTestLogging
{
    NSUInteger total = sizeof(kExpect) / sizeof(kExpect[0]);
    NSUInteger passed = 0, ran = 0;

    DBNSLog(@"[PROTO-SELFTEST] start: %lu fixture(s) "
            @"[offline decode of imported beacons, no live capture]",
            (unsigned long)total);

    for (NSUInteger i = 0; i < total; ++i) {
        KMProtoExpect e = kExpect[i];
        NSString *name = @(e.resource);
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"pcap"];
        if (!path) {
            DBNSLog(@"[PROTO-SELFTEST] FAIL %@: fixture not bundled", name);
            continue;
        }

        ran++;
        NSString *sec = nil, *phy = nil;
        BOOL imported = [self importFirstNetAtPath:path security:&sec phy:&phy];
        if (!imported) {
            DBNSLog(@"[PROTO-SELFTEST] FAIL %@: import produced no network", name);
            continue;
        }

        if (e.security == NULL && e.phy == NULL) {
            // No-crash fixture: surviving the import IS the pass.
            DBNSLog(@"[PROTO-SELFTEST] PASS %@: no crash (malformed input) "
                    @"-> security=\"%@\" phy=\"%@\"", name, sec, phy);
            passed++;
            continue;
        }

        BOOL secOK = [sec isEqualToString:@(e.security)];
        BOOL phyOK = [phy isEqualToString:@(e.phy)];
        if (secOK && phyOK) {
            DBNSLog(@"[PROTO-SELFTEST] PASS %@: security=\"%@\" phy=\"%@\"",
                    name, sec, phy);
            passed++;
        } else {
            DBNSLog(@"[PROTO-SELFTEST] FAIL %@: "
                    @"security got=\"%@\" want=\"%s\" | phy got=\"%@\" want=\"%s\"",
                    name, sec, e.security, phy, e.phy);
        }
    }

    BOOL allPass = (passed == ran) && (ran == total);
    DBNSLog(@"[PROTO-SELFTEST] %@ %lu/%lu passed (%lu ran)",
            allPass ? @"PASS" : @"FAIL",
            (unsigned long)passed, (unsigned long)total, (unsigned long)ran);
    return allPass;
}

@end
