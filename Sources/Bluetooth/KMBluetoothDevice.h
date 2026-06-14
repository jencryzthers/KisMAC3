/*
 File:        KMBluetoothDevice.h
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 Description: Clean model object for one observed Bluetooth Low Energy device.
              Captured from CoreBluetooth advertisement callbacks during a
              passive scan. Holds the per-device facts the recon UI / report
              needs: the (CoreBluetooth-scoped) identifier UUID, advertised
              local name, advertised service UUIDs, raw manufacturer data,
              latest RSSI, connectability where the OS exposes it, and the
              first/last-seen timestamps.

              PRIVACY: a Bluetooth identifier is sensitive. The model stores
              the raw value (needed for de-dup + a user-initiated GATT connect)
              but exposes -redactedDescriptionWithSettings: so logs / reports
              never have to dump it unredacted. macOS hands apps a per-app
              random UUID for unpaired peripherals (NOT the hardware MAC), but
              we still treat it as sensitive.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

@interface KMBluetoothDevice : NSObject

/// CoreBluetooth peripheral identifier (a per-app random UUID for unpaired
/// devices, not the hardware address). Stable for the life of the scan and the
/// handle used for a user-initiated GATT connect.
@property (nonatomic, copy, readonly) NSString *identifier;

/// Advertised local name (CBAdvertisementDataLocalNameKey), or nil.
@property (nonatomic, copy, nullable) NSString *localName;

/// Advertised service UUID strings (CBAdvertisementDataServiceUUIDsKey).
@property (nonatomic, copy) NSArray<NSString *> *serviceUUIDs;

/// Raw manufacturer-specific data (CBAdvertisementDataManufacturerDataKey).
@property (nonatomic, copy, nullable) NSData *manufacturerData;

/// Most recent RSSI (dBm). 127 means "not available" per CoreBluetooth.
@property (nonatomic, assign) NSInteger rssi;

/// YES iff the advertisement marked the peripheral connectable
/// (CBAdvertisementDataIsConnectable). nil-equivalent absence is reported as NO.
@property (nonatomic, assign, getter=isConnectable) BOOL connectable;

/// Number of advertisement frames observed (proximity / activity hint).
@property (nonatomic, assign) NSUInteger observationCount;

/// First and last time this identifier was seen during the scan.
@property (nonatomic, copy, readonly) NSDate *firstSeen;
@property (nonatomic, copy) NSDate *lastSeen;

/// Designated init. `firstSeen`/`lastSeen` default to now.
- (instancetype)initWithIdentifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Best 16-bit manufacturer company identifier parsed from the first two
/// little-endian bytes of manufacturerData, or -1 when absent/too short.
- (NSInteger)manufacturerCompanyIdentifier;

/// A plain (UNREDACTED) dictionary representation for in-memory use / export
/// where the caller is responsible for redaction.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description. When `settings` redacts Bluetooth
/// identifiers the identifier + local name are masked; pass nil to get the
/// fully redacted form (safe default for logs).
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
