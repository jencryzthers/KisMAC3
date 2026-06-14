/*
 File:        KMCapabilityEngine.m
 Program:     KisMac3
 Slice:       S1.3 - Capability engine core

 This file is part of KisMAC. GPL v2.
 */

#import "KMCapabilityEngine.h"
#import "KMHardwareProbe.h"

/// Concrete scope provider used only by the self-test (reports active scope).
@interface KMSelfTestScopeProvider : NSObject <KMActiveScopeProviding>
@end

#pragma mark - Scope provider stub

@implementation KMNoActiveScopeProvider
- (BOOL)hasActiveScope { return NO; }
@end

#pragma mark - Protocol parser registry

@interface KMProtocolParserRegistry ()
@property (nonatomic, strong) NSMutableSet<NSString *> *present;
@end

@implementation KMProtocolParserRegistry

- (instancetype)init {
    if ((self = [super init])) {
        _present = [NSMutableSet set];
    }
    return self;
}

- (BOOL)hasParserForFeature:(NSString *)featureKey {
    return featureKey != nil && [self.present containsObject:featureKey];
}

- (void)registerParserForFeature:(NSString *)featureKey {
    if (featureKey) [self.present addObject:featureKey];
}

+ (instancetype)defaultRegistry {
    // S2.1 DONE: the KMProtocolMetadata decoder parses RSN/WPA IEs and
    // HT/VHT/HE/EHT capability elements from imported management frames, so the
    // modern decode capabilities are now AVAILABLE (offline/imported-pcap
    // decode -- not a claim of live monitor capture). Only register what we
    // actually decode: WPA3 (SAE/transition/enterprise), OWE, Enterprise
    // (802.1X EAP), and Wi-Fi 6/6E/7 PHY generation.
    KMProtocolParserRegistry *reg = [[self alloc] init];
    [reg registerParserForFeature:KMFeatureWPA3Decode];
    [reg registerParserForFeature:KMFeatureOWEDecode];
    [reg registerParserForFeature:KMFeatureEnterpriseDecode];
    [reg registerParserForFeature:KMFeatureWiFi6Decode];
    return reg;
}

@end

#pragma mark - Engine

@interface KMCapabilityEngine ()
/// Hardware facts keyed by S1.1 capability key for O(1) lookup.
@property (nonatomic, strong) NSDictionary<NSString *, KMHardwareCapability *> *hardwareByKey;
@property (nonatomic, strong) id<KMActiveScopeProviding> scopeProvider;
@property (nonatomic, strong) KMProtocolParserRegistry *parserRegistry;
@end

@implementation KMCapabilityEngine

#pragma mark Init

- (instancetype)initWithHardwareCapabilities:(NSArray<KMHardwareCapability *> *)hardware
                               scopeProvider:(id<KMActiveScopeProviding>)scopeProvider
                             parserRegistry:(KMProtocolParserRegistry *)parserRegistry {
    if ((self = [super init])) {
        NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
        for (KMHardwareCapability *cap in hardware) {
            if (cap.key) byKey[cap.key] = cap;
        }
        _hardwareByKey   = [byKey copy];
        _scopeProvider   = scopeProvider ?: [[KMNoActiveScopeProvider alloc] init];
        _parserRegistry  = parserRegistry ?: [KMProtocolParserRegistry defaultRegistry];
    }
    return self;
}

- (instancetype)initWithProbe:(KMHardwareProbe *)probe {
    return [self initWithHardwareCapabilities:probe.capabilities
                                scopeProvider:nil
                              parserRegistry:nil];
}

- (instancetype)initWithProbe:(KMHardwareProbe *)probe
                scopeProvider:(id<KMActiveScopeProviding>)scopeProvider {
    return [self initWithHardwareCapabilities:probe.capabilities
                                scopeProvider:scopeProvider
                              parserRegistry:nil];
}

