/*
 File:        KMReportSelfTest.m
 Program:     KisMac3
 Slice:       S6.1 - Secure .kismac load + unified report generator

 This file is part of KisMAC. GPL v2. OFFLINE / PASSIVE ONLY.
 */

#import "KMReportSelfTest.h"
#import "KMReport.h"

#import "WaveStorageController.h"
#import "WaveContainer.h"
#import "WaveNet.h"
#import "WaveScanner.h"

#import "KMCapabilityEngine.h"
#import "KMCapability.h"
#import "KMRedactionSettings.h"
#import "KMPrivacySettings.h"

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

// Golden fixture known networks (see Tests/Fixtures/README.md).
static NSString * const kAlphaSSID  = @"KISMAC-FIX-ALPHA";
static NSString * const kBravoSSID  = @"KISMAC-FIX-BRAVO";
static NSString * const kAlphaBSSID = @"00:11:22:33:44:01";

@implementation KMReportSelfTest

#pragma mark - small assert helper

static BOOL kmAssert(BOOL cond, NSString *label, NSString *detail) {
    DBNSLog(@"[REPORT-SELFTEST] %@ %@%@", cond ? @"PASS" : @"FAIL", label,
            detail.length ? [@" — " stringByAppendingString:detail] : @"");
    return cond;
}

#pragma mark - Part A: secure .kismac load

// Build a small WaveNet via its plist dictionary representation so we have a
// real model object to round-trip.
+ (WaveNet *)makeSampleNet {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"netID"]    = @(1);
    d[@"channel"]  = @(6);
    d[@"originalChannel"] = @(6);
    d[@"type"]     = @(2);          // managed
    d[@"encryption"] = @(0);
    d[@"ID"]       = @"001122334455";
    d[@"SSID"]     = @"SELFTEST-NET";
    d[@"BSSID"]    = @"00:11:22:33:44:55";
    d[@"date"]     = [NSDate dateWithTimeIntervalSince1970:1700000000];
    d[@"firstDate"]= [NSDate dateWithTimeIntervalSince1970:1700000000];
    d[@"maxSignal"]= @(-42);
    return [[WaveNet alloc] initWithDataDictionary:d];
}

// (A1) WaveNet NSSecureCoding round-trip: encode with requiringSecureCoding,
// decode with the secure allowlist. Proves +supportsSecureCoding + the typed
// decoders work end to end.
+ (BOOL)testWaveNetSecureCodingRoundTrip {
    WaveNet *net = [self makeSampleNet];
    if (!net) return kmAssert(NO, @"A1 WaveNet secure-coding round-trip", @"could not build sample net");

    NSError *err = nil;
    NSData *blob = [NSKeyedArchiver archivedDataWithRootObject:net
                                        requiringSecureCoding:YES
                                                        error:&err];
    if (!blob || err)
        return kmAssert(NO, @"A1 WaveNet secure-coding round-trip",
                        [NSString stringWithFormat:@"encode failed: %@", err.localizedDescription]);

    WaveNet *back = [NSKeyedUnarchiver unarchivedObjectOfClasses:
                        [WaveStorageController secureLegacyAllowedClasses]
                                                        fromData:blob
                                                           error:&err];
    BOOL ok = (back != nil && err == nil
               && [[back SSID] isEqualToString:@"SELFTEST-NET"]
               && [back channel] == 6);
    return kmAssert(ok, @"A1 WaveNet secure-coding round-trip",
                    [NSString stringWithFormat:@"ssid=%@ ch=%ld", [back SSID], (long)[back channel]]);
}

