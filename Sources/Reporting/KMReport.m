/*
 File:        KMReport.m
 Program:     KisMac3
 Slice:       S6.1 - Secure .kismac load + unified report generator (Milestone 12)

 This file is part of KisMAC. GPL v2.
 */

#import "KMReport.h"

#import "WaveContainer.h"
#import "WaveNet.h"
#import "WaveClient.h"
#import "KMProtocolMetadata.h"

#import "KMCapability.h"
#import "KMCapabilityEngine.h"
#import "KMHardwareProbe.h"
#import "KMHardwareCapability.h"

#import "KMRedactionSettings.h"
#import "KMPrivacySettings.h"
#import "KMReportSelfTest.h"

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

// All S3.x inventory models (KMBluetoothDevice / KMUSBDevice / KMHIDDevice /
// KMSerialDevice / KMLANService / KMNetworkInterface) expose this redaction
// entry point. We declare it as an informal protocol so the report can call it
// on a heterogeneous `id<KMRedactableDescription>` without importing each model.
@protocol KMRedactableDescription <NSObject>
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;
@end

NSString *KMStringFromEvidenceSource(KMEvidenceSource source) {
    switch (source) {
        case KMEvidenceSourceCoreWLAN:      return @"CoreWLAN";
        case KMEvidenceSourceCoreBluetooth: return @"CoreBluetooth";
        case KMEvidenceSourcePcap:          return @"pcap";
        case KMEvidenceSourceKismet:        return @"Kismet";
        case KMEvidenceSourceUSB:           return @"USB";
        case KMEvidenceSourceUserImport:    return @"user-import";
        case KMEvidenceSourceManualNote:    return @"manual-note";
    }
    return @"unknown";
}

@implementation KMEvidenceEntry
+ (instancetype)entryWithDate:(NSDate *)date
                       source:(KMEvidenceSource)source
                       detail:(NSString *)detail {
    KMEvidenceEntry *e = [[self alloc] init];
    e.timestamp = date;
    e.source = source;
    e.detail = detail ?: @"";
    return e;
}
@end

@implementation KMReport

#pragma mark - Helpers (redaction goes through the supplied settings)

- (KMRedactionSettings *)effectiveRedaction {
    // nil => fully-redacted safe default (never leak when unset).
    if (self.redaction) return self.redaction;
    KMRedactionSettings *safe = [KMRedactionSettings defaultSettings];
    safe.enabled = YES;
    return safe;
}

- (KMPrivacySettings *)effectivePrivacy {
    return self.privacy ?: [KMPrivacySettings sharedSettings];
}

- (NSString *)redactMAC:(NSString *)s    { return [[self effectiveRedaction] redactMAC:s]; }
- (NSString *)redactSSID:(NSString *)s   { return [[self effectiveRedaction] redactSSID:s]; }
- (NSString *)redactHost:(NSString *)s   { return [[self effectiveRedaction] redactHostname:s]; }
- (NSString *)redactBT:(NSString *)s     { return [[self effectiveRedaction] redactBluetoothIdentifier:s]; }

- (NSString *)isoString:(NSDate *)d {
    if (![d isKindOfClass:[NSDate class]]) return @"-";
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [fmt stringFromDate:d];
}

#pragma mark - Section builders

- (void)appendHeader:(NSMutableString *)md {
    KMPrivacySettings *priv = [self effectivePrivacy];
    BOOL redactOn = [self effectiveRedaction].isEnabled;
    [md appendFormat:@"# %@\n\n", self.title.length ? self.title : @"KisMac3 Report"];
    [md appendFormat:@"_Generated: %@ (UTC)_\n\n", [self isoString:[NSDate date]]];
    [md appendString:@"> Privacy: local-only artifact. "];
    [md appendFormat:@"Server export: **%@** (opt-in). ", priv.allowsServerExport ? @"enabled" : @"OFF"];
    [md appendFormat:@"Redaction: **%@**.\n\n", redactOn ? @"ON" : @"off"];
}

