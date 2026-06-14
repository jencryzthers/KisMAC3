/*
 File:        KMUSBDevice.h
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 Description: Clean model object for one USB device enumerated read-only from
              IOKit (IOServiceMatching(kIOUSBDeviceClassName) / IOUSBHostDevice).
              Holds the device facts a recon UI / report needs: vendor + product
              id, vendor + product name, USB device class/subclass, serial where
              the device exposes it, the IOKit location id + service path, and
              the negotiated speed when available.

              READ-ONLY: this model is produced by enumerating the IORegistry.
              KisMAC NEVER opens, claims, configures, or writes to any USB
              device -- this is pure diagnostics.

              PRIVACY: a USB serial number is a stable hardware identifier and is
              sensitive. The model stores the raw value (it is what the IORegistry
              exposes) but -redactedDescriptionWithSettings: masks it so logs /
              reports never have to dump it unredacted.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

@interface KMUSBDevice : NSObject

/// USB vendor id (idVendor), or -1 when not exposed.
@property (nonatomic, assign) NSInteger vendorID;
/// USB product id (idProduct), or -1 when not exposed.
@property (nonatomic, assign) NSInteger productID;

/// USB vendor / manufacturer string descriptor, or nil.
@property (nonatomic, copy, nullable) NSString *vendorName;
/// USB product string descriptor, or nil.
@property (nonatomic, copy, nullable) NSString *productName;

/// bDeviceClass / bDeviceSubClass, or -1 when not exposed.
@property (nonatomic, assign) NSInteger deviceClass;
@property (nonatomic, assign) NSInteger deviceSubClass;

/// USB serial-number string descriptor (SENSITIVE), or nil.
@property (nonatomic, copy, nullable) NSString *serialNumber;

/// IOKit location id (the topology address on the bus), or nil.
@property (nonatomic, copy, nullable) NSString *locationID;
/// IORegistry service path for the device (connection/topology path).
@property (nonatomic, copy, nullable) NSString *servicePath;

/// Negotiated device speed string ("low"/"full"/"high"/"super"/"super+"), or nil.
@property (nonatomic, copy, nullable) NSString *speed;

/// A plain (UNREDACTED) dictionary representation for in-memory use / export
/// where the caller is responsible for redaction.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description. When `settings` redacts MAC/Bluetooth
/// identifiers the serial number is masked; pass nil to get the fully redacted
/// form (safe default for logs).
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