- (instancetype)initWithLiveProbe {
    KMHardwareProbe *probe = [[KMHardwareProbe alloc] init];
    [probe runProbe];
    return [self initWithProbe:probe];
}

#pragma mark Hardware-fact helpers

/// Returns the S1.1 status for a hardware key, or a sentinel if absent.
/// Absence is treated as "unknown" so the engine fails closed rather than
/// inventing support.
- (KMCapabilityStatus)hardwareStatusForKey:(NSString *)key
                                   present:(BOOL *)present {
    KMHardwareCapability *cap = self.hardwareByKey[key];
    if (cap) {
        if (present) *present = YES;
        return cap.status;
    }
    if (present) *present = NO;
    return KMCapabilityStatusUnknownRequiresActiveProbe;
}

- (NSString *)hardwareReasonForKey:(NSString *)key fallback:(NSString *)fallback {
    KMHardwareCapability *cap = self.hardwareByKey[key];
    if (cap.reason.length) return cap.reason;
    return fallback;
}

- (BOOL)locationAuthorized {
    BOOL present = NO;
    return [self hardwareStatusForKey:KMCapLocationAuthorization present:&present]
               == KMCapabilityStatusSupported && present;
}

- (BOOL)wifiInterfacePresent {
    BOOL present = NO;
    return [self hardwareStatusForKey:KMCapWiFiInterfacePresent present:&present]
               == KMCapabilityStatusSupported && present;
}

- (BOOL)hasActiveScope {
    return [self.scopeProvider hasActiveScope];
}

#pragma mark Public API

- (BOOL)isAvailable:(NSString *)featureKey {
    return [self availabilityForCapability:featureKey].isAvailable;
}

- (NSArray<KMCapability *> *)allCapabilities {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in KMAllFeatureKeys()) {
        [out addObject:[self availabilityForCapability:key]];
    }
    return out;
}

