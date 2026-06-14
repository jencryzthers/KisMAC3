/*
 File:        KMHardwareInventory.h
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 Description: Read-only IOKit collector that enumerates the USB, HID and serial
              (BSD tty) devices attached to this Mac. One-shot enumeration is the
              must-have; each -enumerate* method walks the IORegistry once and
              returns clean model objects.

              READ-ONLY DIAGNOSTICS: this collector NEVER opens, claims,
              configures, writes to, or otherwise interacts with any device. It
              only reads IORegistry properties (which needs no permission /
              authorization on macOS), so all three enumerations are honestly
              AVAILABLE in the capability engine.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMUSBDevice;
@class KMHIDDevice;
@class KMSerialDevice;

NS_ASSUME_NONNULL_BEGIN

@interface KMHardwareInventory : NSObject

/// One-shot read-only enumeration of USB devices via
/// IOServiceMatching(kIOUSBDeviceClassName). Returns [] on a sandbox/registry
/// error (never nil, never throws).
- (NSArray<KMUSBDevice *> *)enumerateUSBDevices;

/// One-shot read-only enumeration of HID devices via
/// IOServiceMatching(kIOHIDDeviceKey). Returns [] on error.
- (NSArray<KMHIDDevice *> *)enumerateHIDDevices;

/// One-shot read-only enumeration of serial (BSD tty) devices via
/// IOServiceMatching(kIOSerialBSDServiceValue). Returns [] on error.
- (NSArray<KMSerialDevice *> *)enumerateSerialDevices;

@end

NS_ASSUME_NONNULL_END