// Discovered networks (S2.1 security/PHY strings).
- (void)appendNetworks:(NSMutableString *)md {
    [md appendString:@"## Discovered networks\n\n"];
    WaveContainer *c = self.container;
    if (!c || [c count] == 0) {
        [md appendString:@"_No networks._\n\n"];
        return;
    }
    [md appendString:@"| SSID | BSSID | Ch | Security | PHY | Signal | Last seen | Source |\n"];
    [md appendString:@"|------|-------|----|----------|-----|--------|-----------|--------|\n"];
    for (NSUInteger i = 0; i < [c count]; ++i) {
        WaveNet *net = [c netAtIndex:i];
        NSString *ssid = [self redactSSID:[net SSID] ?: @""];
        NSString *bssid = [self redactMAC:[net BSSID] ?: @""];
        NSString *sec = [net securityString] ?: @"";
        NSString *phy = [net phyString] ?: @"";
        NSString *src = [net liveCaptured] ? @"CoreWLAN" : @"pcap/import";
        [md appendFormat:@"| %@ | %@ | %ld | %@ | %@ | %ld dBm | %@ | %@ |\n",
            ssid.length ? ssid : @"&lt;hidden&gt;",
            bssid.length ? bssid : @"-",
            (long)[net channel],
            sec.length ? sec : @"-",
            phy.length ? phy : @"-",
            (long)[net maxSignal],
            [self isoString:[net lastSeenDate]],
            src];
    }
    [md appendFormat:@"\n_Total networks: %lu_\n\n", (unsigned long)[c count]];
}

// Observed clients (per network).
- (void)appendClients:(NSMutableString *)md {
    [md appendString:@"## Observed clients\n\n"];
    WaveContainer *c = self.container;
    NSUInteger total = 0;
    NSMutableString *body = [NSMutableString string];
    for (NSUInteger i = 0; c && i < [c count]; ++i) {
        WaveNet *net = [c netAtIndex:i];
        NSDictionary *clients = [net getClients];
        NSArray *keys = [net getClientKeys];
        if (clients.count == 0) continue;
        [body appendFormat:@"- **%@** (%@): ", [self redactSSID:[net SSID] ?: @""], [self redactMAC:[net BSSID] ?: @""]];
        NSMutableArray *cline = [NSMutableArray array];
        for (id k in (keys.count ? keys : clients.allKeys)) {
            WaveClient *cl = clients[k];
            if (![cl isKindOfClass:[WaveClient class]]) continue;
            NSString *cid = [self redactMAC:[cl ID] ?: @""];
            [cline addObject:cid.length ? cid : @"?"];
            total++;
        }
        [body appendFormat:@"%@\n", [cline componentsJoinedByString:@", "]];
    }
    if (total == 0) { [md appendString:@"_No clients._\n\n"]; return; }
    [md appendString:body];
    [md appendFormat:@"\n_Total clients: %lu_\n\n", (unsigned long)total];
}

// Protocol / security posture summary (counts by security string).
- (void)appendProtocolPosture:(NSMutableString *)md {
    [md appendString:@"## Protocol & security posture\n\n"];
    WaveContainer *c = self.container;
    if (!c || [c count] == 0) { [md appendString:@"_No data._\n\n"]; return; }
    NSCountedSet *secCounts = [NSCountedSet set];
    NSCountedSet *phyCounts = [NSCountedSet set];
    for (NSUInteger i = 0; i < [c count]; ++i) {
        WaveNet *net = [c netAtIndex:i];
        [secCounts addObject:([net securityString].length ? [net securityString] : @"(unknown)")];
        [phyCounts addObject:([net phyString].length ? [net phyString] : @"(unknown)")];
    }
    [md appendString:@"Security:\n"];
    for (NSString *s in [secCounts.allObjects sortedArrayUsingSelector:@selector(compare:)])
        [md appendFormat:@"- %@: %lu\n", s, (unsigned long)[secCounts countForObject:s]];
    [md appendString:@"\nPHY / generation:\n"];
    for (NSString *p in [phyCounts.allObjects sortedArrayUsingSelector:@selector(compare:)])
        [md appendFormat:@"- %@: %lu\n", p, (unsigned long)[phyCounts countForObject:p]];
    [md appendString:@"\n"];
}

