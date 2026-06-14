/*
 File:        KMHardwareCapability.h
 Program:     KisMac3
 Slice:       S1.1 - MacBook hardware capability probe

 Description: Value object describing a single hardware/OS capability as
              determined by KMHardwareProbe. A capability carries a stable
              key, a concrete status, and a human-readable reason. There is
              never a "guessed" status: every capability is one of the
              KMCapabilityStatus values below, each with an explicit reason.

 This file is part of KisMAC.

 KisMAC is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License, version 2,
 as published by the Free Software Foundation.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Concrete capability status. No value means "guessed / assumed yes".
/// Disruptive capabilities that we deliberately did NOT execute (monitor
/// mode, channel switch, AP, injection) are reported as
/// KMCapabilityStatusUnknownRequiresActiveProbe, never as a fabricated yes/no.
typedef NS_ENUM(NSInteger, KMCapabilityStatus) {
    /// Verified available on this machine/OS right now.
    KMCapabilityStatusSupported = 0,
    /// Verified NOT available (hardware/OS does not provide it).
    KMCapabilityStatusUnsupported,
    /// The API exists but a required permission has not been granted.
    KMCapabilityStatusPermissionMissing,
    /// Modern macOS blocks this on built-in hardware.
    KMCapabilityStatusMacOSBlocked,
    /// Could not be determined without a disruptive, user-initiated active
    /// probe (e.g. monitor mode would drop the Wi-Fi link). Reported, not run.
    KMCapabilityStatusUnknownRequiresActiveProbe
};

/// Stable capability keys (string-backed for stable persistence).
extern NSString * const KMCapWiFiInterfacePresent;
extern NSString * const KMCapLocationAuthorization;
extern NSString * const KMCapCoreWLANScan;
extern NSString * const KMCapBand24GHz;
extern NSString * const KMCapBand5GHz;
extern NSString * const KMCapBand6GHz;
extern NSString * const KMCapPHYMetadata;
extern NSString * const KMCapPcapOpen;
extern NSString * const KMCapDatalinkEnumeration;
extern NSString * const KMCapMonitorCapture;
extern NSString * const KMCapChannelSwitching;
extern NSString * const KMCapAPMode;
extern NSString * const KMCapFrameInjection;

/// Returns a stable, persistable token for a status value.
extern NSString *KMStringFromCapabilityStatus(KMCapabilityStatus status);

@interface KMHardwareCapability : NSObject

/// Stable capability key (one of the KMCap* constants).
@property (nonatomic, copy, readonly) NSString *key;
/// Concrete status. Never absent.
@property (nonatomic, assign, readonly) KMCapabilityStatus status;
/// Human-readable explanation of WHY the status is what it is.
@property (nonatomic, copy, readonly) NSString *reason;
/// Optional remediation text (e.g. how to grant Location).
@property (nonatomic, copy, readonly, nullable) NSString *remediation;

+ (instancetype)capabilityWithKey:(NSString *)key
                           status:(KMCapabilityStatus)status
                           reason:(NSString *)reason;

+ (instancetype)capabilityWithKey:(NSString *)key
                           status:(KMCapabilityStatus)status
                           reason:(NSString *)reason
                      remediation:(nullable NSString *)remediation;

/// Persistable dictionary representation (stable string keys/values).
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
