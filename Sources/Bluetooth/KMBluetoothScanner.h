/*
 File:        KMBluetoothScanner.h
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 Description: CoreBluetooth-backed BLE advertisement scanner + on-demand GATT
              enumerator. Wraps a CBCentralManager.

              CAPABILITIES:
                - start/stop a passive advertisement scan (CBCentralManager
                  scanForPeripheralsWithServices:nil) and accumulate one
                  KMBluetoothDevice per peripheral identifier (de-duped, with
                  first/last-seen + observation count + latest RSSI).
                - read/map CBManager.authorization to a clear KMBluetoothAuthState
                  (+ remediation text).
                - GATT enumeration for a USER-SELECTED device only
                  (enumerateGATTForDeviceIdentifier:completion:). NEVER
                  auto-connects: a connect happens ONLY for an identifier the
                  user explicitly passes.

              NOTIFICATIONS: posts KMBluetoothScannerDidUpdateDevicesNotification
              on the main thread when the device set changes, and
              KMBluetoothScannerAuthorizationChangedNotification when the
              CoreBluetooth authorization state changes. A delegate is also
              available for in-process consumers.

              PRIVACY: local-only; no auto-connect; identifiers are sensitive
              and are redacted in this class's own logging via KMRedactionSettings.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMBluetoothDevice;
@class KMGATTProfile;
@class KMBluetoothScanner;

NS_ASSUME_NONNULL_BEGIN

/// Posted (main thread) when the discovered-device set changes.
extern NSString * const KMBluetoothScannerDidUpdateDevicesNotification;
/// Posted (main thread) when CoreBluetooth authorization changes.
extern NSString * const KMBluetoothScannerAuthorizationChangedNotification;

/// Clear, UI-facing Bluetooth authorization state (maps CBManagerAuthorization).
typedef NS_ENUM(NSInteger, KMBluetoothAuthState) {
    KMBluetoothAuthNotDetermined = 0, ///< Not yet asked; a scan will prompt.
    KMBluetoothAuthRestricted,        ///< Restricted by policy (MDM/parental).
    KMBluetoothAuthDenied,            ///< User denied; needs Settings remediation.
    KMBluetoothAuthAuthorized         ///< Authorized; scanning permitted.
};

/// Stable token for an auth state (logging / persistence).
extern NSString *KMStringFromBluetoothAuthState(KMBluetoothAuthState state);

@protocol KMBluetoothScannerDelegate <NSObject>
@optional
- (void)bluetoothScanner:(KMBluetoothScanner *)scanner
        didUpdateDevices:(NSArray<KMBluetoothDevice *> *)devices;
- (void)bluetoothScanner:(KMBluetoothScanner *)scanner
 didChangeAuthorization:(KMBluetoothAuthState)state;
@end

@interface KMBluetoothScanner : NSObject

@property (nonatomic, weak, nullable) id<KMBluetoothScannerDelegate> delegate;

/// Current CoreBluetooth authorization, mapped to KMBluetoothAuthState. Safe to
/// read without starting a scan (uses the class-level CBManager.authorization).
@property (nonatomic, readonly) KMBluetoothAuthState authorizationState;

/// YES once the underlying CBCentralManager reports powered-on.
@property (nonatomic, readonly, getter=isRadioPoweredOn) BOOL radioPoweredOn;

/// YES while a scan is active.
@property (nonatomic, readonly, getter=isScanning) BOOL scanning;

/// Human-readable remediation for the current auth/radio state (or nil when OK).
@property (nonatomic, readonly, copy, nullable) NSString *remediation;

/// Returns the class-level CoreBluetooth authorization WITHOUT instantiating a
/// central manager. Used by the capability engine's permission provider so it
/// never spins up a radio just to read permission.
+ (KMBluetoothAuthState)currentAuthorizationState;

/// Start a passive advertisement scan. On first call this lazily creates the
/// CBCentralManager (which triggers the system Bluetooth prompt if
/// notDetermined). No-op (logged) if authorization is denied/restricted.
- (void)startScan;

/// Stop the advertisement scan. Safe to call when not scanning.
- (void)stopScan;

/// Snapshot of the devices discovered so far (most-recently-seen first).
- (NSArray<KMBluetoothDevice *> *)discoveredDevices;

/// Clear the accumulated device set.
- (void)resetDiscoveredDevices;

/// Enumerate GATT services + characteristics for a USER-SELECTED device.
/// Connects ONLY to the given identifier (no auto-connect to others), discovers
/// services + characteristics, disconnects, and calls `completion` on the main
/// thread with a KMGATTProfile (its errorReason is set on failure/timeout).
/// `timeout` <= 0 uses a sane default.
- (void)enumerateGATTForDeviceIdentifier:(NSString *)identifier
                                 timeout:(NSTimeInterval)timeout
                              completion:(void (^)(KMGATTProfile *profile))completion;

@end

NS_ASSUME_NONNULL_END