// Generic inventory section (uses each model's -redactedDescriptionWithSettings:
// when redaction is on, else a description that may include raw identifiers).
- (void)appendInventory:(NSMutableString *)md
                  title:(NSString *)title
                  items:(NSArray *)items {
    [md appendFormat:@"## %@\n\n", title];
    if (items.count == 0) { [md appendString:@"_None._\n\n"]; return; }
    KMRedactionSettings *r = [self effectiveRedaction];
    for (id item in items) {
        NSString *line = nil;
        if ([item respondsToSelector:@selector(redactedDescriptionWithSettings:)]) {
            line = [(id<KMRedactableDescription>)item redactedDescriptionWithSettings:r];
        } else {
            line = [item description];
        }
        [md appendFormat:@"- %@\n", line ?: @"?"];
    }
    [md appendFormat:@"\n_Count: %lu_\n\n", (unsigned long)items.count];
}

// LAN services (S3.3) + local interfaces (S3.4).
- (void)appendLAN:(NSMutableString *)md {
    [self appendInventory:md title:@"LAN hosts & services (Bonjour)" items:self.lanServices ?: @[]];
    [self appendInventory:md title:@"Local network interfaces" items:self.networkInterfaces ?: @[]];
}

- (void)appendNativeSurfaces:(NSMutableString *)md {
    [self appendInventory:md title:@"BLE devices" items:self.bleDevices ?: @[]];
    [self appendInventory:md title:@"USB devices" items:self.usbDevices ?: @[]];
    [self appendInventory:md title:@"HID devices" items:self.hidDevices ?: @[]];
    [self appendInventory:md title:@"Serial devices" items:self.serialDevices ?: @[]];
}

// Capture / evidence files.
- (void)appendCaptureFiles:(NSMutableString *)md {
    [md appendString:@"## Capture & evidence files\n\n"];
    if (self.captureFiles.count == 0) { [md appendString:@"_None._\n\n"]; return; }
    for (NSString *p in self.captureFiles)
        [md appendFormat:@"- `%@`\n", [p lastPathComponent]];
    [md appendString:@"\n"];
}

// MacBook capability result (from the S1.1 probe) — READ verbatim.
- (void)appendHardwareResult:(NSMutableString *)md {
    [md appendString:@"## MacBook capability result\n\n"];
    KMHardwareProbe *p = self.hardwareProbe;
    if (!p) { [md appendString:@"_No probe result._\n\n"]; return; }
    [md appendFormat:@"- Model: %@\n- macOS: %@\n- Architecture: %@\n- Build: %@\n\n",
        p.hardwareModel ?: @"?", p.osVersion ?: @"?", p.architecture ?: @"?", p.appBuild ?: @"?"];
    NSArray<KMHardwareCapability *> *caps = p.capabilities;
    if (caps.count == 0) { [md appendString:@"_No hardware capabilities recorded._\n\n"]; return; }
    [md appendString:@"| Capability | Status | Reason |\n|------------|--------|--------|\n"];
    for (KMHardwareCapability *hc in caps) {
        [md appendFormat:@"| %@ | %@ | %@ |\n",
            hc.key ?: @"?",
            KMStringFromCapabilityStatus(hc.status),
            hc.reason.length ? hc.reason : @"-"];
    }
    [md appendString:@"\n"];
}

