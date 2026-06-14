/*
 File:        KMGATTProfile.h
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 Description: Result model for a GATT (services + characteristics) enumeration
              of a USER-SELECTED BLE device. KisMac3 NEVER auto-connects: a
              connect+discover only happens when the user explicitly picks a
              device (privacy/safety). These value objects carry what was
              discovered after such a connect.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One discovered GATT characteristic.
@interface KMGATTCharacteristic : NSObject
@property (nonatomic, copy)   NSString *uuid;
/// CBCharacteristicProperties bitmask (read/write/notify/...).
@property (nonatomic, assign) NSUInteger properties;
/// Human-readable property list (e.g. "read, notify").
@property (nonatomic, copy, readonly) NSString *propertiesDescription;
- (instancetype)initWithUUID:(NSString *)uuid properties:(NSUInteger)properties;
@end

/// One discovered GATT service and its characteristics.
@interface KMGATTService : NSObject
@property (nonatomic, copy)   NSString *uuid;
@property (nonatomic, assign, getter=isPrimary) BOOL primary;
@property (nonatomic, copy)   NSArray<KMGATTCharacteristic *> *characteristics;
- (instancetype)initWithUUID:(NSString *)uuid primary:(BOOL)primary;
@end

/// The full result of enumerating one device.
@interface KMGATTProfile : NSObject
/// The device identifier (CoreBluetooth UUID) that was enumerated.
@property (nonatomic, copy)   NSString *deviceIdentifier;
@property (nonatomic, copy)   NSArray<KMGATTService *> *services;
/// Populated when enumeration failed (connect refused/timeout/disconnect).
@property (nonatomic, copy, nullable) NSString *errorReason;
- (instancetype)initWithDeviceIdentifier:(NSString *)identifier;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

NS_ASSUME_NONNULL_END
