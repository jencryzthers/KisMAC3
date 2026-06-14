/*
 File:        KMSerialDevice.h
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 Description: Clean model object for one serial (BSD tty) device enumerated
              read-only from IOKit (IOServiceMatching(kIOSerialBSDServiceValue)).
              Reports the callout (/dev/cu.*) and dialin (/dev/tty.*) paths plus
              the IOTTYBaseName. This is what surfaces USB-UART adapters and GPS
              receivers (it ties to the GPS serial-path selection elsewhere in
              KisMAC).

              READ-ONLY: produced by enumerating the IORegistry. KisMAC NEVER
              opens the tty here -- this is pure discovery; the GPS controller
              owns any later open of a user-selected path.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

@interface KMSerialDevice : NSObject

/// IOTTYBaseName (e.g. "usbserial-0001", "Bluetooth-Incoming-Port"), or nil.
@property (nonatomic, copy, nullable) NSString *baseName;
/// Callout device path (/dev/cu.*) -- the path used for outgoing/GPS, or nil.
@property (nonatomic, copy, nullable) NSString *calloutDevice;
/// Dialin device path (/dev/tty.*), or nil.
@property (nonatomic, copy, nullable) NSString *dialinDevice;
/// IOTTYSuffix, or nil.
@property (nonatomic, copy, nullable) NSString *suffix;

/// YES if the base name / path looks like a USB-UART or GPS receiver (heuristic
/// over the base name: "usbserial"/"usbmodem"/"UART"/"GPS"/"SLAB"/"FTDI"/etc.).
@property (nonatomic, assign, readonly) BOOL looksLikeUARTOrGPS;

/// A plain dictionary representation for in-memory use / export.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description. Serial-port paths are not personal
/// identifiers, so redaction leaves them intact; pass nil for the default form.
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
