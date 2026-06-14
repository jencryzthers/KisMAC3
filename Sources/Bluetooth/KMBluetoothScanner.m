/*
 File:        KMBluetoothScanner.m
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMBluetoothScanner.h"
#import "KMBluetoothDevice.h"
#import "KMGATTProfile.h"
#import "../Safety/KMPrivacySettings.h"
#import "../Safety/KMRedactionSettings.h"
#import <CoreBluetooth/CoreBluetooth.h>

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

NSString * const KMBluetoothScannerDidUpdateDevicesNotification        = @"KMBluetoothScannerDidUpdateDevicesNotification";
NSString * const KMBluetoothScannerAuthorizationChangedNotification    = @"KMBluetoothScannerAuthorizationChangedNotification";

NSString *KMStringFromBluetoothAuthState(KMBluetoothAuthState state) {
    switch (state) {
        case KMBluetoothAuthNotDetermined: return @"notDetermined";
        case KMBluetoothAuthRestricted:    return @"restricted";
        case KMBluetoothAuthDenied:        return @"denied";
        case KMBluetoothAuthAuthorized:    return @"authorized";
    }
    return @"unknown";
}

/// Maps a CBManagerAuthorization to our UI state.
static KMBluetoothAuthState KMMapCBAuthorization(CBManagerAuthorization a) {
    switch (a) {
        case CBManagerAuthorizationAllowedAlways: return KMBluetoothAuthAuthorized;
        case CBManagerAuthorizationDenied:        return KMBluetoothAuthDenied;
        case CBManagerAuthorizationRestricted:    return KMBluetoothAuthRestricted;
        case CBManagerAuthorizationNotDetermined: return KMBluetoothAuthNotDetermined;
    }
    return KMBluetoothAuthNotDetermined;
}

@interface KMBluetoothScanner () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) dispatch_queue_t btQueue;
/// identifier (UUID string) -> KMBluetoothDevice
@property (nonatomic, strong) NSMutableDictionary<NSString *, KMBluetoothDevice *> *devicesByID;
@property (nonatomic, assign, readwrite, getter=isScanning) BOOL scanning;
@property (nonatomic, assign, readwrite, getter=isRadioPoweredOn) BOOL radioPoweredOn;
@property (nonatomic, assign) BOOL wantsScan;        ///< start requested before powered-on
@property (nonatomic, assign) KMBluetoothAuthState lastAuthState;

// ---- GATT (one user-selected device at a time) ----
@property (nonatomic, strong, nullable) CBPeripheral *gattPeripheral;
@property (nonatomic, strong, nullable) KMGATTProfile *gattProfile;
@property (nonatomic, copy, nullable)   void (^gattCompletion)(KMGATTProfile *);
@property (nonatomic, assign) NSUInteger gattPendingServices; ///< chars still to discover
@end

@implementation KMBluetoothScanner

- (instancetype)init {
    if ((self = [super init])) {
        _btQueue = dispatch_queue_create("ca.gox.kismac.ble", DISPATCH_QUEUE_SERIAL);
        _devicesByID = [NSMutableDictionary dictionary];
        _lastAuthState = [[self class] currentAuthorizationState];
    }
    return self;
}

#pragma mark - Authorization

+ (KMBluetoothAuthState)currentAuthorizationState {
    // Class-level read: does NOT instantiate a CBCentralManager (no radio spin,
    // no prompt). Available on macOS 10.15+ (our deployment target is 13.0).
    return KMMapCBAuthorization([CBCentralManager authorization]);
}

- (KMBluetoothAuthState)authorizationState {
    // If we have a live manager, prefer its instance authorization (most
    // current); otherwise the class-level value.
    if (self.central) {
        return KMMapCBAuthorization(self.central.authorization);
    }
    return [[self class] currentAuthorizationState];
}

- (NSString *)remediation {
    switch (self.authorizationState) {
        case KMBluetoothAuthDenied:
            return @"Bluetooth access was denied. Grant it in System Settings > Privacy & Security > Bluetooth, then re-run the scan.";
        case KMBluetoothAuthRestricted:
            return @"Bluetooth is restricted on this Mac (device management / parental controls). BLE recon is unavailable.";
        case KMBluetoothAuthNotDetermined:
            return @"Bluetooth access has not been requested yet. Starting a scan will prompt for permission.";
        case KMBluetoothAuthAuthorized:
            if (!self.radioPoweredOn) {
                return @"Bluetooth is authorized but the radio is not powered on. Turn Bluetooth on.";
            }
            return nil;
    }
    return nil;
}

#pragma mark - Lazy central

- (void)ensureCentral {
    if (self.central) return;
    // Creating the manager triggers the system prompt when notDetermined.
    NSDictionary *opts = @{ CBCentralManagerOptionShowPowerAlertKey: @NO };
    self.central = [[CBCentralManager alloc] initWithDelegate:self
                                                       queue:self.btQueue
                                                     options:opts];
    DBNSLog(@"[S3.1 BLE] CBCentralManager created (auth=%@).",
            KMStringFromBluetoothAuthState(self.authorizationState));
}

#pragma mark - Scan control

- (void)startScan {
    KMBluetoothAuthState auth = self.authorizationState;
    if (auth == KMBluetoothAuthDenied || auth == KMBluetoothAuthRestricted) {
        DBNSLog(@"[S3.1 BLE] startScan refused: authorization=%@. %@",
                KMStringFromBluetoothAuthState(auth), self.remediation ?: @"");
        return;
    }
    self.wantsScan = YES;
    [self ensureCentral];
    dispatch_async(self.btQueue, ^{
        [self beginScanIfReady];
    });
}

/// Must run on btQueue.
- (void)beginScanIfReady {
    if (!self.wantsScan) return;
    if (!self.central || self.central.state != CBManagerStatePoweredOn) return;
    if (self.scanning) return;
    // Passive advertisement scan; AllowDuplicates so we can track last-seen/RSSI
    // and observation counts (proximity hint).
    [self.central scanForPeripheralsWithServices:nil
                                         options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @YES }];
    self.scanning = YES;
    DBNSLog(@"[S3.1 BLE] advertisement scan STARTED (passive, local-only, no auto-connect).");
}

- (void)stopScan {
    self.wantsScan = NO;
    dispatch_async(self.btQueue, ^{
        if (self.central && self.scanning) {
            [self.central stopScan];
        }
        self.scanning = NO;
        DBNSLog(@"[S3.1 BLE] advertisement scan STOPPED.");
    });
}

- (NSArray<KMBluetoothDevice *> *)discoveredDevices {
    __block NSArray *snapshot;
    dispatch_sync(self.btQueue, ^{
        NSArray *all = self.devicesByID.allValues;
        snapshot = [all sortedArrayUsingComparator:^NSComparisonResult(KMBluetoothDevice *a, KMBluetoothDevice *b) {
            return [b.lastSeen compare:a.lastSeen]; // most-recent first
        }];
    });
    return snapshot ?: @[];
}

- (void)resetDiscoveredDevices {
    dispatch_async(self.btQueue, ^{
        [self.devicesByID removeAllObjects];
        [self postDevicesUpdated];
    });
}

#pragma mark - Notifications (main thread)

- (void)postDevicesUpdated {
    NSArray<KMBluetoothDevice *> *devices = [self.devicesByID.allValues copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(bluetoothScanner:didUpdateDevices:)]) {
            [self.delegate bluetoothScanner:self didUpdateDevices:devices];
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:KMBluetoothScannerDidUpdateDevicesNotification object:self];
    });
}

- (void)postAuthorizationChanged:(KMBluetoothAuthState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(bluetoothScanner:didChangeAuthorization:)]) {
            [self.delegate bluetoothScanner:self didChangeAuthorization:state];
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:KMBluetoothScannerAuthorizationChangedNotification object:self];
    });
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    self.radioPoweredOn = (central.state == CBManagerStatePoweredOn);
    KMBluetoothAuthState auth = self.authorizationState;
    if (auth != self.lastAuthState) {
        self.lastAuthState = auth;
        [self postAuthorizationChanged:auth];
    }
    DBNSLog(@"[S3.1 BLE] central state=%ld poweredOn=%@ auth=%@",
            (long)central.state, self.radioPoweredOn ? @"Y" : @"N",
            KMStringFromBluetoothAuthState(auth));
    if (central.state == CBManagerStatePoweredOn) {
        [self beginScanIfReady];
    } else {
        self.scanning = NO; // radio gone: scanning implicitly stopped
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
    NSString *idKey = peripheral.identifier.UUIDString ?: @"";
    if (idKey.length == 0) return;

    KMBluetoothDevice *dev = self.devicesByID[idKey];
    BOOL isNew = (dev == nil);
    if (isNew) {
        dev = [[KMBluetoothDevice alloc] initWithIdentifier:idKey];
        self.devicesByID[idKey] = dev;
    }
    dev.lastSeen = [NSDate date];
    dev.observationCount += 1;
    dev.rssi = RSSI.integerValue;

    NSString *advName = advertisementData[CBAdvertisementDataLocalNameKey];
    if (advName.length) dev.localName = advName;
    else if (!dev.localName && peripheral.name.length) dev.localName = peripheral.name;

    NSArray<CBUUID *> *svc = advertisementData[CBAdvertisementDataServiceUUIDsKey];
    if (svc.count) {
        NSMutableArray *uuids = [NSMutableArray arrayWithCapacity:svc.count];
        for (CBUUID *u in svc) [uuids addObject:u.UUIDString];
        dev.serviceUUIDs = uuids;
    }
    NSData *mfg = advertisementData[CBAdvertisementDataManufacturerDataKey];
    if (mfg.length) dev.manufacturerData = mfg;

    NSNumber *connectable = advertisementData[CBAdvertisementDataIsConnectable];
    dev.connectable = connectable.boolValue;

    // Coalesce updates to avoid flooding the main thread on duplicate ads.
    [self postDevicesUpdated];
}

#pragma mark - GATT (user-selected device only)

- (void)enumerateGATTForDeviceIdentifier:(NSString *)identifier
                                 timeout:(NSTimeInterval)timeout
                              completion:(void (^)(KMGATTProfile *))completion {
    if (timeout <= 0) timeout = 12.0;
    [self ensureCentral];
    dispatch_async(self.btQueue, ^{
        KMGATTProfile *profile = [[KMGATTProfile alloc] initWithDeviceIdentifier:identifier ?: @""];

        if (self.authorizationState != KMBluetoothAuthAuthorized) {
            profile.errorReason = @"Bluetooth not authorized; cannot connect for GATT enumeration.";
            [self finishGATT:profile completion:completion];
            return;
        }
        if (self.central.state != CBManagerStatePoweredOn) {
            profile.errorReason = @"Bluetooth radio is not powered on.";
            [self finishGATT:profile completion:completion];
            return;
        }
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
        if (!uuid) {
            profile.errorReason = @"Invalid device identifier.";
            [self finishGATT:profile completion:completion];
            return;
        }
        NSArray<CBPeripheral *> *known =
            [self.central retrievePeripheralsWithIdentifiers:@[ uuid ]];
        CBPeripheral *peripheral = known.firstObject;
        if (!peripheral) {
            profile.errorReason = @"Device is not currently known to CoreBluetooth; scan for it first, then select it.";
            [self finishGATT:profile completion:completion];
            return;
        }

        // Stash state for the connect callbacks. NOTE: only ONE user-selected
        // device is enumerated at a time (privacy/safety: no fan-out connect).
        self.gattProfile    = profile;
        self.gattCompletion = completion;
        self.gattPeripheral = peripheral;
        peripheral.delegate = self;

        DBNSLog(@"[S3.1 BLE] GATT enumerate (USER-SELECTED) connecting to %@",
                [self redactedID:identifier]);
        [self.central connectPeripheral:peripheral options:nil];

        // Timeout guard.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                       self.btQueue, ^{
            if (self.gattProfile == profile && self.gattCompletion != nil) {
                profile.errorReason = profile.errorReason ?: @"GATT enumeration timed out.";
                if (self.gattPeripheral) [self.central cancelPeripheralConnection:self.gattPeripheral];
                [self finishGATT:profile completion:self.gattCompletion];
            }
        });
    });
}

/// Must run on btQueue. Clears state + dispatches completion on main.
- (void)finishGATT:(KMGATTProfile *)profile
        completion:(void (^)(KMGATTProfile *))completion {
    self.gattProfile = nil;
    self.gattCompletion = nil;
    self.gattPeripheral = nil;
    self.gattPendingServices = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(profile);
    });
}

- (NSString *)redactedID:(NSString *)identifier {
    KMRedactionSettings *r = [KMPrivacySettings sharedSettings].redaction;
    return [r redactBluetoothIdentifier:identifier] ?: @"****";
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
    if (peripheral != self.gattPeripheral) return;
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    if (peripheral != self.gattPeripheral) return;
    KMGATTProfile *p = self.gattProfile;
    p.errorReason = error.localizedDescription ?: @"Failed to connect.";
    [self finishGATT:p completion:self.gattCompletion];
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    if (peripheral != self.gattPeripheral) return;
    // If we still have a pending completion, the disconnect was unexpected.
    if (self.gattCompletion) {
        KMGATTProfile *p = self.gattProfile;
        if (!p.errorReason && error) p.errorReason = error.localizedDescription;
        [self finishGATT:p completion:self.gattCompletion];
    }
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error {
    if (peripheral != self.gattPeripheral) return;
    KMGATTProfile *p = self.gattProfile;
    if (error) {
        p.errorReason = error.localizedDescription;
        [self cancelConnection:peripheral onCentral:self.central];
        // No characteristics will arrive; deliver now.
        void (^cb)(KMGATTProfile *) = self.gattCompletion;
        [self finishGATT:p completion:cb];
        return;
    }
    NSMutableArray<KMGATTService *> *services = [NSMutableArray array];
    for (CBService *s in peripheral.services) {
        KMGATTService *gs = [[KMGATTService alloc] initWithUUID:s.UUID.UUIDString
                                                        primary:s.isPrimary];
        [services addObject:gs];
    }
    p.services = services;
    self.gattPendingServices = peripheral.services.count;
    if (self.gattPendingServices == 0) {
        [self cancelConnection:peripheral onCentral:self.central]; // nothing more to do
        void (^cb)(KMGATTProfile *) = self.gattCompletion;
        [self finishGATT:p completion:cb];
        return;
    }
    for (CBService *s in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:s];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
            error:(NSError *)error {
    if (peripheral != self.gattPeripheral) return;
    KMGATTProfile *p = self.gattProfile;
    // Attach the characteristics to the matching service model.
    for (KMGATTService *gs in p.services) {
        if ([gs.uuid isEqualToString:service.UUID.UUIDString]) {
            NSMutableArray<KMGATTCharacteristic *> *chars = [NSMutableArray array];
            for (CBCharacteristic *c in service.characteristics) {
                [chars addObject:[[KMGATTCharacteristic alloc]
                    initWithUUID:c.UUID.UUIDString properties:c.properties]];
            }
            gs.characteristics = chars;
            break;
        }
    }
    if (self.gattPendingServices > 0) self.gattPendingServices -= 1;
    if (self.gattPendingServices == 0) {
        DBNSLog(@"[S3.1 BLE] GATT enumerate complete: %lu service(s) on %@",
                (unsigned long)p.services.count, [self redactedID:p.deviceIdentifier]);
        [self cancelConnection:peripheral onCentral:self.central]; // disconnect
        // Deliver now (don't depend on the disconnect callback ordering).
        void (^cb)(KMGATTProfile *) = self.gattCompletion;
        [self finishGATT:p completion:cb];
    }
}

/// Small helper so we cancel a connection consistently.
- (void)cancelConnection:(CBPeripheral *)peripheral onCentral:(CBCentralManager *)central {
    if (central && peripheral) [central cancelPeripheralConnection:peripheral];
}

@end
