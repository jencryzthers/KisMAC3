/*
 File:        KMKismetSelfTest.m
 Program:     KisMac3
 Slice:       S2.4 - Kismet remote/drone backend modernization

 Description: See KMKismetSelfTest.h. Loopback only / plaintext / passive.

 This file is part of KisMAC. GPL v2.
 */

#import "KMKismetSelfTest.h"
#import "KMKismetTransport.h"
#import "../WaveDrivers/WaveDriverKismet.h"

// The mock server emits these two networks (kept in sync with
// Tests/Fixtures/mock_kismet_server.py).
//   *NETWORK: 00:11:22:33:44:55 0 0 -42 54 6 \x01TestNetOne\x01
//   *NETWORK: AA:BB:CC:DD:EE:FF 0 2 -55 54 11 \x01SecureNet\x01
static const uint8_t kExpectedBSSID1[6] = {0x00,0x11,0x22,0x33,0x44,0x55};
static const uint8_t kExpectedBSSID2[6] = {0xAA,0xBB,0xCC,0xDD,0xEE,0xFF};

@implementation KMKismetSelfTest

#pragma mark - Mock server lifecycle

+ (NSString *)mockServerScriptPath
{
    // Bundled as a resource for a built app; also try the source tree for a
    // dev run from the repo root.
    NSString *p = [[NSBundle mainBundle] pathForResource:@"mock_kismet_server" ofType:@"py"];
    if (p) return p;
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *guess = [cwd stringByAppendingPathComponent:@"Tests/Fixtures/mock_kismet_server.py"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:guess]) return guess;
    // Env override.
    NSString *env = [[NSProcessInfo processInfo] environment][@"KISMAC_KISMET_MOCK"];
    if (env.length && [[NSFileManager defaultManager] fileExistsAtPath:env]) return env;
    return nil;
}

+ (NSTask *)launchMockServerOnPort:(int)port script:(NSString *)script
{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = @[@"python3", script, @"127.0.0.1", [@(port) stringValue]];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    @try {
        [task launch];
    } @catch (NSException *ex) {
        DBNSLog(@"[KISMET-SELFTEST] failed to launch mock server: %@", ex);
        return nil;
    }
    // Give it a moment to bind/listen.
    [NSThread sleepForTimeInterval:0.8];
    return task;
}

#pragma mark - Test 1: transport connects + parses via the driver

+ (BOOL)testDriverIngestOnPort:(int)port
{
    // Point the driver at the mock server via NSUserDefaults (its config source).
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    id saved = [defs objectForKey:@"ActiveDrivers"];
    [defs setObject:@[@{@"driverID": @"WaveDriverKismet",
                        @"kismetserverhost": @"127.0.0.1",
                        @"kismetserverport": @(port)}]
             forKey:@"ActiveDrivers"];

    BOOL ok = NO;
    WaveDriverKismet *drv = [[WaveDriverKismet alloc] init];
    if (![drv startedScanning]) {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: driver could not connect to mock server on :%d", port);
        goto done;
    }

    // Poll networksInRange a few times; the mock server sends the lines shortly
    // after the subscribe command arrives.
    BOOL sawNet1 = NO, sawNet2 = NO;
    for (int attempt = 0; attempt < 30 && !(sawNet1 && sawNet2); ++attempt) {
        NSArray *nets = [drv networksInRange];
        for (NSDictionary *net in nets) {
            NSData *bssid = net[@"BSSID"];
            if (bssid.length == 6) {
                if (memcmp(bssid.bytes, kExpectedBSSID1, 6) == 0) sawNet1 = YES;
                if (memcmp(bssid.bytes, kExpectedBSSID2, 6) == 0) sawNet2 = YES;
            }
        }
        if (!(sawNet1 && sawNet2)) [NSThread sleepForTimeInterval:0.1];
    }
    [drv stopCapture];

    if (sawNet1 && sawNet2) {
        DBNSLog(@"[KISMET-SELFTEST] PASS: driver ingested both mock networks "
                @"(00:11:22:33:44:55 + AA:BB:CC:DD:EE:FF) over the modernized transport.");
        ok = YES;
    } else {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: missing networks (net1=%d net2=%d)", sawNet1, sawNet2);
    }

done:
    if (saved) [defs setObject:saved forKey:@"ActiveDrivers"];
    else [defs removeObjectForKey:@"ActiveDrivers"];
    return ok;
}

#pragma mark - Test 2: refused connection fails CLOSED (no silent failure / no hang)

+ (BOOL)testRefusedFailsClosed
{
    // Port 1 on loopback: nothing listens -> connect must fail fast with a
    // reason, not hang. (Bounded by the transport's own connect timeout.)
    KMKismetTransport *t = [[KMKismetTransport alloc] initWithHost:@"127.0.0.1" port:1];
    NSDate *start = [NSDate date];
    BOOL connected = [t connectWithTimeout:5.0];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    [t close];

    if (connected) {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: connect to a dead port unexpectedly succeeded.");
        return NO;
    }
    if (!t.isFailed || t.lastError == nil) {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: refused connection did not set isFailed/lastError (silent failure).");
        return NO;
    }
    if (elapsed > 6.0) {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: refused connect took %.1fs (should fail fast, not hang).", elapsed);
        return NO;
    }
    DBNSLog(@"[KISMET-SELFTEST] PASS: refused connection failed closed in %.2fs with reason: %@",
            elapsed, [t lastErrorReason]);
    return YES;
}

#pragma mark - Entry

+ (BOOL)runSelfTestLogging
{
    DBNSLog(@"[KISMET-SELFTEST] start [loopback mock server, legacy plaintext "
            @"*NETWORK: protocol; no live radio / monitor / channel switching]");

    BOOL allPass = YES;

    // Test 2 first (needs no server).
    allPass &= [self testRefusedFailsClosed];

    // Test 1 needs the mock server.
    NSString *script = [self mockServerScriptPath];
    if (!script) {
        DBNSLog(@"[KISMET-SELFTEST] FAIL: mock_kismet_server.py not found "
                @"(bundle / Tests/Fixtures / $KISMAC_KISMET_MOCK).");
        allPass = NO;
    } else {
        int port = 27410; // arbitrary high port for the mock legacy server
        NSTask *server = [self launchMockServerOnPort:port script:script];
        if (!server) {
            allPass = NO;
        } else {
            allPass &= [self testDriverIngestOnPort:port];
            [server terminate];
            [server waitUntilExit];
        }
    }

    DBNSLog(@"[KISMET-SELFTEST] %@", allPass ? @"PASS - all assertions held" : @"FAIL");
    return allPass;
}

@end