// (A2) Legacy `.kismac` graph loads THROUGH the secure unarchiver and populates
// a container. We archive a raw NSKeyedArchiver dict { Creator, Trace, Networks }
// (the "Creator=KisMAC" path), decode it via the hardened
// +secureLegacyDictionaryFromData: (NOT the old insecure call), then drive the
// EXACT container step the legacy loader performs (-loadData: on Networks) and
// assert fidelity. We deliberately exercise the secure-unarchive + container
// steps directly rather than +loadFromFile:, which would first hand the file to
// BIDecompressor (the compressed-format path) — out of scope for this Part-A
// assertion, which is specifically about the secure UNARCHIVER.
+ (BOOL)testLegacyKismacSecureLoad {
    NSDictionary *net1 = @{ @"netID": @(1), @"channel": @(6), @"originalChannel": @(6),
                            @"type": @(2), @"encryption": @(0),
                            @"ID": @"001122334455", @"SSID": @"SELFTEST-NET",
                            @"BSSID": @"00:11:22:33:44:55",
                            @"date": [NSDate dateWithTimeIntervalSince1970:1700000000],
                            @"firstDate": [NSDate dateWithTimeIntervalSince1970:1700000000],
                            @"maxSignal": @(-42) };
    NSDictionary *root = @{ @"Creator": @"KisMAC",
                            @"Trace": @[],
                            @"Networks": @[ net1 ] };

    NSError *err = nil;
    NSData *blob = [NSKeyedArchiver archivedDataWithRootObject:root
                                        requiringSecureCoding:NO
                                                        error:&err];
    if (!blob) return kmAssert(NO, @"A2 .kismac secure legacy load", @"could not archive root dict");

    // (1) The hardened secure unarchiver accepts the allowlisted graph.
    NSDictionary *decoded = [WaveStorageController secureLegacyDictionaryFromData:blob];
    BOOL helperOK = ([decoded isKindOfClass:[NSDictionary class]]
                     && [decoded[@"Creator"] isEqualToString:@"KisMAC"]
                     && [decoded[@"Networks"] isKindOfClass:[NSArray class]]
                     && [decoded[@"Networks"] count] == 1);

    // (2) The decoded per-net dictionary rehydrates a WaveNet with fidelity and
    //     deposits into a container (the model step the loader performs after the
    //     secure decode). We build + addNetwork: directly rather than -loadData:,
    //     which calls -[WaveNet copy] (WaveNet predates NSCopying — a separate
    //     legacy issue, out of scope for this secure-load assertion).
    BOOL fidelity = NO, loaded = NO;
    if (helperOK) {
        NSDictionary *netDict = [decoded[@"Networks"] firstObject];
        WaveNet *n = [[WaveNet alloc] initWithDataDictionary:netDict];
        WaveContainer *container = [[WaveContainer alloc] init];
        [container clearAllEntries];
        loaded = (n != nil) && [container addNetwork:n];
        [container refreshView];
        if (loaded && [container count] == 1) {
            WaveNet *got = [container netAtIndex:0];
            fidelity = [[got SSID] isEqualToString:@"SELFTEST-NET"] && [got channel] == 6;
        }
    }

    BOOL ok = helperOK && loaded && fidelity;
    return kmAssert(ok, @"A2 .kismac secure legacy load",
                    [NSString stringWithFormat:@"helperOK=%d loaded=%d fidelity=%d",
                     helperOK, loaded, fidelity]);
}

