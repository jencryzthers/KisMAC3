/*
 File:        KMCapability.h
 Program:     KisMac3
 Slice:       S1.3 - Capability engine core

 Description: Feature-capability descriptor. This is the value object the
              KMCapabilityEngine produces for every capability in the
              Milestone 3 list. It carries:
                - a stable capability key (one of the KMFeature* constants),
                - an availability state (available / unavailable /
                  unknownRequiresActiveProbe),
                - an unavailable-reason matching Milestone 3's six reasons
                  (plus a "none" sentinel for the available case and an
                  "unknown" sentinel for the requires-active-probe case),
                - a human-readable explanation, and a dictionary representation.

 INVARIANT: a capability is never silently "available". Every non-available
            (and unknown) state MUST carry an explicit reason + explanation.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Capability keys (Milestone 3 list)

/// Stable, string-backed feature keys. These are the canonical Milestone 3
/// capability identifiers used by the UI and drivers to query the engine.
extern NSString * const KMFeatureScan;
extern NSString * const KMFeaturePassiveCapture;
extern NSString * const KMFeaturePcapImport;
extern NSString * const KMFeaturePcapExport;
extern NSString * const KMFeatureChannelSwitching;
extern NSString * const KMFeatureMonitorMode;
extern NSString * const KMFeatureAPMode;
extern NSString * const KMFeatureFrameInjection;
extern NSString * const KMFeatureDeauth;
extern NSString * const KMFeatureHandshakeCapture;
extern NSString * const KMFeatureKismetRemoteCapture;
extern NSString * const KMFeatureGPS;
extern NSString * const KMFeatureMapPlotting;
extern NSString * const KMFeatureLANDiscovery;
extern NSString * const KMFeatureBonjourInventory;
extern NSString * const KMFeatureBLEScan;
extern NSString * const KMFeatureBLEGattEnumeration;
extern NSString * const KMFeatureUSBInventory;
extern NSString * const KMFeatureHIDInventory;
extern NSString * const KMFeatureSerialInventory;
extern NSString * const KMFeatureWiFi6Decode;
extern NSString * const KMFeatureWPA3Decode;
extern NSString * const KMFeatureOWEDecode;
extern NSString * const KMFeatureEnterpriseDecode;
extern NSString * const KMFeatureSubGhzExternalModule;
extern NSString * const KMFeatureNFCExternalModule;
extern NSString * const KMFeatureRFIDExternalModule;
extern NSString * const KMFeatureIRExternalModule;
extern NSString * const KMFeatureIButtonExternalModule;

/// The complete, ordered Milestone 3 capability key list.
extern NSArray<NSString *> *KMAllFeatureKeys(void);

#pragma mark - Availability state

/// Three-valued availability. The engine fails CLOSED: anything not provably
/// available is unavailable (or, for disruptive ops that were never executed,
/// unknownRequiresActiveProbe). The UI must treat both non-available states
/// as "do not enable".
typedef NS_ENUM(NSInteger, KMCapabilityAvailability) {
    /// Feature is available to use right now.
    KMCapabilityAvailable = 0,
    /// Feature is not available; see -reason for why.
    KMCapabilityUnavailable,
    /// Feature could not be determined without a disruptive, user-consented
    /// active probe (e.g. monitor mode would drop the Wi-Fi link). Treated as
    /// NOT available by the UI until a consented active probe resolves it.
    KMCapabilityUnknownRequiresActiveProbe
};

#pragma mark - Unavailable reason (Milestone 3's six reasons)

/// Why a capability is unavailable (or unknown). The six concrete reasons are
/// exactly Milestone 3's list; two sentinels frame the available/unknown ends.
typedef NS_ENUM(NSInteger, KMCapabilityReason) {
    /// Sentinel: the capability is available; no blocking reason.
    KMCapabilityReasonNone = 0,
    /// A required permission has not been granted (Location, Bluetooth, ...).
    KMCapabilityReasonPermissionMissing,
    /// The built-in MacBook hardware does not provide this.
    KMCapabilityReasonUnsupportedMacBookHardware,
    /// Requires an external adapter that is not present.
    KMCapabilityReasonUnsupportedAdapter,
    /// Modern macOS blocks this on built-in hardware.
    KMCapabilityReasonMacOSBlocked,
    /// The protocol decoder/parser for this feature does not exist yet.
    KMCapabilityReasonProtocolParserMissing,
    /// No active/authorized campaign scope is in effect (fail-closed for
    /// disruptive/offensive ops).
    KMCapabilityReasonActiveLabScopeMissing,
    /// Sentinel: state is unknownRequiresActiveProbe (see availability).
    KMCapabilityReasonUnknownRequiresActiveProbe
};

/// Stable, persistable token for an availability value.
extern NSString *KMStringFromCapabilityAvailability(KMCapabilityAvailability a);
/// Stable, persistable token for a reason value.
extern NSString *KMStringFromCapabilityReason(KMCapabilityReason r);

#pragma mark - KMCapability

@interface KMCapability : NSObject

/// Stable capability key (one of the KMFeature* constants).
@property (nonatomic, copy, readonly) NSString *key;
/// Three-valued availability state.
@property (nonatomic, assign, readonly) KMCapabilityAvailability availability;
/// Why it is (un)available. KMCapabilityReasonNone iff available.
@property (nonatomic, assign, readonly) KMCapabilityReason reason;
/// Human-readable explanation. Always non-empty for non-available states.
@property (nonatomic, copy, readonly) NSString *explanation;

/// Convenience: YES iff availability == KMCapabilityAvailable.
@property (nonatomic, assign, readonly) BOOL isAvailable;

+ (instancetype)capabilityWithKey:(NSString *)key
                     availability:(KMCapabilityAvailability)availability
                           reason:(KMCapabilityReason)reason
                      explanation:(NSString *)explanation;

/// Convenience constructors for the two common cases.
+ (instancetype)availableCapabilityWithKey:(NSString *)key
                               explanation:(NSString *)explanation;
+ (instancetype)unavailableCapabilityWithKey:(NSString *)key
                                      reason:(KMCapabilityReason)reason
                                 explanation:(NSString *)explanation;

/// Persistable dictionary representation (stable string keys/values).
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
