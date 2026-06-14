/*
 File:        KMBluetoothSelfTest.h
 Program:     KisMac3
 Slice:       S3.1 - BLE inventory

 Description: Env-gated self-test (KISMAC_BLE_SELFTEST=1) for the S3.1 BLE
              surface. BLE needs a real authorization grant + radio that cannot
              be provided headlessly for an unsigned ad-hoc binary, so this test
              verifies what IS testable WITHOUT a grant:
                - KMBluetoothScanner initializes,
                - CBManager.authorization is read and mapped to a state,
                - the capability engine reports bleScan/bleGattEnumeration with
                  the correct state+reason given mock authorizations
                  (authorized=>available, denied/notDetermined=>permissionMissing,
                  restricted=>macOSBlocked) AND given THIS machine's live auth,
                - the device model + GATT model behave (de-dup, redaction),
              and, only when authorized + radio on, runs a brief live scan and
              logs the device count. Logs PASS/FAIL via DBNSLog.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMBluetoothSelfTest : NSObject
/// Runs the self-test and logs PASS/FAIL. Returns YES on pass.
+ (BOOL)runSelfTestLogging;
@end

NS_ASSUME_NONNULL_END