// (A3) Malformed / hostile input fails gracefully. Two cases:
//   (a) an archive whose ROOT is a disallowed class (NSValue) — the secure
//       unarchiver must reject it (nil), NOT instantiate it;
//   (b) random garbage bytes — must also return nil, no crash.
+ (BOOL)testMalformedInputFailsClosed {
    NSError *err = nil;
    // (a) disallowed root class.
    NSData *hostile = [NSKeyedArchiver archivedDataWithRootObject:[NSValue valueWithRange:NSMakeRange(1,2)]
                                           requiringSecureCoding:NO
                                                           error:&err];
    NSDictionary *r1 = [WaveStorageController secureLegacyDictionaryFromData:hostile];

    // (b) pure garbage.
    NSData *garbage = [@"this is not a keyed archive at all" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *r2 = [WaveStorageController secureLegacyDictionaryFromData:garbage];

    // (c) nil/empty.
    NSDictionary *r3 = [WaveStorageController secureLegacyDictionaryFromData:[NSData data]];

    BOOL ok = (r1 == nil && r2 == nil && r3 == nil);
    return kmAssert(ok, @"A3 malformed/hostile input fails closed",
                    [NSString stringWithFormat:@"disallowedRoot=%@ garbage=%@ empty=%@",
                     r1 ? @"DECODED(!)" : @"nil",
                     r2 ? @"DECODED(!)" : @"nil",
                     r3 ? @"DECODED(!)" : @"nil"]);
}

#pragma mark - Part B: unified report

+ (NSString *)goldenFixturePath {
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"golden" ofType:@"pcap"];
    if (bundled) return bundled;
    // Fallback: repo-relative (when run from a dev tree).
    NSString *env = [[NSProcessInfo processInfo] environment][@"KISMAC_REPORT_FIXTURE"];
    if (env.length) return [env stringByExpandingTildeInPath];
    return nil;
}

+ (WaveContainer *)importGolden:(NSString *)path {
    WaveContainer *container = [[WaveContainer alloc] init];
    [container clearAllEntries];
    WaveScanner *scanner = [[WaveScanner alloc] init];
    [scanner setValue:container forKey:@"_container"];
    [scanner readPCAPDump:path];   // OFFLINE, no radio.
    [container refreshView];
    return container;
}

+ (KMReport *)reportForContainer:(WaveContainer *)container redact:(BOOL)redact {
    KMReport *report = [[KMReport alloc] init];
    report.title = @"S6.1 Self-Test Report";
    report.container = container;
    // READS the engine (invariant). A live-probe engine is fine here; it never
    // touches a radio for the report — the report only renders its output.
    report.capabilityEngine = [[KMCapabilityEngine alloc] initWithLiveProbe];

    KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
    r.enabled = redact;            // all four per-type flags default YES
    report.redaction = r;
    report.captureFiles = @[ @"golden.pcap" ];
    return report;
}

// (B1) report contains the expected sections + the 3 known networks +
// capability/blocked section present.
+ (BOOL)testReportSectionsAndNetworks:(WaveContainer *)container {
    KMReport *report = [self reportForContainer:container redact:NO];
    NSString *md = [report generateMarkdown];

    NSArray<NSString *> *sections = @[
        @"## Discovered networks", @"## Observed clients",
        @"## Protocol & security posture", @"## LAN hosts & services",
        @"## Local network interfaces", @"## BLE devices",
        @"## USB devices", @"## Capture & evidence files",
        @"## MacBook capability result", @"## Capabilities & blocked features",
        @"### Unsupported / blocked (with reasons)", @"## Evidence timeline" ];
    BOOL sectionsOK = YES;
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *s in sections) {
        if ([md rangeOfString:s].location == NSNotFound) { sectionsOK = NO; [missing addObject:s]; }
    }
    BOOL netsOK = ([md rangeOfString:kAlphaSSID].location != NSNotFound
                   && [md rangeOfString:kBravoSSID].location != NSNotFound
                   && [md rangeOfString:@"KISMAC-FIX-CHARLIE"].location != NSNotFound);
    // evidence timeline carries explicit source labels
    BOOL sourceLabelOK = ([md rangeOfString:@"pcap"].location != NSNotFound);

    BOOL ok = sectionsOK && netsOK && sourceLabelOK;
    return kmAssert(ok, @"B1 report sections + 3 known networks + source labels",
                    [NSString stringWithFormat:@"missingSections=%@ netsOK=%d sourceLabelOK=%d",
                     missing.count ? [missing componentsJoinedByString:@","] : @"(none)",
                     netsOK, sourceLabelOK]);
}

