/*
 File:        KMBluetoothPermissionProvider.m
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMBluetoothPermissionProvider.h"
#import "KMBluetoothScanner.h"

@implementation KMBluetoothPermissionProvider

- (BOOL)isBluetoothAuthorized {
    return [KMBluetoothScanner currentAuthorizationState] == KMBluetoothAuthAuthorized;
}

- (BOOL)isBluetoothRestricted {
    return [KMBluetoothScanner currentAuthorizationState] == KMBluetoothAuthRestricted;
}

@end
