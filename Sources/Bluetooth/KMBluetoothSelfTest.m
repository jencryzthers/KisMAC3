/*
 File:        KMBluetoothSelfTest.m
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMBluetoothSelfTest.h"
#import "KMBluetoothScanner.h"
#import "KMBluetoothDevice.h"
#import "KMGATTProfile.h"
#import "KMBluetoothPermissionProvider.h"
#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMCapability.h"
#import "../Capabilities/KMHardwareCapability.h"
#import "../Safety/KMRedactionSettings.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

#pragma mark - Mock Bluetooth-permission providers

@interface KMMockBTAuthorized : NSObject <KMBluetoothPermissionProviding>
@end
@implementation KMMockBTAuthorized
- (BOOL)isBluetoothAuthorized { return YES; }
- (BOOL)isBluetoothRestricted { return NO; }
@end

@interface KMMockBTDenied : NSObject <KMBluetoothPermissionProviding>
@end
@implementation KMMockBTDenied
- (BOOL)isBluetoothAuthorized { return NO; }
- (BOOL)isBluetoothRestricted { return NO; }
@end

@interface KMMockBTRestricted : NSObject <KMBluetoothPermissionProviding>
@end
@implementation KMMockBTRestricted
- (BOOL)isBluetoothAuthorized { return NO; }
- (BOOL)isBluetoothRestricted { return YES; }
@end

@implementation KMBluetoothSelfTest

+ (NSArray<KMHardwareCapability *> *)mockGreenWiFi {
    return @[
        [KMHardwareCapability capabilityWithKey:KMCapWiFiInterfacePresent
            status:KMCapabilityStatusSupported reason:@"mock iface"],
        [KMHardwareCapability capabilityWithKey:KMCapLocationAuthorization
            status:KMCapabilityStatusSupported reason:@"mock granted"],
    ];
}

+ (KMCapabilityEngine *)engineWithBTProvider:(id<KMBluetoothPermissionProviding>)bt {
    return [[KMCapabilityEngine alloc]
        initWithHardwareCapabilities:[self mockGreenWiFi]
                       scopeProvider:nil
                     parserRegistry:nil
                    adapterProvider:nil
                  bluetoothProvider:bt];
}

+ (BOOL)runSelfTestLogging {
    NSMutableArray<NSString *> *fail = [NSMutableArray array];

    BOOL (^check)(NSString *, BOOL) = ^BOOL(NSString *label, BOOL cond) {
        if (cond) { DBNSLog(@"[KMBluetoothSelfTest]   PASS  %@", label); }
        else      { DBNSLog(@"[KMBluetoothSelfTest]   FAIL  %@", label); [fail addObject:label]; }
        return cond;
    };
    BOOL (^feat)(NSString *, KMCapabilityEngine *, NSString *,
                 KMCapabilityAvailability, KMCapabilityReason) =
    ^BOOL(NSString *label, KMCapabilityEngine *eng, NSString *key,
          KMCapabilityAvailability wantAvail, KMCapabilityReason wantReason) {
        KMCapability *c = [eng availabilityForCapability:key];
        BOOL ok = (c.availability == wantAvail) && (c.reason == wantReason);
        if (ok) DBNSLog(@"[KMBluetoothSelfTest]   PASS  %@ (got %@/%@)", label,
                        KMStringFromCapabilityAvailability(c.availability),
                        KMStringFromCapabilityReason(c.reason));
        else { DBNSLog(@"[KMBluetoothSelfTest]   FAIL  %@ -- got (%@/%@) want (%@/%@) -- %@",
                       label, KMStringFromCapabilityAvailability(c.availability),
                       KMStringFromCapabilityReason(c.reason),
                       KMStringFromCapabilityAvailability(wantAvail),
                       KMStringFromCapabilityReason(wantReason), c.explanation);
               [fail addObject:label]; }
        return ok;
    };

    DBNSLog(@"[KMBluetoothSelfTest] ===== S3.1 BLE inventory self-test =====");

    // ---- 1) Scanner initializes + reads/maps CBManager.authorization ----
    KMBluetoothScanner *scanner = [[KMBluetoothScanner alloc] init];
    check(@"1a scanner instantiates", scanner != nil);
    KMBluetoothAuthState live = [KMBluetoothScanner currentAuthorizationState];
    NSString *liveStr = KMStringFromBluetoothAuthState(live);
    check(@"1b class-level authorization read maps to a known state",
          [@[ @"notDetermined", @"restricted", @"denied", @"authorized" ] containsObject:liveStr]);
    check(@"1c instance authorizationState matches a known state",
          [@[ @"notDetermined", @"restricted", @"denied", @"authorized" ]
              containsObject:KMStringFromBluetoothAuthState(scanner.authorizationState)]);
    DBNSLog(@"[KMBluetoothSelfTest]   INFO  live CoreBluetooth authorization on THIS machine = %@", liveStr);
    if (live != KMBluetoothAuthAuthorized) {
        DBNSLog(@"[KMBluetoothSelfTest]   INFO  remediation: %@", scanner.remediation);
    }

    // ---- 2) Capability engine maps each authorization correctly ----
    feat(@"2a authorized => bleScan available",
         [self engineWithBTProvider:[KMMockBTAuthorized new]],
         KMFeatureBLEScan, KMCapabilityAvailable, KMCapabilityReasonNone);
    feat(@"2b authorized => bleGatt available",
         [self engineWithBTProvider:[KMMockBTAuthorized new]],
         KMFeatureBLEGattEnumeration, KMCapabilityAvailable, KMCapabilityReasonNone);
    feat(@"2c denied/notDetermined => bleScan permissionMissing",
         [self engineWithBTProvider:[KMMockBTDenied new]],
         KMFeatureBLEScan, KMCapabilityUnavailable, KMCapabilityReasonPermissionMissing);
    feat(@"2d denied/notDetermined => bleGatt permissionMissing",
         [self engineWithBTProvider:[KMMockBTDenied new]],
         KMFeatureBLEGattEnumeration, KMCapabilityUnavailable, KMCapabilityReasonPermissionMissing);
    feat(@"2e restricted => bleScan macOSBlocked",
         [self engineWithBTProvider:[KMMockBTRestricted new]],
         KMFeatureBLEScan, KMCapabilityUnavailable, KMCapabilityReasonMacOSBlocked);
    // Default (no provider) => fail closed permissionMissing.
    feat(@"2f default provider => bleScan permissionMissing (fail-closed)",
         [self engineWithBTProvider:nil],
         KMFeatureBLEScan, KMCapabilityUnavailable, KMCapabilityReasonPermissionMissing);

    // ---- 3) Engine vs THIS machine's live authorization (real provider) ----
    KMCapabilityEngine *liveEngine = [self engineWithBTProvider:[KMBluetoothPermissionProvider new]];
    KMCapability *liveScan = [liveEngine availabilityForCapability:KMFeatureBLEScan];
    DBNSLog(@"[KMBluetoothSelfTest]   INFO  engine bleScan on THIS machine = %@/%@ -- %@",
            KMStringFromCapabilityAvailability(liveScan.availability),
            KMStringFromCapabilityReason(liveScan.reason), liveScan.explanation);
    BOOL liveConsistent;
    switch (live) {
        case KMBluetoothAuthAuthorized:
            liveConsistent = (liveScan.availability == KMCapabilityAvailable); break;
        case KMBluetoothAuthRestricted:
            liveConsistent = (liveScan.reason == KMCapabilityReasonMacOSBlocked); break;
        default:
            liveConsistent = (liveScan.reason == KMCapabilityReasonPermissionMissing); break;
    }
    check(@"3a engine bleScan is consistent with live CB authorization", liveConsistent);

    // ---- 4) Device model: de-dup + redaction-safe description ----
    KMBluetoothDevice *d = [[KMBluetoothDevice alloc] initWithIdentifier:@"11223344-5566-7788-99AA-BBCCDDEEFF00"];
    d.localName = @"SecretBeacon";
    uint8_t mfg[] = { 0x4C, 0x00, 0x02, 0x15 }; // Apple company id 0x004C + iBeacon
    d.manufacturerData = [NSData dataWithBytes:mfg length:sizeof(mfg)];
    check(@"4a manufacturer company id parsed (Apple 0x004C)",
          [d manufacturerCompanyIdentifier] == 0x004C);
    KMRedactionSettings *r = [KMRedactionSettings defaultSettings];
    r.enabled = YES;
    NSString *redacted = [d redactedDescriptionWithSettings:r];
    check(@"4b redacted description does NOT contain raw identifier",
          [redacted rangeOfString:@"11223344-5566-7788-99AA-BBCCDDEEFF00"].location == NSNotFound);
    check(@"4c redacted description does NOT contain raw local name",
          [redacted rangeOfString:@"SecretBeacon"].location == NSNotFound);
    NSString *defaultDesc = [d description]; // default must be redacted too
    check(@"4d default -description is redacted (no raw identifier)",
          [defaultDesc rangeOfString:@"11223344-5566-7788-99AA-BBCCDDEEFF00"].location == NSNotFound);

    // ---- 5) GATT model basic shape ----
    KMGATTProfile *prof = [[KMGATTProfile alloc] initWithDeviceIdentifier:@"X"];
    KMGATTService *svc = [[KMGATTService alloc] initWithUUID:@"180A" primary:YES];
    KMGATTCharacteristic *ch = [[KMGATTCharacteristic alloc] initWithUUID:@"2A29" properties:0x02 /*read*/];
    svc.characteristics = @[ ch ];
    prof.services = @[ svc ];
    check(@"5a GATT characteristic properties decode (read)",
          [ch.propertiesDescription rangeOfString:@"read"].location != NSNotFound);
    check(@"5b GATT profile dictionaryRepresentation has services",
          [[prof dictionaryRepresentation][@"services"] count] == 1);

    // ---- 6) Optional brief LIVE scan (only when authorized + radio on) ----
    if (live == KMBluetoothAuthAuthorized) {
        DBNSLog(@"[KMBluetoothSelfTest]   INFO  authorized -- running a brief 3s live advertisement scan...");
        [scanner startScan];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3.0];
        while ([until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        }
        [scanner stopScan];
        NSUInteger n = [scanner discoveredDevices].count;
        DBNSLog(@"[KMBluetoothSelfTest]   INFO  brief live scan saw %lu BLE device(s).", (unsigned long)n);
        check(@"6a live scan completed without crash", YES);
    } else {
        DBNSLog(@"[KMBluetoothSelfTest]   SKIP  live advertisement scan + GATT enumeration require a SIGNED build + a human Bluetooth grant (auth=%@). Cannot be exercised headlessly on an unsigned ad-hoc binary.", liveStr);
    }

    BOOL pass = (fail.count == 0);
    if (pass) {
        DBNSLog(@"[KMBluetoothSelfTest] PASS - scanner init + authorization mapping + engine bleScan/bleGatt gating + model redaction held.");
        DBNSLog(@"[KMBluetoothSelfTest] NOTE - actual BLE advertisements + GATT connect/enumerate require a SIGNED build and a human granting Bluetooth in System Settings; only the permission-mapping + models are verified headlessly.");
    } else {
        DBNSLog(@"[KMBluetoothSelfTest] FAIL - %lu assertion(s):", (unsigned long)fail.count);
        for (NSString *l in fail) DBNSLog(@"[KMBluetoothSelfTest]   - %@", l);
    }
    return pass;
}

@end