- (KMCapability *)availabilityForCapability:(NSString *)featureKey {
    // -------- Offline features: always available --------
    if ([featureKey isEqualToString:KMFeaturePcapImport]) {
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"Offline pcap import works without any radio or permission."];
    }
    if ([featureKey isEqualToString:KMFeaturePcapExport]) {
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"Offline pcap export works without any radio or permission."];
    }

    // -------- scan --------
    if ([featureKey isEqualToString:KMFeatureScan]) {
        if (![self wifiInterfacePresent]) {
            return [KMCapability unavailableCapabilityWithKey:featureKey
                reason:KMCapabilityReasonUnsupportedMacBookHardware
                explanation:@"No usable Wi-Fi interface was reported by the hardware probe."];
        }
        if (![self locationAuthorized]) {
            return [KMCapability unavailableCapabilityWithKey:featureKey
                reason:KMCapabilityReasonPermissionMissing
                explanation:@"Active scan requires Location authorization to reveal BSSIDs."];
        }
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"Wi-Fi interface present and Location authorized."];
    }

    // -------- passiveCapture (gated on pcap.open) --------
    if ([featureKey isEqualToString:KMFeaturePassiveCapture]) {
        BOOL present = NO;
        KMCapabilityStatus pcap = [self hardwareStatusForKey:KMCapPcapOpen present:&present];
        if (pcap == KMCapabilityStatusSupported) {
            return [KMCapability availableCapabilityWithKey:featureKey
                explanation:@"BPF device can be opened for passive capture."];
        }
        if (pcap == KMCapabilityStatusPermissionMissing) {
            return [KMCapability unavailableCapabilityWithKey:featureKey
                reason:KMCapabilityReasonPermissionMissing
                explanation:[self hardwareReasonForKey:KMCapPcapOpen
                    fallback:@"Opening the BPF device was denied; grant capture permission."]];
        }
        if (pcap == KMCapabilityStatusMacOSBlocked) {
            return [KMCapability unavailableCapabilityWithKey:featureKey
                reason:KMCapabilityReasonMacOSBlocked
                explanation:[self hardwareReasonForKey:KMCapPcapOpen
                    fallback:@"Modern macOS blocks raw BPF capture on this configuration."]];
        }
        // Unsupported / unknown / absent -> hardware can't do it.
        return [KMCapability unavailableCapabilityWithKey:featureKey
            reason:KMCapabilityReasonUnsupportedMacBookHardware
            explanation:[self hardwareReasonForKey:KMCapPcapOpen
                fallback:@"Passive capture is unavailable on this hardware/OS."]];
    }

    // -------- Disruptive PASSIVE-ish radio ops on built-in --------
    // monitorMode / channelSwitching / handshakeCapture: the probe reports the
    // underlying hardware op as unknownRequiresActiveProbe (we never executed
    // it). Fail closed as unknownRequiresActiveProbe until a consented probe.
    if ([featureKey isEqualToString:KMFeatureMonitorMode]) {
        return [KMCapability capabilityWithKey:featureKey
            availability:KMCapabilityUnknownRequiresActiveProbe
            reason:KMCapabilityReasonUnknownRequiresActiveProbe
            explanation:@"Built-in monitor mode was not exercised; requires a user-consented active probe."];
    }
    if ([featureKey isEqualToString:KMFeatureChannelSwitching]) {
        return [KMCapability capabilityWithKey:featureKey
            availability:KMCapabilityUnknownRequiresActiveProbe
            reason:KMCapabilityReasonUnknownRequiresActiveProbe
            explanation:@"Channel switching was not exercised; requires a user-consented active probe."];
    }
    if ([featureKey isEqualToString:KMFeatureHandshakeCapture]) {
        return [KMCapability capabilityWithKey:featureKey
            availability:KMCapabilityUnknownRequiresActiveProbe
            reason:KMCapabilityReasonUnknownRequiresActiveProbe
            explanation:@"Handshake capture depends on monitor mode, which requires a user-consented active probe."];
    }

    // -------- Active / offensive ops: fail closed on scope --------
    // apMode / frameInjection / deauth: even if hardware allowed, these stay
    // unavailable while no campaign scope is in effect (dominant reason). On
    // built-in MacBook hardware they are also unsupported per parity, but
    // activeLabScopeMissing is the policy gate we report first.
    if ([featureKey isEqualToString:KMFeatureAPMode] ||
        [featureKey isEqualToString:KMFeatureFrameInjection] ||
        [featureKey isEqualToString:KMFeatureDeauth]) {
        if (![self hasActiveScope]) {
            return [KMCapability unavailableCapabilityWithKey:featureKey
                reason:KMCapabilityReasonActiveLabScopeMissing
                explanation:@"No authorized campaign scope is in effect; active/offensive operations are disabled (fail-closed)."];
        }
        // With scope, the built-in still can't do AP/injection per parity.
        return [KMCapability unavailableCapabilityWithKey:featureKey
            reason:KMCapabilityReasonUnsupportedMacBookHardware
            explanation:@"Built-in Wi-Fi cannot perform AP/injection; an external adapter is required."];
    }

    // -------- Kismet remote capture --------
    // S2.4: the remote Kismet/drone transport is modernized onto
    // Network.framework (plaintext TCP). The backend depends on NO local
    // MacBook radio/permission -- it ingests networks from a user-supplied
    // remote server -- so it is AVAILABLE as a user-initiated remote source.
    // The actual connect is attempted only when the user starts the driver and
    // fails CLOSED with a clear reason if the server is unreachable (no silent
    // failure). HONESTY: this speaks the LEGACY (~2006) *NETWORK:/drone binary
    // protocol only; it does NOT talk to modern Kismet 3.x (REST/websocket/JSON
    // over TLS) -- that adapter is a separate future slice needing a live
    // server to validate.
    if ([featureKey isEqualToString:KMFeatureKismetRemoteCapture]) {
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"Remote Kismet backend (legacy plaintext protocol) available; "
                        @"connection is user-initiated and fails closed if the server is unreachable. "
                        @"Modern Kismet 3.x is not supported (separate future slice)."];
    }

    // -------- GPS / map plotting: data path exists --------
    if ([featureKey isEqualToString:KMFeatureGPS]) {
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"GPS data path (CoreLocation / serial NMEA) is available."];
    }
    if ([featureKey isEqualToString:KMFeatureMapPlotting]) {
        return [KMCapability availableCapabilityWithKey:featureKey
            explanation:@"Map plotting works against available position data."];
    }

    // -------- MacBook-native surfaces: not yet implemented (S3.x) --------
    if ([featureKey isEqualToString:KMFeatureBLEScan] ||
        [featureKey isEqualToString:KMFeatureBLEGattEnumeration]) {
        return [KMCapability unavailableCapabilityWithKey:featureKey
            reason:KMCapabilityReasonPermissionMissing
            explanation:@"Bluetooth surface not yet implemented (S3.x) and no Bluetooth authorization wired."];
    }
    if ([featureKey isEqualToString:KMFeatureLANDiscovery] ||
        [featureKey isEqualToString:KMFeatureBonjourInventory] ||
        [featureKey isEqualToString:KMFeatureUSBInventory] ||
        [featureKey isEqualToString:KMFeatureHIDInventory] ||
        [featureKey isEqualToString:KMFeatureSerialInventory]) {
        return [KMCapability capabilityWithKey:featureKey
            availability:KMCapabilityUnknownRequiresActiveProbe
            reason:KMCapabilityReasonUnknownRequiresActiveProbe
            explanation:@"Native surface not yet implemented (S3.x)."];
    }

    // -------- Modern protocol decoders: parser missing (S2.1) --------
    if ([featureKey isEqualToString:KMFeatureWiFi6Decode] ||
        [featureKey isEqualToString:KMFeatureWPA3Decode] ||
        [featureKey isEqualToString:KMFeatureOWEDecode] ||
        [featureKey isEqualToString:KMFeatureEnterpriseDecode]) {
        if ([self.parserRegistry hasParserForFeature:featureKey]) {
            return [KMCapability availableCapabilityWithKey:featureKey
                explanation:@"A decoder for this protocol is registered."];
        }
        return [KMCapability unavailableCapabilityWithKey:featureKey
            reason:KMCapabilityReasonProtocolParserMissing
            explanation:@"The modern protocol decoder is not implemented yet (S2.1)."];
    }

    // -------- External-module hardware: requires an adapter --------
    if ([featureKey isEqualToString:KMFeatureSubGhzExternalModule] ||
        [featureKey isEqualToString:KMFeatureNFCExternalModule] ||
        [featureKey isEqualToString:KMFeatureRFIDExternalModule] ||
        [featureKey isEqualToString:KMFeatureIRExternalModule] ||
        [featureKey isEqualToString:KMFeatureIButtonExternalModule]) {
        return [KMCapability unavailableCapabilityWithKey:featureKey
            reason:KMCapabilityReasonUnsupportedAdapter
            explanation:@"Requires an external hardware module; never available on a MacBook alone."];
    }

    // -------- Unknown key: fail closed --------
    return [KMCapability capabilityWithKey:featureKey ?: @"<nil>"
        availability:KMCapabilityUnknownRequiresActiveProbe
        reason:KMCapabilityReasonUnknownRequiresActiveProbe
        explanation:@"Unknown capability key; failing closed."];
}

