/*
 File:        KMBluetoothPermissionProvider.h
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 Description: Real KMBluetoothPermissionProviding for the capability engine,
              backed by +[KMBluetoothScanner currentAuthorizationState]. Reading
              the class-level CBManager.authorization does NOT instantiate a
              central manager (no radio spin / no prompt), so the engine can ask
              "is BLE authorized?" cheaply at build time. Injected by
              ScanController alongside the S4.1 scope + S4.2 adapter providers.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "../Capabilities/KMCapabilityEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface KMBluetoothPermissionProvider : NSObject <KMBluetoothPermissionProviding>
@end

NS_ASSUME_NONNULL_END
