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

// S7.1 campaign/lab section inputs.
#import "../Lab/KMLabEvent.h"
#import "../Lab/KMLabEventLog.h"
#import "../Lab/KMLabAPProfile.h"
#import "../Lab/KMLabWorkflow.h"   // KMLabScopeChecking
#import "../Safety/KMCampaignManager.h"
#import "../Safety/KMAuditLog.h"
#import "../Campaigns/KMCampaign.h"
#import "../Campaigns/KMCampaignScope.h"

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

#pragma mark - Campaign / lab section (S7.1)

// Renders the authorized-lab section: scope summary, lab event-log summary,
// handshakes observed, AP-profile usability, the active-op attempts/refusals
// drawn from the audit log, and an explicit LIMITATIONS block. Redaction-aware.
// Emitted ONLY when there is some lab input (event log / profiles / manager).
- (void)appendCampaignLab:(NSMutableString *)md {
    BOOL haveLab = (self.labEventLog != nil) || (self.labAPProfiles.count > 0) ||
                   (self.campaignManager != nil);
    if (!haveLab) return;

    KMRedactionSettings *r = [self effectiveRedaction];
    [md appendString:@"## Authorized lab (campaign)\n\n"];

    // --- Scope summary -----------------------------------------------------
    [md appendString:@"### Scope summary\n\n"];
    KMCampaign *camp = self.campaignManager.currentCampaign;
    if (camp) {
        [md appendFormat:@"- Campaign: **%@**\n", camp.label ?: @"(unnamed)"];
        [md appendFormat:@"- Authorized: **%@**\n", camp.isAuthorized ? @"yes" : @"NO"];
        [md appendFormat:@"- Active now: **%@**\n", [camp isActive] ? @"yes" : @"no"];
        [md appendFormat:@"- Emergency stop: **%@**\n",
            self.campaignManager.isEmergencyStopped ? @"ENGAGED" : @"not engaged"];
        // contextSummary is counts + window only -- it does NOT dump raw lists.
        [md appendFormat:@"- Scope: %@\n", [camp.scope contextSummary] ?: @"-"];
        if (!camp.isActive && [camp inactiveReason].length)
            [md appendFormat:@"- Inactive reason: %@\n", [camp inactiveReason]];
    } else {
        [md appendString:@"_No active campaign (active lab operations fail closed)._\n"];
    }
    [md appendString:@"\n"];

    // --- Lab event-log summary --------------------------------------------
    [md appendString:@"### Event log (passive, imported)\n\n"];
    KMLabEventLog *log = self.labEventLog;
    if (log && [log count] > 0) {
        [md appendString:@"| Event type | Count |\n|------------|-------|\n"];
        KMLabEventType order[] = {
            KMLabEventTypeProbeRequest, KMLabEventTypeProbeResponse,
            KMLabEventTypeAuthentication,
            KMLabEventTypeAssociationRequest, KMLabEventTypeAssociationResponse,
            KMLabEventTypeReassociationRequest, KMLabEventTypeReassociationResponse,
            KMLabEventTypeDisassociation, KMLabEventTypeDeauthentication,
            KMLabEventTypeEAPOLHandshake,
        };
        for (size_t i = 0; i < sizeof(order)/sizeof(order[0]); i++) {
            NSUInteger n = [log countOfType:order[i]];
            if (n) [md appendFormat:@"| %@ | %lu |\n", KMStringFromLabEventType(order[i]), (unsigned long)n];
        }
        [md appendFormat:@"\n_Total events: %lu — handshakes observed: %lu_\n\n",
            (unsigned long)[log count], (unsigned long)[log handshakeCount]];
    } else {
        [md appendString:@"_No lab events (no imported management frames)._\n\n"];
    }

    // --- Lab AP profiles (owned test networks) ----------------------------
    if (self.labAPProfiles.count) {
        [md appendString:@"### Lab AP profiles (owned test networks)\n\n"];
        [md appendString:@"| Profile | Usable (in scope) |\n|---------|-------------------|\n"];
        for (KMLabAPProfile *p in self.labAPProfiles) {
            BOOL usable = [p isUsableWithScopeProvider:self.labScopeProvider];
            [md appendFormat:@"| %@ | %@ |\n",
                [p redactedDescriptionWithSettings:r], usable ? @"yes" : @"no (out of scope)"];
        }
        [md appendString:@"\n"];
    }

    // --- Active-op attempts / refusals (from the audit log) ----------------
    [md appendString:@"### Active-operation attempts (audit log)\n\n"];
    NSArray<NSDictionary *> *entries = [self.campaignManager.auditLog readCurrentEntries];
    NSUInteger permitted = 0, refused = 0;
    NSMutableString *rows = [NSMutableString string];
    for (NSDictionary *e in entries) {
        if (![e[@"action"] isEqual:KMAuditActionActiveOperation]) continue;
        id ctx = e[@"context"];
        BOOL allowed = NO;
        NSString *op = @"", *reason = @"";
        if ([ctx isKindOfClass:[NSDictionary class]]) {
            allowed = [ctx[@"allowed"] boolValue] || [ctx[@"inScope"] boolValue];
            op = ctx[@"operation"] ?: @"";
            reason = ctx[@"reason"] ?: @"";
        }
        if (allowed) permitted++; else refused++;
        NSString *tsStr = [e[@"ts"] isKindOfClass:[NSString class]] ? e[@"ts"] : @"-";
        [rows appendFormat:@"| %@ | %@ | %@ | %@ |\n",
            tsStr,
            op.length ? op : @"?", allowed ? @"permitted" : @"REFUSED",
            reason.length ? reason : @"-"];
    }
    [md appendFormat:@"_Attempts: %lu — permitted: %lu — refused: %lu_\n\n",
        (unsigned long)(permitted + refused), (unsigned long)permitted, (unsigned long)refused];
    if (rows.length) {
        [md appendString:@"| Time (UTC) | Operation | Decision | Reason |\n"];
        [md appendString:@"|------------|-----------|----------|--------|\n"];
        [md appendString:rows];
        [md appendString:@"\n"];
    }

    // --- Limitations (explicit; what is unsupported / hardware-required) ----
    [md appendString:@"### Limitations\n\n"];
    [md appendString:
        @"- **AP-simulation / evil-twin**: NOT implemented. No transmit/AP code exists on "
        @"this build; requires external injection-capable hardware and a future consented "
        @"active-probe. The workflow gates + audits the request, then refuses (fail-closed).\n"
        @"- **Captive-portal hosting**: NOT implemented (same as above). Policy stub only.\n"
        @"- **Deauthentication / frame injection**: gated + audited here, but EXECUTION still "
        @"requires an external injection-capable adapter (built-in MacBook Wi-Fi cannot "
        @"transmit) and an authorized, in-window campaign scope. Without those, every request "
        @"is refused.\n"
        @"- **Event log**: PASSIVE evidence parsed from IMPORTED captures only — no live radio, "
        @"monitor mode, or channel switching is used to produce it.\n"
        @"- **Lab UI / live visualization / module system**: deferred (S5.x / Milestone 13).\n\n"];
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
    [self appendCampaignLab:md];   // S7.1 campaign/lab section + limitations
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