#pragma mark - Self-test (mocked-input verification)

/// Mocked S1.1 capability arrays for the test scenarios.
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

+ (NSArray<KMHardwareCapability *> *)mockLocationGrantedBpfDeniedHardware {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusSupported reason:@"mock iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusSupported reason:@"mock granted"],
        [KMHardwareCapability capabilityWithKey:KMCapPcapOpen
            status:KMCapabilityStatusPermissionMissing reason:@"mock /dev/bpf0 denied"],
    ];
}

+ (NSArray<KMHardwareCapability *> *)mockNoWiFiHardware {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusUnsupported reason:@"mock no iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusPermissionMissing reason:@"mock not determined"],
    ];
}

/// A scope provider that DOES have scope, to prove the gate flips.
+ (id<KMActiveScopeProviding>)scopedProvider {
    static dispatch_once_t once; static id<KMActiveScopeProviding> p;
    dispatch_once(&once, ^{
        // Tiny inline class via a block-backed object is awkward in ObjC;
        // use a private concrete class instead.
        p = (id<KMActiveScopeProviding>)[KMSelfTestScopeProvider new];
    });
    return p;
}

+ (BOOL)runSelfTestReturningFailures:(NSArray<NSString *> * _Nullable * _Nullable)outFailures {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];

    // Helper to assert a capability's availability + reason.
    BOOL (^check)(NSString *, KMCapabilityEngine *, NSString *,
                  KMCapabilityAvailability, KMCapabilityReason) =
    ^BOOL(NSString *scenario, KMCapabilityEngine *engine, NSString *featureKey,
          KMCapabilityAvailability wantAvail, KMCapabilityReason wantReason) {
        KMCapability *c = [engine availabilityForCapability:featureKey];
        BOOL ok = (c.availability == wantAvail) && (c.reason == wantReason);
        if (!ok) {
            [fail addObject:[NSString stringWithFormat:
                @"[%@] %@: got (%@/%@) want (%@/%@) -- %@",
                scenario, featureKey,
                KMStringFromCapabilityAvailability(c.availability),
                KMStringFromCapabilityReason(c.reason),
                KMStringFromCapabilityAvailability(wantAvail),
                KMStringFromCapabilityReason(wantReason),
                c.explanation]];
        }
        return ok;
    };

    // Scenario A: all green (Wi-Fi + Location + bpf), no scope, no parsers.
    KMCapabilityEngine *green =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockAllGreenHardware]
                                                   scopeProvider:nil
                                                 parserRegistry:nil];
    check(@"all-green", green, KMFeatureScan,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeaturePassiveCapture,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // Active op fails closed on scope even with green hardware.
    check(@"all-green", green, KMFeatureFrameInjection,
          KMCapabilityUnavailable, KMCapabilityReasonActiveLabScopeMissing);
    check(@"all-green", green, KMFeatureDeauth,
          KMCapabilityUnavailable, KMCapabilityReasonActiveLabScopeMissing);
    check(@"all-green", green, KMFeatureAPMode,
          KMCapabilityUnavailable, KMCapabilityReasonActiveLabScopeMissing);
    // Offline always works.
    check(@"all-green", green, KMFeaturePcapImport,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeaturePcapExport,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // S2.1: modern decoders are now registered in the default registry, so the
    // decode capabilities are available regardless of hardware (offline decode).
    check(@"all-green", green, KMFeatureWPA3Decode,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeatureWiFi6Decode,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeatureOWEDecode,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeatureEnterpriseDecode,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // Adapter-required.
    check(@"all-green", green, KMFeatureSubGhzExternalModule,
          KMCapabilityUnavailable, KMCapabilityReasonUnsupportedAdapter);
    check(@"all-green", green, KMFeatureNFCExternalModule,
          KMCapabilityUnavailable, KMCapabilityReasonUnsupportedAdapter);
    // Disruptive built-in -> unknown requires active probe.
    check(@"all-green", green, KMFeatureMonitorMode,
          KMCapabilityUnknownRequiresActiveProbe, KMCapabilityReasonUnknownRequiresActiveProbe);
    check(@"all-green", green, KMFeatureChannelSwitching,
          KMCapabilityUnknownRequiresActiveProbe, KMCapabilityReasonUnknownRequiresActiveProbe);
    check(@"all-green", green, KMFeatureHandshakeCapture,
          KMCapabilityUnknownRequiresActiveProbe, KMCapabilityReasonUnknownRequiresActiveProbe);
    // S2.4: remote Kismet backend is a user-initiated remote source -- available
    // independent of local radio/permission (legacy protocol only).
    check(@"all-green", green, KMFeatureKismetRemoteCapture,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // ...and still available even with NO Wi-Fi interface (it's remote).
    // (asserted again in the no-wifi scenario below)
    // Data paths.
    check(@"all-green", green, KMFeatureGPS,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"all-green", green, KMFeatureMapPlotting,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // Native surfaces.
    check(@"all-green", green, KMFeatureBLEScan,
          KMCapabilityUnavailable, KMCapabilityReasonPermissionMissing);
    check(@"all-green", green, KMFeatureLANDiscovery,
          KMCapabilityUnknownRequiresActiveProbe, KMCapabilityReasonUnknownRequiresActiveProbe);

    // Scenario B: Location granted + bpf DENIED.
    KMCapabilityEngine *bpfDenied =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockLocationGrantedBpfDeniedHardware]
                                                   scopeProvider:nil
                                                 parserRegistry:nil];
    check(@"bpf-denied", bpfDenied, KMFeatureScan,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    check(@"bpf-denied", bpfDenied, KMFeaturePassiveCapture,
          KMCapabilityUnavailable, KMCapabilityReasonPermissionMissing);

    // Scenario C: no Wi-Fi interface.
    KMCapabilityEngine *noWifi =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockNoWiFiHardware]
                                                   scopeProvider:nil
                                                 parserRegistry:nil];
    check(@"no-wifi", noWifi, KMFeatureScan,
          KMCapabilityUnavailable, KMCapabilityReasonUnsupportedMacBookHardware);
    // Offline still works with no radio at all.
    check(@"no-wifi", noWifi, KMFeaturePcapImport,
          KMCapabilityAvailable, KMCapabilityReasonNone);
    // S2.4: remote Kismet is independent of local radio -> still available.
    check(@"no-wifi", noWifi, KMFeatureKismetRemoteCapture,
          KMCapabilityAvailable, KMCapabilityReasonNone);

    // Scenario D: prove the scope gate flips when scope IS present + a parser
    // registered -- demonstrates results depend on injected inputs only.
    KMProtocolParserRegistry *reg = [[KMProtocolParserRegistry alloc] init];
    [reg registerParserForFeature:KMFeatureWPA3Decode];
    KMCapabilityEngine *scoped =
        [[KMCapabilityEngine alloc] initWithHardwareCapabilities:[self mockAllGreenHardware]
                                                   scopeProvider:[self scopedProvider]
                                                 parserRegistry:reg];
    // With scope, active op is no longer scope-blocked (built-in HW still
    // blocks it, but the reason flips off activeLabScopeMissing).
    check(@"scoped", scoped, KMFeatureFrameInjection,
          KMCapabilityUnavailable, KMCapabilityReasonUnsupportedMacBookHardware);
    // Registered parser makes the decode available.
    check(@"scoped", scoped, KMFeatureWPA3Decode,
          KMCapabilityAvailable, KMCapabilityReasonNone);

    if (outFailures) *outFailures = [fail copy];
    return fail.count == 0;
}

+ (BOOL)runSelfTestLogging {
    NSArray<NSString *> *failures = nil;
    BOOL pass = [self runSelfTestReturningFailures:&failures];
    if (pass) {
        NSLog(@"[KMCapabilityEngine self-test] PASS - all mocked-scenario assertions held (hardware-independent).");
    } else {
        NSLog(@"[KMCapabilityEngine self-test] FAIL - %lu assertion(s):",
              (unsigned long)failures.count);
        for (NSString *line in failures) {
            NSLog(@"[KMCapabilityEngine self-test]   %@", line);
        }
    }
    return pass;
}

@end

#pragma mark - Self-test scope provider

@implementation KMSelfTestScopeProvider
- (BOOL)hasActiveScope { return YES; }
@end
