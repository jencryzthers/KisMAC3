/*
 File:        KMCampaignScope.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: The explicit authorization SCOPE for an active-lab campaign
              (Milestone 9). A scope enumerates exactly what an authorized
              campaign is allowed to touch:
                - SSIDs       (network names)
                - BSSIDs      (AP MAC addresses)
                - client MACs (station MAC addresses)
                - adapters    (capture/inject adapter identifiers)
                - channels    (Wi-Fi channel numbers)
                - time window (start / end)

              Membership queries (is this BSSID / client / channel in scope?)
              let callers confirm a target is authorized BEFORE any active op.
              An EMPTY collection means "nothing of that kind is in scope" --
              it does NOT mean "everything". This is a FAIL-CLOSED model:
              membership requires an explicit match.

              Normalization: MAC/BSSID/SSID comparisons are case-insensitive
              and MAC separators are stripped, so "00:11:22:33:44:55",
              "00-11-22-33-44-55" and "001122334455" all match.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMCampaignScope : NSObject <NSSecureCoding, NSCopying>

/// Authorized network names. Empty => no SSID is in scope.
@property (nonatomic, copy, readonly) NSSet<NSString *> *ssids;
/// Authorized AP MAC addresses (BSSIDs). Empty => no BSSID is in scope.
@property (nonatomic, copy, readonly) NSSet<NSString *> *bssids;
/// Authorized client/station MAC addresses. Empty => no client is in scope.
@property (nonatomic, copy, readonly) NSSet<NSString *> *clientMACs;
/// Authorized adapter identifiers (e.g. "en0", a USB serial). Empty => none.
@property (nonatomic, copy, readonly) NSSet<NSString *> *adapters;
/// Authorized Wi-Fi channel numbers. Empty => no channel is in scope.
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *channels;

/// The authorized time window. A campaign is only ever active BETWEEN these.
@property (nonatomic, copy, readonly) NSDate *windowStart;
@property (nonatomic, copy, readonly) NSDate *windowEnd;

- (instancetype)initWithSSIDs:(nullable NSSet<NSString *> *)ssids
                       bssids:(nullable NSSet<NSString *> *)bssids
                   clientMACs:(nullable NSSet<NSString *> *)clientMACs
                     adapters:(nullable NSSet<NSString *> *)adapters
                     channels:(nullable NSSet<NSNumber *> *)channels
                  windowStart:(NSDate *)windowStart
                    windowEnd:(NSDate *)windowEnd NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark Time-window check

/// YES iff `date` falls within [windowStart, windowEnd].
- (BOOL)isWithinWindowAtDate:(NSDate *)date;
/// YES iff the window is open right now.
- (BOOL)isWithinWindowNow;

#pragma mark Membership queries (FAIL-CLOSED: explicit match required)

/// YES iff `ssid` is one of the authorized SSIDs (case-insensitive).
- (BOOL)containsSSID:(nullable NSString *)ssid;
/// YES iff `bssid` is one of the authorized BSSIDs (MAC-normalized).
- (BOOL)containsBSSID:(nullable NSString *)bssid;
/// YES iff `mac` is one of the authorized client MACs (MAC-normalized).
- (BOOL)containsClientMAC:(nullable NSString *)mac;
/// YES iff `adapter` is one of the authorized adapters (case-insensitive).
- (BOOL)containsAdapter:(nullable NSString *)adapter;
/// YES iff `channel` is one of the authorized channels.
- (BOOL)containsChannel:(NSInteger)channel;

#pragma mark Helpers

/// Compact, REDACTABLE summary of the scope (counts + window), suitable for
/// an audit context line. Does NOT dump the raw identifier lists.
- (NSString *)contextSummary;

/// Normalizes a MAC string for comparison (lowercase, separators stripped).
+ (nullable NSString *)normalizedMAC:(nullable NSString *)mac;

@end

NS_ASSUME_NONNULL_END
