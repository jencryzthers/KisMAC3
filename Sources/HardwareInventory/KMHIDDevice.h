/*
 File:        KMHIDDevice.h
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 Description: Clean model object for one HID device enumerated read-only from
              IOKit (IOServiceMatching(kIOHIDDeviceKey)). Covers keyboards,
              pointing devices, game controllers, presentation remotes, etc.
              Holds the HID usage-page / usage (which classifies the device),
              vendor + product id, product string, and transport.

              READ-ONLY: produced by enumerating the IORegistry. KisMAC NEVER
              opens an HID device or schedules it on a run loop -- this is pure
              diagnostics; no input is intercepted.

              PRIVACY: a HID serial is a stable hardware identifier and is
              sensitive; -redactedDescriptionWithSettings: masks it.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

@interface KMHIDDevice : NSObject

/// HID primary usage page (kHIDPage_*), or -1 when not exposed.
@property (nonatomic, assign) NSInteger usagePage;
/// HID primary usage (kHIDUsage_*), or -1 when not exposed.
@property (nonatomic, assign) NSInteger usage;

/// USB/HID vendor + product id, or -1 when not exposed.
@property (nonatomic, assign) NSInteger vendorID;
@property (nonatomic, assign) NSInteger productID;

/// Product string, or nil.
@property (nonatomic, copy, nullable) NSString *productName;
/// Manufacturer string, or nil.
@property (nonatomic, copy, nullable) NSString *manufacturer;

/// Transport ("USB"/"Bluetooth"/"SPI"/"BluetoothLowEnergy"/...), or nil.
@property (nonatomic, copy, nullable) NSString *transport;

/// HID serial number (SENSITIVE), or nil.
@property (nonatomic, copy, nullable) NSString *serialNumber;

/// Human-readable category derived from usage page/usage (e.g. "Keyboard",
/// "Pointing device", "Game controller", "Consumer/remote"). Never nil.
@property (nonatomic, copy, readonly) NSString *category;

/// A plain (UNREDACTED) dictionary representation for in-memory use / export.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description; pass nil for the fully redacted form.
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
