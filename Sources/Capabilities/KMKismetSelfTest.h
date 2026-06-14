/*
 File:        KMKismetSelfTest.h
 Program:     KisMac3
 Slice:       S2.4 - Kismet remote/drone backend modernization

 Description: Headless, env-gated self-test for the modernized Kismet transport.
              Runs ONLY when KISMAC_KISMET_SELFTEST=1 is set. It points the new
              KMKismetTransport / WaveDriverKismet at a LOCAL MOCK Kismet server
              (Tests/Fixtures/mock_kismet_server.py, which the test launches on
              127.0.0.1 and which speaks the legacy *NETWORK: text protocol with
              known BSSIDs/SSIDs/channels) and asserts:

                1. the transport connects (non-blocking, bounded timeout),
                2. a refused connection fails CLOSED with a clear reason
                   (no silent failure / no hang),
                3. the driver ingests the expected network(s) from the mock
                   server (BSSID / channel parsed correctly).

              OFFLINE / PASSIVE: loopback only, no live radio, no monitor mode,
              no channel switching. Plaintext TCP by design (legacy Kismet).

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@interface KMKismetSelfTest : NSObject
/// Runs the self-test and logs PASS/FAIL. Returns YES on pass.
+ (BOOL)runSelfTestLogging;
@end