// Capabilities & blocked features — READ straight from the capability engine.
- (void)appendCapabilities:(NSMutableString *)md {
    [md appendString:@"## Capabilities & blocked features\n\n"];
    KMCapabilityEngine *eng = self.capabilityEngine;
    if (!eng) { [md appendString:@"_No capability engine provided._\n\n"]; return; }
    NSArray<KMCapability *> *all = [eng allCapabilities];
    NSMutableString *avail = [NSMutableString string];
    NSMutableString *blocked = [NSMutableString string];
    for (KMCapability *cap in all) {
        if (cap.isAvailable) {
            [avail appendFormat:@"- %@\n", cap.key];
        } else {
            // Every blocked feature carries an explicit reason + explanation.
            [blocked appendFormat:@"- **%@** — %@ (%@)\n",
                cap.key,
                KMStringFromCapabilityReason(cap.reason),
                cap.explanation.length ? cap.explanation : @"-"];
        }
    }
    [md appendString:@"### Available\n\n"];
    [md appendString:avail.length ? avail : @"_None._\n"];
    [md appendString:@"\n### Unsupported / blocked (with reasons)\n\n"];
    [md appendString:blocked.length ? blocked : @"_None._\n"];
    [md appendString:@"\n"];
}

// Evidence timeline with source labels.
- (void)appendEvidenceTimeline:(NSMutableString *)md {
    [md appendString:@"## Evidence timeline\n\n"];
    NSMutableArray<KMEvidenceEntry *> *entries = [NSMutableArray array];

    // Auto-derive per-network first/last-seen entries with the correct source.
    WaveContainer *c = self.container;
    for (NSUInteger i = 0; c && i < [c count]; ++i) {
        WaveNet *net = [c netAtIndex:i];
        KMEvidenceSource src = [net liveCaptured] ? KMEvidenceSourceCoreWLAN : KMEvidenceSourcePcap;
        NSString *label = [NSString stringWithFormat:@"%@ %@",
                           [self redactSSID:[net SSID] ?: @""],
                           [self redactMAC:[net BSSID] ?: @""]];
        [entries addObject:[KMEvidenceEntry entryWithDate:[net firstSeenDate] source:src
                                                   detail:[@"first seen: " stringByAppendingString:label]]];
        [entries addObject:[KMEvidenceEntry entryWithDate:[net lastSeenDate] source:src
                                                   detail:[@"last seen: " stringByAppendingString:label]]];
    }
    if (self.additionalEvidence.count)
        [entries addObjectsFromArray:self.additionalEvidence];

    if (entries.count == 0) { [md appendString:@"_No timeline entries._\n\n"]; return; }

    [entries sortUsingComparator:^NSComparisonResult(KMEvidenceEntry *a, KMEvidenceEntry *b) {
        NSDate *da = a.timestamp ?: [NSDate distantPast];
        NSDate *db = b.timestamp ?: [NSDate distantPast];
        return [da compare:db];
    }];

    [md appendString:@"| Time (UTC) | Source | Detail |\n|------------|--------|--------|\n"];
    for (KMEvidenceEntry *e in entries) {
        [md appendFormat:@"| %@ | %@ | %@ |\n",
            [self isoString:e.timestamp],
            KMStringFromEvidenceSource(e.source),
            e.detail ?: @""];
    }
    [md appendString:@"\n"];
}

#pragma mark - Generation

- (NSString *)generateMarkdown {
    NSMutableString *md = [NSMutableString string];
    [self appendHeader:md];
    [self appendNetworks:md];
    [self appendClients:md];
    [self appendProtocolPosture:md];
    [self appendLAN:md];
    [self appendNativeSurfaces:md];
    [self appendCaptureFiles:md];
    [self appendHardwareResult:md];
    [self appendCapabilities:md];
    [self appendEvidenceTimeline:md];
    return [md copy];
}

- (BOOL)writeMarkdownToFile:(NSString *)path error:(NSError **)error {
    // LOCAL-ONLY: this is a local artifact, never an off-device export.
    NSString *md = [self generateMarkdown];
    return [md writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

#pragma mark - Self-test

+ (BOOL)runSelfTestLogging {
    return [KMReportSelfTest runSelfTestLogging];
}

@end