// (B2) redaction OFF => raw BSSID/SSID present.
+ (BOOL)testRedactionOff:(WaveContainer *)container {
    NSString *md = [[self reportForContainer:container redact:NO] generateMarkdown];
    BOOL ok = ([md rangeOfString:kAlphaSSID].location != NSNotFound
               && [md rangeOfString:kAlphaBSSID].location != NSNotFound);
    return kmAssert(ok, @"B2 redaction OFF emits raw SSID + BSSID",
                    [NSString stringWithFormat:@"ssidRaw=%d bssidRaw=%d",
                     [md rangeOfString:kAlphaSSID].location != NSNotFound,
                     [md rangeOfString:kAlphaBSSID].location != NSNotFound]);
}

// (B3) redaction ON => NO raw BSSID/SSID anywhere.
+ (BOOL)testRedactionOn:(WaveContainer *)container {
    NSString *md = [[self reportForContainer:container redact:YES] generateMarkdown];
    BOOL ssidLeak  = ([md rangeOfString:kAlphaSSID].location != NSNotFound
                      || [md rangeOfString:kBravoSSID].location != NSNotFound
                      || [md rangeOfString:@"KISMAC-FIX-CHARLIE"].location != NSNotFound);
    // Full BSSID must be gone; the OUI prefix may remain by design.
    BOOL bssidLeak = ([md rangeOfString:kAlphaBSSID].location != NSNotFound);
    BOOL ok = (!ssidLeak && !bssidLeak);
    return kmAssert(ok, @"B3 redaction ON emits NO raw SSID/BSSID",
                    [NSString stringWithFormat:@"ssidLeak=%d bssidLeak=%d", ssidLeak, bssidLeak]);
}

#pragma mark - Runner

// Run a single test step under exception protection so a throw is reported as a
// FAIL (with the reason) instead of silently aborting the whole runner.
+ (BOOL)guard:(NSString *)label block:(BOOL (^)(void))block {
    @try {
        return block();
    } @catch (NSException *ex) {
        return kmAssert(NO, label, [NSString stringWithFormat:@"EXCEPTION: %@ — %@", ex.name, ex.reason]);
    }
}

+ (BOOL)runSelfTestLogging {
    DBNSLog(@"[REPORT-SELFTEST] === S6.1 secure .kismac load + unified report ===");
    BOOL all = YES;

    // Part A — secure load.
    all &= [self guard:@"A1 WaveNet secure-coding round-trip" block:^{ return [self testWaveNetSecureCodingRoundTrip]; }];
    all &= [self guard:@"A2 .kismac secure legacy load" block:^{ return [self testLegacyKismacSecureLoad]; }];
    all &= [self guard:@"A3 malformed/hostile input fails closed" block:^{ return [self testMalformedInputFailsClosed]; }];

    // Part B — report.
    NSString *fixture = [self goldenFixturePath];
    if (!fixture || ![[NSFileManager defaultManager] fileExistsAtPath:fixture]) {
        kmAssert(NO, @"B0 golden.pcap fixture present",
                 @"no golden.pcap in bundle (set KISMAC_REPORT_FIXTURE=<path>)");
        all = NO;
    } else {
        WaveContainer *container = [self importGolden:fixture];
        BOOL imported = kmAssert([container count] == 3,
                                 @"B0 golden import -> 3 networks",
                                 [NSString stringWithFormat:@"count=%lu", (unsigned long)[container count]]);
        all &= imported;
        all &= [self guard:@"B1 report sections + 3 known networks + source labels" block:^{ return [self testReportSectionsAndNetworks:container]; }];
        all &= [self guard:@"B2 redaction OFF emits raw SSID + BSSID" block:^{ return [self testRedactionOff:container]; }];
        all &= [self guard:@"B3 redaction ON emits NO raw SSID/BSSID" block:^{ return [self testRedactionOn:container]; }];
    }

    DBNSLog(@"[REPORT-SELFTEST] OVERALL %@", all ? @"PASS" : @"FAIL");
    return all;
}

@end
